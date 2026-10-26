import Foundation

final class MeetingUploadProgress: NSObject, URLSessionTaskDelegate {
    private let report: @Sendable (Int) -> Void
    private let lock = NSLock()
    private var last = -1
    init(report: @escaping @Sendable (Int) -> Void) { self.report = report }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        let percent = min(100, Int(Double(totalBytesSent) / Double(totalBytesExpectedToSend) * 100))
        lock.lock(); let changed = percent > last; if changed { last = percent }; lock.unlock()
        if changed { report(percent) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
