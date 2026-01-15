# T-Timer

## Overview
T-Timer is a macOS menubar timer. It shows the countdown in the menubar, speaks a phrase on completion, and blinks the time text until dismissed.

## Hotkey
- Toggle panel: Command + Option + T

## Build
Debug build:
- `xcodebuild -project "TimerApp.xcodeproj" -scheme "T-Timer" -configuration Debug build`

Release build:
- `xcodebuild -project "TimerApp.xcodeproj" -scheme "T-Timer" -configuration Release build`

## Run
Debug app path:
- `/Users/AnthonyWest/Library/Developer/Xcode/DerivedData/TimerApp-ewufikqmlpmfbbfaawttwstwmvkc/Build/Products/Debug/T-Timer.app`

Release app path:
- `/Users/AnthonyWest/Library/Developer/Xcode/DerivedData/TimerApp-ewufikqmlpmfbbfaawttwstwmvkc/Build/Products/Release/T-Timer.app`

## Install
Copy the Release build to Applications:
- `ditto "/Users/AnthonyWest/Library/Developer/Xcode/DerivedData/TimerApp-ewufikqmlpmfbbfaawttwstwmvkc/Build/Products/Release/T-Timer.app" ~/Applications/T-Timer.app`
