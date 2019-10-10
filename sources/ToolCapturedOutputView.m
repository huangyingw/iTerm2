//
//  ToolCapturedOutput.m
//  iTerm
//
//  Created by George Nachman on 5/22/14.
//
//

#import "ToolCapturedOutputView.h"

#import "CapturedOutput.h"
#import "CaptureTrigger.h"
#import "iTermCapturedOutputMark.h"
#import "iTermCommandHistoryCommandUseMO+Additions.h"
#import "iTermSearchField.h"
#import "iTermToolbeltView.h"
#import "iTermToolWrapper.h"
#import "NSTableColumn+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "ToolCommandHistoryView.h"

static const CGFloat kMargin = 4;
static const CGFloat kButtonHeight = 23;
static NSString *const iTermCapturedOutputToolTableViewCellIdentifier = @"ToolCapturedOutputEntryIdentifier";

@interface ToolCapturedOutputView() <
    ToolbeltTool,
    NSMenuDelegate,
    NSSearchFieldDelegate,
    NSTextFieldDelegate>
@end

@implementation ToolCapturedOutputView {
    NSScrollView *scrollView_;
    NSTableView *tableView_;
    BOOL shutdown_;
    NSArray *allCapturedOutput_;
    NSTableCellView *_measuringCellView;
    VT100ScreenMark *mark_;  // Mark from which captured output came
    iTermSearchField *searchField_;
    NSButton *help_;
    NSButton *_clearButton;
    NSArray *filteredEntries_;
}

@synthesize tableView = tableView_;

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        help_ = [[NSButton alloc] initWithFrame:CGRectZero];
        [help_ setBezelStyle:NSHelpButtonBezelStyle];
        [help_ setButtonType:NSMomentaryPushInButton];
        [help_ setBordered:YES];
        [help_ sizeToFit];
        help_.target = self;
        help_.action = @selector(help:);
        help_.title = @"";
        [help_ setAutoresizingMask:NSViewMinXMargin];
        [self addSubview:help_];

        _clearButton = [[NSButton alloc] initWithFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight)];
        [_clearButton setButtonType:NSMomentaryPushInButton];
        [_clearButton setTitle:@"Clear"];
        [_clearButton setTarget:self];
        [_clearButton setAction:@selector(clear:)];
        [_clearButton setBezelStyle:NSSmallSquareBezelStyle];
        [_clearButton sizeToFit];
        [_clearButton setAutoresizingMask:NSViewMinYMargin];
        [self addSubview:_clearButton];

        searchField_ = [[iTermSearchField alloc] initWithFrame:CGRectZero];
        [searchField_ sizeToFit];
        searchField_.autoresizingMask = NSViewWidthSizable;
        searchField_.frame = NSMakeRect(0, 0, frame.size.width, searchField_.frame.size.height);
        ITERM_IGNORE_PARTIAL_BEGIN
        [searchField_ setDelegate:self];
        ITERM_IGNORE_PARTIAL_END
        [self addSubview:searchField_];

        scrollView_ = [[NSScrollView alloc] initWithFrame:CGRectZero];
        [scrollView_ setHasVerticalScroller:YES];
        [scrollView_ setHasHorizontalScroller:NO];
        [scrollView_ setBorderType:NSBezelBorder];
        NSSize contentSize = [scrollView_ contentSize];
        [scrollView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        if (@available(macOS 10.14, *)) { } else {
            scrollView_.drawsBackground = NO;
        }
        
        tableView_ = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
        NSTableColumn *col;
        col = [[NSTableColumn alloc] initWithIdentifier:@"contents"];
        [col setEditable:NO];
        [tableView_ addTableColumn:col];
        [[col headerCell] setStringValue:@"Contents"];
        NSFont *theFont = [NSFont fontWithName:@"Menlo" size:11];
        [[col dataCell] setFont:theFont];
        tableView_.rowHeight = col.suggestedRowHeight;
        [tableView_ setHeaderView:nil];
        [tableView_ setDataSource:self];
        [tableView_ setDelegate:self];
        NSSize spacing = tableView_.intercellSpacing;
        spacing.height += 5;
        tableView_.intercellSpacing = spacing;

        [tableView_ setDoubleAction:@selector(doubleClickOnTableView:)];
        [tableView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

        tableView_.menu = [[NSMenu alloc] init];
        tableView_.menu.delegate = self;
        NSMenuItem *item;
        item = [[NSMenuItem alloc] initWithTitle:@"Toggle Checkmark"
                                          action:@selector(toggleCheckmark:)
                                   keyEquivalent:@""];
        [tableView_.menu addItem:item];

        [searchField_ setArrowHandler:tableView_];

        [scrollView_ setDocumentView:tableView_];
        [self addSubview:scrollView_];

        [tableView_ setColumnAutoresizingStyle:NSTableViewSequentialColumnAutoresizingStyle];

        [self relayout];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(capturedOutputDidChange:)
                                                     name:kPTYSessionCapturedOutputDidChange
                                                   object:nil];
        [self updateCapturedOutput];
    }
    return self;
}

