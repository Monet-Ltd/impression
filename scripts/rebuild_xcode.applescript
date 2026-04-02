set projectPath to POSIX file "/Users/minghsuan/Documents/Impression/.worktrees/multi-provider-codex/Impression.xcodeproj"

tell application "Xcode"
    activate
    open projectPath
end tell

tell application "System Events"
    repeat until exists process "Xcode"
        delay 1
    end repeat
end tell

delay 3

tell application "System Events"
    tell process "Xcode"
        keystroke "k" using {command down, shift down}
        delay 1
        keystroke "b" using {command down}
        delay 1
        keystroke "u" using {command down}
    end tell
end tell
