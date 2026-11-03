import AppKit

@MainActor
enum ChromeTasksTab {
    static let browserID = "com.google.Chrome"
    static let url = URL(string: "https://calendar.google.com/calendar/u/0/r/tasks")!

    static func activateIfOpen() -> Bool {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: browserID).isEmpty else {
            return false
        }
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        return error == nil && result?.booleanValue == true
    }

    private static let script = NSAppleScript(source: """
        with timeout of 4 seconds
            tell application id "com.google.Chrome"
                repeat with chromeWindow in windows
                    set tabURLs to URL of every tab of chromeWindow
                    repeat with tabIndex from 1 to count of tabURLs
                        if my isTasksURL(item tabIndex of tabURLs) then
                            set matchingWindow to window id (id of chromeWindow)
                            set active tab index of matchingWindow to tabIndex
                            if minimized of matchingWindow then set minimized of matchingWindow to false
                            set index of matchingWindow to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end tell
        end timeout
        return false

        on isTasksURL(tabURL)
            if tabURL is missing value then return false
            if tabURL is "https://tasks.google.com" or tabURL starts with "https://tasks.google.com/" then return true
            if tabURL does not start with "https://calendar.google.com/calendar/" then return false
            set savedDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to {"?", "#"}
            set pagePath to first text item of tabURL
            set AppleScript's text item delimiters to savedDelimiters
            return pagePath ends with "/r/tasks" or pagePath contains "/r/tasks/" or pagePath is "https://calendar.google.com/calendar/tasks"
        end isTasksURL
        """)
}
