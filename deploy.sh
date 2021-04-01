#!/bin/zsh
SCRIPT=$(realpath "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
cd "$SCRIPTPATH"

~/loadrc/bashrc/ln_fs.sh ~/loadrc/iterm2rc/movescreen.py ~/Library/ApplicationSupport/iTerm2/Scripts/movescreen/movescreen/movescreen.py
