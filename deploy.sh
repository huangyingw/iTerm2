#!/bin/zsh
SCRIPT=$(realpath "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
cd "$SCRIPTPATH"

cp -fv ./movescreen.py ~/Library/ApplicationSupport/iTerm2/Scripts/movescreen/movescreen/movescreen.py
