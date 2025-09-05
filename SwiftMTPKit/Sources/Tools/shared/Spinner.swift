import Foundation

final class Spinner {
    private let frames = ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"]
    private var idx = 0
    private var timer: DispatchSourceTimer?
    private let message: String
    private let isTTY: Bool
    private let jsonMode: Bool

    init(_ message: String, jsonMode: Bool) {
        self.message = message
        self.jsonMode = jsonMode
        #if canImport(Darwin)
        self.isTTY = isatty(STDERR_FILENO) == 1
        #else
        self.isTTY = true
        #endif
    }

    func start() {
        guard isTTY, !jsonMode else { return }
        fputs("  \(frames[idx]) \(message)\r", stderr)
        let t = DispatchSource.makeTimerSource(queue: .global())
        t.schedule(deadline: .now(), repeating: .milliseconds(80))
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.idx = (self.idx + 1) % self.frames.count
            fputs("  \(self.frames[self.idx]) \(self.message)\r", stderr)
            fflush(stderr)
        }
        t.resume()
        timer = t
    }

    func succeed(_ final: String) {
        stop()
        if isTTY, !jsonMode { fputs("  ✓ \(final)\n", stderr) }
    }

    func fail(_ final: String) {
        stop()
        if isTTY, !jsonMode { fputs("  ✗ \(final)\n", stderr) }
    }

    private func stop() {
        timer?.cancel()
        timer = nil
        if isTTY, !jsonMode { fputs("\r", stderr) }
    }
}
