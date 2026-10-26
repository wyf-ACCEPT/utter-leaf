import ObjectiveC.runtime
import UIKit

// Personal-install compatibility only. All selectors are optional and never used to launch an arbitrary bundle.
// Re-evaluate this adapter before public distribution or a major iOS update.
@MainActor enum KeyboardReturn {
    static func attempt(host: String?) async -> Bool {
        guard UIApplication.shared.applicationState == .active else { return true }
        let application = UIApplication.shared
        if let ivar = class_getInstanceVariable(UIApplication.self, "_systemNavigationAction"),
           let action = object_getIvar(application, ivar) as? NSObject {
            let list = NSSelectorFromString("destinations"), back = NSSelectorFromString("sendResponseForDestination:")
            if action.responds(to: list), action.responds(to: back),
               let destinations = action.perform(list)?.takeUnretainedValue() as? [NSNumber], destinations.count == 1,
               let destination = destinations.first, let implementation = action.method(for: back) {
                typealias SendBack = @convention(c) (AnyObject, Selector, UInt) -> Bool
                if unsafeBitCast(implementation, to: SendBack.self)(action, back, destination.uintValue) { return true }
            }
        }
        // Some apps expose an ordinary resume scheme. Exclude schemes known to create a new page/conversation.
        let schemes = ["com.tencent.xin": "weixin://"]
        guard let host, let value = schemes[host], let url = URL(string: value) else { return false }
        return await application.open(url)
    }
}
