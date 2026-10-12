--
--  configure-window.applescript
--  Loom
--
--  Copyright © 2026 Deepak Sharma (ChaiWithCode).
--  Licensed under the MIT License. See LICENSE for details.
--

on run argv
    if (count of argv) < 1 then
        error "Usage: configure-window.applescript <volume-name> [mount-point-path]"
    end if

    set volName to item 1 of argv
    set mountPath to "/Volumes/" & volName
    if (count of argv) >= 2 then
        set mountPath to item 2 of argv
    end if

    with timeout of 30 seconds
        tell application "Finder"
            activate

            -- Directly target the mounted volume disk object
            -- Directly addresses disk target; prior Finder automation failures were of unknown cause rather than alias resolution
            tell disk volName
                open
                set targetWindow to container window

                -- Enforce icon view
                set current view of targetWindow to icon view

                -- Hide Finder chrome (writable supported properties without suppressed failures)
                set toolbar visible of targetWindow to false
                set statusbar visible of targetWindow to false
                set pathbar visible of targetWindow to false

                -- Approved content area: 640 x 420 pt (outer bounds: {200, 120, 840, 572} with 32 pt titlebar)
                set bounds of targetWindow to {200, 120, 840, 572}

                -- Flush chrome and bounds to prevent async layout drift
                update without registering applications
                delay 1

                -- Enforce approved DMG icon view options
                tell icon view options of targetWindow
                    set arrangement to not arranged
                    set icon size to 96
                    set text size to 12
                    set label position to bottom

                    -- Set custom background image strictly via actual file alias
                    set bgFile to ((POSIX file (mountPath & "/.background/background.tiff")) as alias)
                    set background picture to bgFile
                end tell

                -- Approved icon center coordinates:
                -- Loom.app: {180, 235}
                -- Applications: {460, 235}
                set position of item "Loom.app" of targetWindow to {180, 235}
                set position of item "Applications" of targetWindow to {460, 235}

                -- Commit modifications to .DS_Store
                update without registering applications
                delay 1

                -- Flush .DS_Store to disk and reopen so window state remains open on mount
                close
                delay 1
                open
                set targetWindow to container window
                delay 1

                -- Assertions for chrome, icon size, arrangement, bounds, and icon positions
                -- Note: 'background picture' getter is omitted because Finder throws -10000;
                -- background picture persistence is verified via independent .DS_Store bplist validation.
                if toolbar visible of targetWindow is not false then
                    error "Assertion failed: toolbar is visible"
                end if
                if statusbar visible of targetWindow is not false then
                    error "Assertion failed: statusbar is visible"
                end if
                if pathbar visible of targetWindow is not false then
                    error "Assertion failed: pathbar is visible"
                end if
                if icon size of icon view options of targetWindow is not 96 then
                    error "Assertion failed: icon size is " & (icon size of icon view options of targetWindow as text) & ", expected 96"
                end if
                if arrangement of icon view options of targetWindow is not not arranged then
                    error "Assertion failed: arrangement is not 'not arranged'"
                end if

                set winBounds to bounds of targetWindow
                set winWidth to (item 3 of winBounds) - (item 1 of winBounds)
                set winHeight to (item 4 of winBounds) - (item 2 of winBounds)
                if winWidth is not 640 or winHeight is not 452 then
                    error "Assertion failed: window dimensions are " & (winWidth as text) & "x" & (winHeight as text) & ", expected 640x452 (bounds: " & (winBounds as text) & ")"
                end if

                if position of item "Loom.app" of targetWindow is not {180, 235} then
                    error "Assertion failed: Loom.app position is " & (position of item "Loom.app" of targetWindow as text) & ", expected {180, 235}"
                end if
                if position of item "Applications" of targetWindow is not {460, 235} then
                    error "Assertion failed: Applications position is " & (position of item "Applications" of targetWindow as text) & ", expected {460, 235}"
                end if

                -- Final update keeping window open for auto-opening on mount
                update without registering applications
                delay 1
            end tell
        end tell
    end timeout
end run
