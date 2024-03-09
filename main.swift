//
//  main.swift
//  SurgeRuleHelper
//
//  Created by Lukas Schmidt on 09.03.24.
//

import AppleScriptObjC
import Foundation

@discardableResult func safeShell(_ command: String) throws -> String {
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/bash") // <--updated
    task.standardInput = nil

    try task.run() // <--updated

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)!

    return output
}

func shell(_ command: String) -> String? {
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command.trimmingCharacters(in: .whitespacesAndNewlines)]
    task.launchPath = "/bin/bash"
    task.standardInput = nil
    task.launch()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)

    return output?.trimmingCharacters(in: .whitespacesAndNewlines)
}

enum Browesr: String, CaseIterable {
    case arc = "Arc"
    case chrome = "Google Chrome"
    case safari = "Safari"

    func getURL() -> String? {
        let script: String = {
            switch self {
            case .safari:
                return """
                try
                    tell application "Safari" to return URL of current tab of front window
                on error the error_message number the error_number
                    set the error_text to "Error: " & the error_number & ". " & the error_message
                    return error_message
                end try
                """
            case .arc, .chrome:
                return """
                try
                    tell application "\(rawValue)" to return URL of active tab of front window
                on error the error_message number the error_number
                    set the error_text to "Error: " & the error_number & ". " & the error_message
                    return error_message
                end try
                """
            }
        }()

        guard let ascp = NSAppleScript(source: script) else {
            return nil
        }
        var error: NSDictionary?
        let output = ascp.executeAndReturnError(&error)
        if let err = error {
            return err.description
        } else {
            return output.stringValue
        }
    }
}

/// https://www.alfredapp.com/help/workflows/inputs/script-filter/json/
struct AlfredOuput: Encodable {
    struct Icon: Encodable {
        var type = "file"
        let path: String
    }

    /// The mod element gives you control over how the modifier keys react. It can alter the looks of a result (e.g. subtitle, icon) and output a different arg or session variables.
    struct Mode: Encodable {
        let valid = true
        let arg: [String]
        let subtitle: String
    }

    enum UID: String, Encodable {
        case success = "success.surge.rule.helper"
        case failure = "failure.surge.rule.helper"
    }
    /// A unique identifier for the item. It allows Alfred to learn about the item for subsequent sorting and ordering of the user's actioned results.
    let uid: UID
    /// The title displayed in the result row. There are no options for this element and it is essential that this element is populated.
    let title: String
    /// The subtitle displayed in the result row.
    var subtitle: String?
    /// The icon displayed in the result row. path is relative to the workflow's root folder:
    let icon: Icon?
    let valid: Bool = true
    var mods: [String: Mode] = [:]
    /// Defines the text the user will get when copying the selected result row with ⌘C or displaying large type with ⌘L.
    let text: [String: String]?
    /// The argument which is passed through the workflow to the connected output action.
    let arg: [String]

    init(url: String?, browser: Browesr?) {
        let actualURL = url.flatMap(URL.init(string:))
        let host = actualURL?.host
        uid = host == nil ? .failure : .success
        title = host.flatMap({ "Add Rule for: \($0)" }) ?? "Not Found"
        subtitle = host.flatMap({ _ in "Standard Rule" })
        icon = browser.flatMap { .init(type: "fileicon", path: "/Applications/\($0.rawValue).app") } ?? .init(type: "fileicon", path: "")
        text = host.flatMap({
            ["copy": $0]
        })
        arg = [host].compactMap({ $0 })
        if host != nil {
            mods = [
                "cmd": Mode(arg: arg, subtitle: "Copy and Open Logical Rule"),
                "alt": Mode(arg: arg, subtitle: "Copy and Ruleset"),
            ]
        }
    }
}

func process() -> [AlfredOuput] {
    let browsers = shell("lsappinfo metainfo | grep -E -o 'Safari|Google Chrome|Arc'")?.split(separator: "\n").compactMap { Browesr(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? []
    
    let result = browsers.map({
        let url = $0.getURL()
        return AlfredOuput(url: url, browser: $0)
    }).filter({ (o: AlfredOuput) in
        return o.uid == .success
    })
    if result.isEmpty {
        /// Display first error or fallback error
        return [result.first ?? AlfredOuput(url: nil, browser: nil)]
    } else {
        return result
    }
}

let output = process()
if let string = (try? JSONEncoder().encode(["items": output])).flatMap({ String(data: $0, encoding: .utf8) }) {
    print(string)
}
