import Foundation
import UtterLeafCore

@MainActor final class MeetingLive {
    private let api = Providers()
    private var continuation: AsyncStream<Data>.Continuation?
    private var task: Task<Void, Never>?
    private var buffer = Data()
    var onFailure: (() -> Void)?
    func start(job: UUID, price: PriceSnapshot, onCall: @escaping (UsageCall) -> Void, onSegments: @escaping ([MeetingUtterance]) -> Void) async throws {
        api.streamResourceTimeout = 3 * 3600 + 120
        api.onCall = onCall; api.onSpeakerResult = onSegments
        try await api.startStream(pipeline: .realtime, job: job, price: price, speakerInfo: true)
        var continuation: AsyncStream<Data>.Continuation!
        let stream = AsyncStream<Data>(bufferingPolicy: .bufferingOldest(150)) { continuation = $0 }
        self.continuation = continuation
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for await data in stream {
                    try Task.checkCancellation(); try await api.send(data)
                    try await Task.sleep(for: .milliseconds(200))
                }
                try await api.send(buffer, final: true); buffer.removeAll()
                _ = try await api.endStream()
            } catch { api.cancel(); if !Task.isCancelled { onFailure?() } }
        }
    }
    func append(_ data: Data) {
        guard continuation != nil else { return }
        buffer.append(data)
        while buffer.count >= 6400 {
            if case .dropped = continuation?.yield(Data(buffer.prefix(6400))) { cancel(); onFailure?(); return }
            buffer.removeFirst(6400)
        }
    }
    func finish() { continuation?.finish(); continuation = nil }
    func cancel() { continuation?.finish(); continuation = nil; task?.cancel(); api.cancel(); buffer.removeAll() }
}
