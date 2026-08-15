import Combine
import OpenFactorCore
import SwiftUI

/// One code, and the way back.
///
/// **Read only, and that is the security design rather than a scope cut.** No copying, no
/// editing, no deleting. The smallest device with the weakest lock gets the fewest
/// capabilities, and there is nothing here that can change or reveal anything the list did
/// not already show.
///
/// The secret is read at the moment a code is generated and never held. The timer drives a
/// date, and the date drives a fresh read, which is the same shape the phone uses.
struct WatchCodeView: View {

    let store: any SecretStore
    let record: AccountRecord

    @State private var code: String?
    @State private var now = Date()

    /// Whether a read has been attempted yet, so the placeholder can tell "still loading"
    /// apart from "this account cannot produce a code".
    @State private var hasRead = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text(code.map(CodeFormatting.grouped) ?? (hasRead ? "unavailable" : " "))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                ring
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
        // No navigation title. It was the issuer, which is already named beneath the
        // code, and on a screen this size the same word twice is the most expensive
        // duplication there is.
        .onReceive(tick) { now = $0 }
        .task(id: now.timeIntervalSince1970.rounded()) { refresh() }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 4)

            Circle()
                .trim(from: 0, to: remainingFraction)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 24, height: 24)
        .accessibilityLabel("\(Int(remainingSeconds.rounded())) seconds left")
    }

    /// Red for the last few seconds, because a code you are halfway through typing is about
    /// to stop working and that is worth being told loudly. Matches the phone.
    private var ringColor: Color {
        remainingSeconds <= 5 ? Color(red: 1, green: 0.35, blue: 0.32) : .white
    }

    private var period: Double {
        guard case let .totp(configuration) = record.metadata.generator else { return 30 }
        return Double(configuration.period)
    }

    private var remainingSeconds: Double {
        period - now.timeIntervalSince1970.truncatingRemainder(dividingBy: period)
    }

    private var remainingFraction: Double {
        max(0, min(1, remainingSeconds / period))
    }

    private func refresh() {
        defer { hasRead = true }

        guard case let .totp(configuration) = record.metadata.generator else {
            code = nil
            return
        }

        do {
            let secret = try store.secret(for: record.id)
            code = TOTP.code(secret: secret, at: now, configuration: configuration)
        } catch {
            code = nil
        }
    }
}
