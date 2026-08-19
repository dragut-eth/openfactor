import Foundation
import Testing

@testable import OpenFactorCore

/// The rule for what happens when two things arrive at once, which took two rounds to get right
/// and had no test either time.
@Suite("Arrival queue")
struct ArrivalQueueTests {

    /// **Round one's defect.** A second URL replaced whatever was pending, so a link opened while
    /// a shared image waited to be confirmed destroyed that image with no sign anything happened.
    @Test("A second arrival does not replace the first")
    func theFirstKeepsTheScreen() {
        var queue = ArrivalQueue<String>()

        queue.arrived("the shared image")
        queue.arrived("a link opened a moment later")

        #expect(queue.current == "the shared image")
    }

    /// **Round two's defect**, which was the fix for round one's. The second arrival was dropped
    /// entirely: somebody taps a link, the app comes forward, and nothing happens.
    @Test("The second arrival is held, not lost")
    func theSecondIsHeld() {
        var queue = ArrivalQueue<String>()

        queue.arrived("the shared image")
        queue.arrived("a link opened a moment later")

        queue.finished()
        #expect(queue.current == "a link opened a moment later", "it comes forward in its turn")

        queue.finished()
        #expect(queue.current == nil)
    }

    /// Two is the bound, and the refusal is reported rather than silent.
    @Test("A third arrival is refused, and says so")
    func aThirdIsRefused() {
        var queue = ArrivalQueue<String>()

        let first = queue.arrived("first")
        let second = queue.arrived("second")
        let third = queue.arrived("third")

        #expect(first)
        #expect(second)
        #expect(!third, "whatever can send a third can send a thousand")

        #expect(queue.current == "first")
        #expect(queue.next == "second")
    }

    @Test("Finishing an empty queue does nothing")
    func finishingEmptyIsInert() {
        var queue = ArrivalQueue<String>()
        queue.finished()
        #expect(queue.current == nil)
        #expect(queue.next == nil)
    }

    /// The ordinary case: one thing at a time, each replaced by the next after it is answered.
    @Test("One at a time works the way it always did")
    func oneAtATime() {
        var queue = ArrivalQueue<String>()

        queue.arrived("first")
        #expect(queue.current == "first")

        queue.finished()
        queue.arrived("second")
        #expect(queue.current == "second")
        #expect(queue.next == nil)
    }
}
