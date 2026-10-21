import AlfredWorkflowScriptFilter


struct Window {
    
    let number: CGWindowID
    let title: String
    let appPID: pid_t
    let appName: String
    let appIcon: String

}


struct RegexFilter {

    let pattern: String
    let regex: NSRegularExpression
    let keepsMatchingWindows: Bool

    // a Window matches if the regex finds a match in either its App Name or its Title
    func allows(_ window: Window) -> Bool {
        let matches = [window.appName, window.title].contains { string in
            let precomposedString = string.precomposedStringWithCanonicalMapping

            return regex.firstMatch(in: precomposedString, range: NSRange(precomposedString.startIndex..., in: precomposedString)) != nil
        }

        return matches == keepsMatchingWindows
    }

}


class Entrance {

    static let shared = Entrance()

    private init() {}


    static func scriptFilter() -> String {
        switch argument {
        case "excluded":
            return resultsForExcludedWindows()
        case "filtered":
            return resultsForRegexFilteredWindows()
        default:
            return resultsForOnscreenWindowsExcludingExcludedWindowsLOL()
        }
    }
        
}


extension Entrance {
    
    private static var argument: String? {
        guard CommandLine.arguments.count >= 2 else { return nil }
        
        return CommandLine.arguments[1]
    }

    private static func resultsForExcludedWindows() -> String {
        guard let excludedWindows = excludedWindows()?.windows else {
            ScriptFilter.add(
                Item(title: "🚨️ Oops 🚨️ Something is failing badly. The smart thing to do is to report!")
                    .subtitle("Press ↵ to fly to the GitHub Issues page")
                    .arg("do")
                    .variable(Variable(name: "action", value: "headToGitHubIssues"))
            )
            
            return ScriptFilter.output()
        }
        
        if excludedWindows.isEmpty {
            ScriptFilter.add(
                Item(title: "You haven't excluded any Window yet!")
                    .valid(false)
            )
        } else {
            for window in excludedWindows {
                ScriptFilter.add(
                    Item(title: window.title)
                        .subtitle(window.appName)
                        .match("\(window.appName) \(window.title)")
                        .icon(Icon(path: window.appIcon, type: .fileicon))
                        .arg("do")
                        .variable(Variable(name: "windowTitle", value: window.title))
                        .variable(Variable(name: "appName", value: window.appName))
                        .variable(Variable(name: "action", value: "includeBackWindow"))
                        .mod(
                            Cmd()
                                .subtitle("Unban this Window")
                                .arg("do")
                                .variable(Variable(name: "windowTitle", value: window.title))
                                .variable(Variable(name: "appName", value: window.appName))
                                .variable(Variable(name: "action", value: "includeBackWindow"))
                        )
                )
            }
            
        }
        
        return ScriptFilter.output()
    }
    
    // `filtered <regex> [keep|hide]`, each Script Filter carrying its own regex.
    // falls back to the `filter_regex` and `filter_mode` variables, which is how List Filters drive the shared
    // Script Filter, and how a filtered list gets reopened after a Window got banned from it.
    // without a mode, a regex starting with `!` hides the Windows that match, which List Filter items can use.
    private static func resultsForRegexFilteredWindows() -> String {
        let arguments = CommandLine.arguments
        var pattern = (arguments.count >= 3 ? arguments[2] : ProcessInfo.processInfo.environment["filter_regex"] ?? "").precomposedStringWithCanonicalMapping
        var mode = arguments.count >= 4 ? arguments[3] : ProcessInfo.processInfo.environment["filter_mode"] ?? ""
        
        if mode.isEmpty, pattern.hasPrefix("!") {
            pattern.removeFirst()
            mode = "hide"
        }

        guard pattern.isEmpty == false else {
            return resultsForOnscreenWindowsExcludingExcludedWindowsLOL()
        }

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            ScriptFilter.add(
                Item(title: "🚨️ The regex of this filter is invalid 🚨️")
                    .subtitle(pattern)
                    .valid(false)
            )

            return ScriptFilter.output()
        }

