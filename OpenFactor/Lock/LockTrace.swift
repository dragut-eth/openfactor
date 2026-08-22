#if DEBUG

    import Foundation
    import Observation

    /// A rolling record of every event that can move the lock's state, and of what the
    /// windows did about it.
    ///
    /// **Why this exists, and why it is not a `print`.** The interesting moments happen while
    /// the app is leaving the foreground, so the person watching is looking at the app
    /// switcher rather than a console. This keeps the last few hundred events in memory and
    /// shows them on a screen inside the app, which can be read after coming back and copied
    /// out whole.
    ///
    /// **It records the decision inputs, not conclusions.** `phase` and `settling` are the two
    /// pieces of state that decide whether the switcher gets a blank surface or a photograph of
    /// the account list, and neither is visible from outside `AppLockPresentation`. Every line
    /// carries both, plus what the cover window actually was at that instant, so a sequence can
    /// be read back rather than reasoned about. Three attempts at reasoning about this from the
    /// source produced three different wrong answers.
    ///
    /// **DEBUG only, and structurally so.** The whole file is inside the conditional, so a
    /// release build contains no buffer, no timestamps, and no call sites. Verified by searching
    /// the built Release binary for this file's strings and finding none, rather than by trusting
    /// the conditional.
    ///
    /// **This said "delete it when the bug is fixed" and that was wrong, so it stays.** The bug it
    /// was written for took three rounds of reasoning from the source, each producing a different
    /// wrong answer, and one trace to settle. Every future change to the lock touches the same
    /// event ordering, and rebuilding this from scratch next time would cost more than the
    /// nothing it costs to keep.
    @Observable
    @MainActor
    final class LockTrace {

        static let shared = LockTrace()

        /// Newest last. Bounded, because this runs for as long as the process does and an
        /// unbounded log of a per-second timer would be its own bug.
        private(set) var lines: [String] = []

        private static let limit = 500
        private var origin = Date()

        private init() {}

        /// One line per event.
        ///
        /// `event` is what happened. Everything after it is the state *after* the event was
        /// applied, which is what the next decision will read.
        func record(
            _ event: String,
            phase: String,
            settling: Bool,
            locked: Bool,
            cover: Bool,
            lockWindow: Bool,
            coverWindow: String
        ) {
            let t = String(format: "%8.3f", Date().timeIntervalSince(origin))
            let padded = event.padding(toLength: max(event.count, 22), withPad: " ", startingAt: 0)
            lines.append(
                "\(t)  \(padded)  phase=\(phase) settling=\(settling ? 1 : 0) "
                    + "locked=\(locked ? 1 : 0) cover=\(cover ? 1 : 0) "
                    + "lockWin=\(lockWindow ? 1 : 0) win=\(coverWindow)"
            )
            if lines.count > Self.limit {
                lines.removeFirst(lines.count - Self.limit)
            }
        }

        /// A bare note with no state, for things that are not lock events but change the
        /// reading, such as the trace being cleared before a deliberate sequence.
        func note(_ text: String) {
            let t = String(format: "%8.3f", Date().timeIntervalSince(origin))
            lines.append("\(t)  --- \(text) ---")
        }

        var text: String { lines.joined(separator: "\n") }

        func clear() {
            lines.removeAll()
            origin = Date()
            note("cleared")
        }
    }

#endif
