#!/usr/bin/env swift

import AppKit

// Helpers
struct ScriptFilterItem: Codable {
  let variables: [String: String]
  let title: String
  let subtitle: String
  let arg: [Int32]
  let icon: [String: String]
  let match: String
}

// Grab windows
let windowList: CFArray? = CGWindowListCopyWindowInfo(
  [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)

guard let windows = windowList as? [[String: Any]] else { fatalError("Unable to get window list") }

// Populate items
let allItems: [ScriptFilterItem] = windows.compactMap { dict in
  guard
    dict["kCGWindowLayer"] as? Int == 0,
    let appRawName = dict["kCGWindowOwnerName"] as? String,
    let appPID = dict["kCGWindowOwnerPID"] as? Int32,
    let windowID = dict["kCGWindowNumber"] as? Int32,
    let appPath = NSRunningApplication(processIdentifier: appPID)?.bundleURL?.path,
    let windowTitle = dict["kCGWindowName"] as? String,
    // When using Stage Manager, there are a lot of extra windows from Window Manager
    appRawName != "WindowManager",
    // Unnamed windows with a low height are generally safe to ignore
    // Examples include Safari's 20px status bar and a 68px invisible window present on full screen apps
    let windowBounds = dict["kCGWindowBounds"] as? [String: Int32],
    let windowHeight = windowBounds["Height"],
    !windowTitle.isEmpty || windowHeight > 70
  else { return nil }

  // Some apps (e.g. Reeder) have the ".app" extension in "kCGWindowOwnerName"
  let appName = URL(fileURLWithPath: appRawName).deletingPathExtension().lastPathComponent

  // Some apps (e.g. Reeder) have legitimate windows without a name
  let windowName = windowTitle.isEmpty ? appName : windowTitle

  return ScriptFilterItem(
    variables: ["app_name": appName],
    title: windowName,
    subtitle: appName,
    arg: [appPID, windowID],
    icon: ["type": "fileicon", "path": appPath],
    match: "\(windowName) \(appName)"
  )
}

// The on-screen window list is ordered front-to-back, so the first item is the
// window the user is currently in. Drop it — there's no point listing the window
// you're already looking at in a "switch to another window" list.
let sfItems = Array(allItems.dropFirst())

// Fallback if no valid items
guard !sfItems.isEmpty else {
  let subtitle = CGPreflightScreenCaptureAccess() ?
    "Make sure there are unminimised windows in the current Desktop Space" :
    "Press ↩ to request Screen Recording permissions, necessary to get window information"

  let notFound = [
    "title": "No Windows Found",
    "subtitle": subtitle,
    "arg": "request_permissions"
  ]

  let jsonData: Data = try JSONSerialization.data(withJSONObject: ["items": [notFound]])
  let jsonString: String = String(data: jsonData, encoding: .utf8)!

  print(jsonString)
  exit(0)
}

// Output JSON
let jsonData = try JSONEncoder().encode(["items": sfItems])
print(String(data: jsonData, encoding: .utf8)!)
