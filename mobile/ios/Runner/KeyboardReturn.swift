import ObjectiveC.runtime
import UIKit

// Personal-install compatibility only. All selectors are optional and never used to launch an arbitrary bundle.
// Re-evaluate this adapter before public distribution or a major iOS update.
@MainActor enum KeyboardReturn {
    static func attempt(host: String?) async -> Bool {
        let application = UIApplication.shared
        // A deep link can arrive during activation. Inactive does not mean that we returned.
        for _ in 0..<16 where application.applicationState == .inactive {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard !Task.isCancelled else { return false }
        guard application.applicationState == .active else {
            let background = application.applicationState == .background
            try? DictationExchange.write(["hostResolved": host != nil, "route": background ? "already-background" : "activation-timeout", "accepted": false, "leftApp": background], to: "app-navigation")
            return background
        }
        var accepted = false
        var route = "unresolved"
        if let host, host.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil {
            accepted = ULHostReturn.resumeCapturedHost(host)
            route = accepted ? "captured-host" : "captured-host-rejected"
        }
        if !accepted, let ivar = class_getInstanceVariable(UIApplication.self, "_systemNavigationAction"),
           let action = object_getIvar(application, ivar) as? NSObject {
            let list = NSSelectorFromString("destinations"), back = NSSelectorFromString("sendResponseForDestination:")
            if action.responds(to: list), action.responds(to: back),
               let destinations = action.perform(list)?.takeUnretainedValue() as? [NSNumber], destinations.count == 1,
               let destination = destinations.first, let implementation = action.method(for: back) {
                typealias SendBack = @convention(c) (AnyObject, Selector, UInt) -> Bool
                accepted = unsafeBitCast(implementation, to: SendBack.self)(action, back, destination.uintValue)
                if accepted { route = "system-back" }
            }
        }
        // Some apps expose an ordinary resume scheme. Exclude schemes known to create a new page/conversation.
        let schemes = ["com.tencent.xin": "weixin://"]
        if !accepted, let host, let value = schemes[host], let url = URL(string: value) {
            accepted = await application.open(url); route = accepted ? "resume-scheme" : "resume-scheme-rejected"
        }
        if accepted {
            for _ in 0..<20 where application.applicationState != .background && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        let leftApp = application.applicationState == .background
        try? DictationExchange.write(["hostResolved": host != nil, "route": route, "accepted": accepted, "leftApp": leftApp,
            "os": UIDevice.current.systemVersion, "updated": Date().timeIntervalSince1970], to: "app-navigation")
        return accepted && leftApp
    }
}
