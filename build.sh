#!/bin/bash -
SCRIPT=$(realpath "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
cd "$SCRIPTPATH"

xcodebuild -list -project iTerm2.xcodeproj
xcodebuild
