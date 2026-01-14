#!/usr/bin/env bash
# run-timer.sh
# Shortcut script to bring the Timer app to the front and open its menu bar item.
# No quitting/relaunching — just start if needed and click the status bar item.
#
# Usage examples:
#   ./run-timer.sh            # activate and open the status bar popover
#   ./run-timer.sh --start    # forward any args to the app if it reads them
#
# Set BUNDLE_ID to your app's bundle identifier.

set -euo pipefail

BUNDLE_ID="com.yourcompany.Timer"

# Start the app if needed (does not steal focus), pass through any args
# -g: do not bring to foreground, -j: hide Dock icon bounce
open -gj -b "$BUNDLE_ID" --args "$@" >/dev/null 2>&1 || true

# AppleScript to activate the app and click its first status bar item.
# Note: UI scripting requires granting Accessibility permissions to the calling process (e.g., Terminal, Automator, Keyboard Maestro, etc.).
/usr/bin/osascript <<'APPLESCRIPT'
try
  -- Activate the app by bundle identifier
  tell application id "com.yourcompany.Timer" to activate
  delay 0.2
  tell application "System Events"
    -- Try to get the process by application bundle id's running name
    set targetProcess to missing value
    repeat with p in processes
      try
        if bundle identifier of p is "com.yourcompany.Timer" then
          set targetProcess to p
          exit repeat
        end if
      end try
    end repeat

    if targetProcess is missing value then
      -- Fallback: use the frontmost process
      set targetProcess to first process whose frontmost is true
    end if

    if exists targetProcess then
      tell targetProcess
        if exists menu bar 1 then
          tell menu bar 1
            if exists status bar item 1 then
              click status bar item 1
            end if
          end tell
        end if
      end tell
    end if
  end tell
on error errMsg number errNum
  -- Swallow errors (e.g., if Accessibility is not enabled)
end try
APPLESCRIPT

