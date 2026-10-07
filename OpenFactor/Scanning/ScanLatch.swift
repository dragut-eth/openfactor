/// One report per look at a code, and a fresh look whenever the screen asks for one.
///
/// A capture session reports the same QR many times a second while it stays in frame, so the
/// camera keeps a latch: the first payload is reported and the rest are ignored. **The latch has
/// to be re-armed when the person looks again**, and that is the part that was missing. It was
/// re-armed only when the camera view appeared, and the two ways back to the camera on the add
/// screen, "Try again" after a code that could not be used and Cancel on a transfer preview, never
/// take the camera off screen, so the viewfinder came back live and deaf. Audit X5, B1.
///
/// **A generation number, not a reset on every update.** SwiftUI calls the camera's update method
/// whenever the screen redraws, and the account list behind this sheet redraws every second for
/// its codes, so re-arming on every update would report a code held in frame once a second. The
/// view model counts the times it returns to scanning; the latch re-arms only when that count
/// changes.
struct ScanLatch {

    private(set) var hasReported = false
    private var generation: Int?

    /// Whether this payload should be reported. True once per generation, then false until the
    /// next one.
    mutating func accept() -> Bool {
        guard !hasReported else { return false }
        hasReported = true
        return true
    }

    /// Re-arms if, and only if, the screen has returned to scanning since the last call.
    mutating func rearm(for generation: Int) {
        guard generation != self.generation else { return }
        self.generation = generation
        hasReported = false
    }

    /// Re-arms unconditionally, for the camera appearing afresh.
    mutating func rearm() {
        hasReported = false
    }
}