- (void)removeSelection {
    mark_ = nil;
    [tableView_ selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
    [self updateCapturedOutput];
}

- (void)updateCapturedOutput {
    iTermToolWrapper *wrapper = self.toolWrapper;
    ToolCommandHistoryView *commandHistoryView = [wrapper.delegate commandHistoryView];
    iTermCommandHistoryCommandUseMO *commandUse = [commandHistoryView selectedCommandUse];
    VT100ScreenMark *mark;
    NSArray *theArray;
    if (commandUse) {
        mark = commandUse.mark;
    } else {
        mark = [wrapper.delegate.delegate toolbeltLastCommandMark];
    }
    theArray = mark.capturedOutput;
    if (mark != mark_) {
        [tableView_ selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
        mark_ = mark;
    }

    allCapturedOutput_ = [theArray copy];

    // Now update filtered entries based on search string.
    NSMutableArray *temp = [NSMutableArray array];
    for (CapturedOutput *capturedOutput in allCapturedOutput_) {
        if (!searchField_.stringValue.length ||
            [[self labelForCapturedOutput:capturedOutput] rangeOfString:searchField_.stringValue
                                                                options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [temp addObject:capturedOutput];
        }
    }
    filteredEntries_ = temp;

    [tableView_ reloadData];

    // Updating the table data causes the cursor to change into an arrow!
    [self performSelector:@selector(fixCursor) withObject:nil afterDelay:0];
}

- (void)shutdown {
    shutdown_ = YES;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)relayout {
    NSRect frame = self.frame;

    // Search field
    NSRect searchFieldFrame = NSMakeRect(0,
                                         0,
                                         frame.size.width - help_.frame.size.width - _clearButton.frame.size.width - 2 * kMargin,
                                         searchField_.frame.size.height);
    searchField_.frame = searchFieldFrame;

    // Help button
    help_.frame = NSMakeRect(frame.size.width - help_.frame.size.width,
                             1,
                             help_.frame.size.width,
                             help_.frame.size.height);

    _clearButton.frame = NSMakeRect(help_.frame.origin.x - _clearButton.frame.size.width - kMargin,
                                    1,
                                    _clearButton.frame.size.width,
                                    _clearButton.frame.size.height);

    // Scroll view
    [scrollView_ setFrame:NSMakeRect(0,
                                     searchFieldFrame.size.height + kMargin,
                                     frame.size.width,
                                     frame.size.height - 2 * kMargin)];

    // Table view
    NSSize contentSize = [scrollView_ contentSize];
    NSTableColumn *column = tableView_.tableColumns[0];
    column.minWidth = contentSize.width;
    column.maxWidth = contentSize.width;
    [tableView_ sizeToFit];
    [tableView_ reloadData];
}

- (BOOL)isFlipped {
    return YES;
}

- (void)clear:(id)sender {
    allCapturedOutput_ = [[NSMutableArray alloc] init];
    filteredEntries_ = [[NSMutableArray alloc] init];

    [tableView_ reloadData];

    // Updating the table data causes the cursor to change into an arrow!
    [self performSelector:@selector(fixCursor) withObject:nil afterDelay:0];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    _clearButton.enabled = (filteredEntries_.count > 0);
    return filteredEntries_.count;
}

- (NSTableCellView *)newTextField {
    NSTableCellView *cellView = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
    NSTextField *textField = [NSTextField it_textFieldForTableViewWithIdentifier:iTermCapturedOutputToolTableViewCellIdentifier];;
    textField.maximumNumberOfLines = 0;
    textField.lineBreakMode = NSLineBreakByCharWrapping;
    textField.usesSingleLineMode = NO;
    textField.font = [NSFont fontWithName:@"Menlo" size:11];
    cellView.textField = textField;
    [cellView addSubview:textField];
    textField.translatesAutoresizingMaskIntoConstraints = NO;
    NSDictionary *views = NSDictionaryOfVariableBindings(textField);
    [cellView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[textField]-0-|"
                                                                     options:0
                                                                     metrics:nil
                                                                       views:views]];
    [cellView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[textField]-0-|"
                                                                     options:0
                                                                     metrics:nil
                                                                       views:views]];
    return cellView;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTableCellView *result = [tableView makeViewWithIdentifier:iTermCapturedOutputToolTableViewCellIdentifier owner:self];
    if (result == nil) {
        result = [self newTextField];
    }

    CapturedOutput *capturedOutput = filteredEntries_[row];
    NSString *value = [self labelForCapturedOutput:capturedOutput];
    result.textField.stringValue = value;
    result.textField.toolTip = value;

    return result;
}

- (NSString *)labelForCapturedOutput:(CapturedOutput *)capturedOutput {
    NSString *label = capturedOutput.line;
    if (capturedOutput.state) {
        label = [@"✔ " stringByAppendingString:label];
    } else {
        label = [@"🔹 " stringByAppendingString:label];
    }
    return label;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)rowIndex {
    CapturedOutput *capturedOutput = filteredEntries_[rowIndex];
    NSString *label = [self labelForCapturedOutput:capturedOutput];
    if (!_measuringCellView) {
        _measuringCellView = [self newTextField];
    }
    // https://stackoverflow.com/a/42853810/321984
    [_measuringCellView.textField setStringValue:label];
    _measuringCellView.frame = NSMakeRect(0, 0, tableView_.frame.size.width, 0);
    _measuringCellView.needsLayout = YES;
    [_measuringCellView layoutSubtreeIfNeeded];
    NSSize naturalSize = [_measuringCellView fittingSize];
    return naturalSize.height > tableView_.rowHeight ? naturalSize.height : tableView_.rowHeight;
}

- (NSCell *)tableView:(NSTableView *)tableView
        dataCellForTableColumn:(NSTableColumn *)tableColumn
                           row:(NSInteger)row {
    return [self cell];
}

- (NSCell *)cell {
    NSCell *cell = [[NSTextFieldCell alloc] init];
    [cell setEditable:NO];
    [cell setLineBreakMode:NSLineBreakByWordWrapping];
    [cell setWraps:YES];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger selectedIndex = [tableView_ selectedRow];
    if (selectedIndex < 0) {
        return;
    }
    CapturedOutput *capturedOutput = filteredEntries_[selectedIndex];

    if (capturedOutput) {
        iTermToolWrapper *wrapper = self.toolWrapper;
        [wrapper.delegate.delegate toolbeltDidSelectMark:capturedOutput.mark];
    }
}

- (void)capturedOutputDidChange:(NSNotification *)notification {
    [self updateCapturedOutput];
}

- (void)fixCursor {
    if (shutdown_) {
        return;
    }
    iTermToolWrapper *wrapper = self.toolWrapper;
    [wrapper.delegate.delegate toolbeltUpdateMouseCursor];
}

- (void)doubleClickOnTableView:(id)sender {
    NSInteger selectedIndex = [tableView_ selectedRow];
    if (selectedIndex < 0) {
        return;
    }
    CapturedOutput *capturedOutput = filteredEntries_[selectedIndex];
    iTermToolWrapper *wrapper = self.toolWrapper;
    [wrapper.delegate.delegate toolbeltActivateTriggerForCapturedOutputInCurrentSession:capturedOutput];
}

- (CGFloat)minimumHeight {
    return 60;
}

- (void)toggleCheckmark:(id)sender {
    NSInteger index = [tableView_ clickedRow];
    if (index >= 0) {
        CapturedOutput *capturedOutput = filteredEntries_[index];
        capturedOutput.state = !capturedOutput.state;
    }
    [tableView_ reloadData];
}

#pragma mark - NSMenuDelegate

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    return [self respondsToSelector:[item action]] && [tableView_ clickedRow] >= 0;
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidChange:(NSNotification *)aNotification {
    [self updateCapturedOutput];
}

- (NSArray *)control:(NSControl *)control
            textView:(NSTextView *)textView
         completions:(NSArray *)words
 forPartialWordRange:(NSRange)charRange
 indexOfSelectedItem:(NSInteger *)index {
    return @[];
}

#pragma mark - Actions

- (void)help:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://iterm2.com/captured_output.html"]];
}

@end
