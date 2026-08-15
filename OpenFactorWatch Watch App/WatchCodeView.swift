import OpenFactorCore
import SwiftUI

/// One code, and the way back.
///
/// **Read only, and that is the security design rather than a scope cut.** No copying, no
/// editing, no deleting. The smallest device with the weakest lock gets the fewest
/// capabilities, and there is nothing here that can change or reveal anything the list did
/// not already show.
///
/// The secret is read at the moment a code is generated and never held.
///
/// ## Why the current time is not stored
///
/// This screen showed the previous visit's code for a moment, twice, and each fix missed
/// the same trap from a different angle.
///
/// Returning to an account you looked at earlier reuses this view, and every `@State` it
/// holds comes back with it. First that was the code itself, which identity per account did
/// not help with, since revisiting the same account is the same identity. Then the code was
/// gated on the time window it belonged to, and the stale value still got through, because
/// the stored clock came back stale as well and the guard compared an old window against an
/// old window.
///
/// So the clock is not stored. `TimelineView` supplies the time at render, which cannot be
/// stale by construction, and the held code is drawn only while it belongs to the window
/// that clock is in. Everything else is arithmetic on the date passed in, which is the same
/// rule the core follows: time comes in, it is never read.
///
/// The failure being designed out is worth naming, because it does not look like a failure.
/// A stale code is six digits that appear exactly as trustworthy as a good one, on a screen
/// whose only job is to be believed at a glance.
struct WatchCodeView: View {

    let store: any SecretStore
    let record: AccountRecord

    /// The last generated code and the window it belongs to. Both are replaced together,
    /// and neither is shown unless the second one still matches the clock.
    @State private var code: String?
    @State private var codeWindow: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let window = window(for: context.date)

            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Text(displayedCode(in: window).map(CodeFormatting.grouped) ?? placeholder)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    ring(at: context.date)
                }

                VStack(spacing: 0) {
                    Text(record.metadata.displayIssuer)
                        .font(.headline)
                        .foregroundStyle(WatchPalette.color(for: record.metadata.color))

                    if !record.metadata.name.isEmpty {
                        Text(record.metadata.name)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            // Runs on appear and again at every window boundary, which is the only time a
            // new code exists.
            .task(id: window) { refresh(at: context.date, window: window) }
        }
        // No navigation title. It was the issuer, which is already named beneath the code,
        // and on a screen this size the same word twice is the most expensive duplication
        // there is.
    }

    /// The held code, and only while it belongs to the window being drawn.
    private func displayedCode(in window: Double) -> String? {
        codeWindow == window ? code : nil
    }

    /// Blank while a current code is on its way, and honest when there will never be one.
    ///
    /// A space rather than dashes, because dashes read as a code that failed rather than as
    /// one that has not arrived, and the wait is a single frame.
    private var placeholder: String {
        if case .totp = record.metadata.generator { return " " }
        return "unavailable"
    }

    private func ring(at date: Date) -> some View {
        let remaining = remainingSeconds(at: date)

        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 4)

            Circle()
                .trim(from: 0, to: max(0, min(1, remaining / period)))
                .stroke(
                    // Red for the last few seconds, because a code you are halfway through
                    // typing is about to stop working. Matches the phone.
                    remaining <= 5 ? Color(red: 1, green: 0.35, blue: 0.32) : .white,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 24, height: 24)
        .accessibilityLabel("\(Int(remaining.rounded())) seconds left")
    }

    private var period: Double {
        guard case let .totp(configuration) = record.metadata.generator else { return 30 }
        return Double(configuration.period)
    }

    private func window(for date: Date) -> Double {
        (date.timeIntervalSince1970 / period).rounded(.down)
    }

    private func remainingSeconds(at date: Date) -> Double {
        period - date.timeIntervalSince1970.truncatingRemainder(dividingBy: period)
    }

    private func refresh(at date: Date, window: Double) {
        guard case let .totp(configuration) = record.metadata.generator else {
            code = nil
            codeWindow = nil
            return
        }

        do {
            let secret = try store.secret(for: record.id)
            code = TOTP.code(secret: secret, at: date, configuration: configuration)
            codeWindow = window
        } catch {
            code = nil
            codeWindow = nil
        }
    }
}
