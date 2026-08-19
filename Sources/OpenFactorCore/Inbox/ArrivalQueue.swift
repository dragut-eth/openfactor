import Foundation

/// Which arrival is on screen and what happens to the next one, as a value.
///
/// ## Why this is not a pair of optionals in a view
///
/// Two rounds of gate A4 dealt with the same three lines. Round one found that a second URL
/// replaced whatever was pending, so an `otpauth://` opened while a shared image waited to be
/// confirmed destroyed that image with no sign anything had happened. The fix was
/// `guard arrival == nil else { return }`, and round two found the other half of it: the second
/// arrival is now simply lost. Somebody taps a link, the app comes forward, and nothing happens.
///
/// Neither version had a test, because the rule lived in a closure in the app's scene body.
///
/// The rule is: **the first arrival keeps the screen, and one more is held behind it.** A third
/// is refused, and that refusal is deliberate rather than a limit somebody forgot to raise. A
/// queue that grows is a queue that can be filled by whatever is sending links.
public struct ArrivalQueue<Arrival> {

    /// What is on screen now, or `nil` when nothing is.
    public private(set) var current: Arrival?

    /// The one held behind it.
    public private(set) var next: Arrival?

    public init() {}

    /// Whether an arrival was accepted at all, which the caller may want to report.
    @discardableResult
    public mutating func arrived(_ arrival: Arrival) -> Bool {
        if current == nil {
            current = arrival
            return true
        }
        if next == nil {
            next = arrival
            return true
        }
        // Two is the bound. Whatever is sending a third can send a thousand.
        return false
    }

    /// The person answered or dismissed what was on screen. Promotes whatever was waiting.
    public mutating func finished() {
        current = next
        next = nil
    }
}

extension ArrivalQueue: Sendable where Arrival: Sendable {}