        return resultsForOnscreenWindowsExcludingExcludedWindowsLOL(
            filteredBy: RegexFilter(pattern: pattern, regex: regex, keepsMatchingWindows: mode != "hide")
        )
    }

    private static func resultsForOnscreenWindowsExcludingExcludedWindowsLOL(filteredBy regexFilter: RegexFilter? = nil) -> String {
        guard let windowsToShowInAlfredResults = onscreenWindowsExcludingExcludedWindowsLOL() else {
            ScriptFilter.add(
                Item(title: "🚨️ Oops 🚨️ Something is failing badly. The smart thing to do is to report!")
                    .subtitle("Press ↵ to fly to the GitHub Issues page")
                    .arg("do")
                    .variable(Variable(name: "action", value: "headToGitHubIssues"))
            )
            
            return ScriptFilter.output()
        }
            
        if windowsToShowInAlfredResults.isEmpty {
            if CGPreflightScreenCaptureAccess() == true {
                ScriptFilter.add(
                    Item(title: "Desktop is all clean! No Window found.")
                        .valid(false)
                )
            } else {
                ScriptFilter.add(
                    Item(title: "🔐️🔐️🔐️ Screen Recording and/or Accessibility permissions needed 🔐️🔐️🔐️")
                        .subtitle("Press ↵ to grant permissions, ⌘↵ for the README")
                        .arg("do")
                        .variable(Variable(name: "action", value: "promptPermissionDialogs"))
                        .mod(
                            Cmd()
                                .subtitle("README here I come!")
                                .arg("do")
                                .variable(Variable(name: "action", value: "headToREADME"))
                        )
                )
            }
        } else {
            let filterOutFocusedWindow = (ProcessInfo.processInfo.environment["filter_out_focused_window"] == "1" ? true : false)
            let windowsWithoutFocusedWindow = filterOutFocusedWindow ? removeCurrentlyFocusedWindow(from: windowsToShowInAlfredResults) : windowsToShowInAlfredResults
            // the regex filter has to come after removing the Focused Window as that one is detected by being the first of the whole list
            let windowsToShowInAlfredResults = regexFilter.map { regexFilter in windowsWithoutFocusedWindow.filter(regexFilter.allows) } ?? windowsWithoutFocusedWindow

            if windowsWithoutFocusedWindow.isEmpty {
                ScriptFilter.add(
                    Item(title: "The only visible Window is the one you're already on!")
                        .subtitle("Press ↵ to go back to it")
                        .arg("do")
                        .variable(Variable(name: "action", value: "nothing"))
                )
            } else if windowsToShowInAlfredResults.isEmpty {
                ScriptFilter.add(
                    Item(title: "No Window left after applying your regex filter!")
                        .subtitle(regexFilter.map { regexFilter in "\(regexFilter.keepsMatchingWindows ? "keeping" : "hiding") \(regexFilter.pattern)" } ?? "")
                        .valid(false)
                )
            } else {
                // Alfred can't pick a Result on its own, so a single Window gets brought to the foreground right away.
                // Alfred loses focus and goes away in the process. the Result is still listed in case it doesn't.
                let autoSelectSingleWindow = (ProcessInfo.processInfo.environment["auto_select_single_window"] == "1" ? true : false)
                if autoSelectSingleWindow, windowsToShowInAlfredResults.count == 1, let window = windowsToShowInAlfredResults.first {
                    _ = Workflow.bringWindowToForeground(windowNumber: Int(window.number), appPID: Int(window.appPID))
                }
                
                for window in windowsToShowInAlfredResults {
                    let banMod = Cmd()
                        .subtitle("Ban this Window from Alfred's Results")
                        .arg("do")
                        .variable(Variable(name: "windowTitle", value: window.title))
                        .variable(Variable(name: "appName", value: window.appName))
                        .variable(Variable(name: "appIcon", value: window.appIcon))
                        .variable(Variable(name: "action", value: "excludeWindowFromAlfredResults"))
                    
                    if let regexFilter {
                        banMod
                            .variable(Variable(name: "reopen", value: "filtered"))
                            .variable(Variable(name: "filter_regex", value: regexFilter.pattern))
                            .variable(Variable(name: "filter_mode", value: regexFilter.keepsMatchingWindows ? "keep" : "hide"))
                    }
                    
                    ScriptFilter.add(
                        Item(title: window.title)
                            .subtitle(window.appName)
                            .match("\(window.appName) \(window.title)")
                            .icon(Icon(path: window.appIcon, type: .fileicon))
                            .arg("do")
                            .variable(Variable(name: "windowNumber", value: String(window.number)))
                            .variable(Variable(name: "windowTitle", value: window.title))
                            .variable(Variable(name: "appPID", value: String(window.appPID)))
                            .variable(Variable(name: "action", value: "bringWindowToForeground"))
                            .mod(banMod)
                    )
                }
            }
        }
                
        return ScriptFilter.output()
    }
    
    private static func onscreenWindowsExcludingExcludedWindowsLOL() -> [Window]? {
        guard let tooManyWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as NSArray? else { return nil }
        
        // keep Windows that are:
        // 1. not Menu Bar Icons (back to using kCGWindowLayer 25 as Apple finally fixed its kCGStatusWindowLevel vs kCGModalPanelWindowLevel fuckery)
        // 2. not Transparent Windows
        // 3. not a bunch of Window Server Windows (Cursor, StatusIndicator, Menubar, etc.)
        // 4. not Notification Center Windows that show up when receiving Notifications
        // 5. not a Screenshot Window that doesn't go away after you used Screenshot
        // 6. not a bunch of Stage Manager Windows
        // 7. not Alfred itself (Alfred Preferences is something else altogether and is embraced)
        var windowsFilter = """
kCGWindowLayer != 25
&& kCGWindowAlpha > 0
&& kCGWindowOwnerName != "Window Server"
&& kCGWindowOwnerName != "Notification Center"
&& kCGWindowOwnerName != "Screenshot"
&& kCGWindowOwnerName != "WindowManager"
&& kCGWindowOwnerName != "Alfred"
"""
        excludedWindows()?.windows.forEach { excludedWindow in
            // necessary because of Korean: https://developer.apple.com/documentation/foundation/nscharacterset/decomposables#Discussion LOL
            let precomposedAppName = String(data: excludedWindow.appName.precomposedStringWithCanonicalMapping.data(using: .utf8) ?? Data(), encoding: .utf8) ?? ""
            let precomposedWindowTitle = String(data: excludedWindow.title.precomposedStringWithCanonicalMapping.data(using: .utf8) ?? Data(), encoding: .utf8) ?? ""
            
            windowsFilter.append("""
&& !(kCGWindowOwnerName = "\(precomposedAppName)" && kCGWindowName = "\(precomposedWindowTitle)")
"""
            )
        }
               
        let windows: [Window] = tooManyWindows.filtered(using: NSPredicate(format: windowsFilter)).compactMap { window in
            guard
                let window = window as? NSDictionary,
                let windowNumber = window.value(forKey: "kCGWindowNumber") as? CGWindowID,
                let windowOwnerPID = window.value(forKey: "kCGWindowOwnerPID") as? pid_t,
                let windowOwnerName = window.value(forKey: "kCGWindowOwnerName") as? String,
                let windowName = window.value(forKey: "kCGWindowName") as? String
            else {
                return nil
            }
            
            return Window(
                number: windowNumber,
                title: windowName,
                appPID: windowOwnerPID,
                appName: windowOwnerName,
                appIcon: NSRunningApplication(processIdentifier: windowOwnerPID)?.bundleURL?.path ?? Bundle.main.bundlePath
            )
        }
        
        return windows
    }
    
    private static func excludedWindows() -> ExcludedWindows? {
        guard
            let excludedWindowsPlistFile = Workflow.excludedWindowsPlistFile,
            FileManager.default.fileExists(atPath: excludedWindowsPlistFile)
        else {
            return nil
        }
        
        let excludedWindowsPlistFileURL = URL(fileURLWithPath: excludedWindowsPlistFile)
        guard let data = try? Data(contentsOf: excludedWindowsPlistFileURL) else { return nil }
            
        let decoder = PropertyListDecoder()
        guard let excludedWindows = try? decoder.decode(ExcludedWindows.self, from: data) else { return nil }
        
        return excludedWindows
    }
        
    private static func removeCurrentlyFocusedWindow(from onscreenWindows: [Window]) -> [Window] {
        guard
            let frontmostWindow = onscreenWindows.first,
            frontmostWindow.appPID == NSWorkspace.shared.frontmostApplication?.processIdentifier
        else {
            return onscreenWindows
        }
        
        return Array(onscreenWindows.dropFirst())
    }

    private static func axFocusedWindowNumber() -> CGWindowID? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let axApplication = AXUIElementCreateApplication(pid)

        var axWindow: AnyObject?
        guard AXUIElementCopyAttributeValue(axApplication, kAXFocusedWindowAttribute as CFString, &axWindow) == .success else { return nil }

        var axWindowNumber: CGWindowID = 0
        guard _AXUIElementGetWindow((axWindow as! AXUIElement), &axWindowNumber) == .success else { return nil }

        return axWindowNumber
    }

}
