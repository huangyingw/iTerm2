#!/bin/bash -
SCRIPT=$(realpath "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
cd "$SCRIPTPATH"

xcodebuild -list -project iTerm2.xcodeproj
xcodebuild -target iTerm2Shared
xcodebuild -target SSKeychain
xcodebuild
open /Users/huangyingw/Dropbox/myproject/git/mac/gnachman/iTerm2/build/Development/iTerm2.app
