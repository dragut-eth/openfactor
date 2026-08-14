import OpenFactorCore
import SwiftUI

/// One account, as it appears in the list.
///
/// Everything it draws is passed in. It holds no state, runs no timer, and never touches
/// a store, so it can be reviewed against the design in previews without any of that
/// existing. The list that drives it arrives in PR 7.
struct AccountCard: View {

    /// What a card needs. Deliberately not an `AccountRecord`: the card needs a code and
    /// a countdown, which are not stored, and it must never be handed a secret.
    struct Model: Sendable, Equatable {
        var issuer: String
        var name: String
        var code: String

        /// How long this code stays valid, or `nil` for a counter based account.
        ///
        /// Counter based codes do not expire on a clock. They advance when the user asks
        /// for the next one, so a countdown would be a lie. Those accounts get no ring at
        /// all rather than a ring that never moves.
        var secondsRemaining: TimeInterval?

        var period: Int
        var color: AccountColor

        /// How much of the current code's life is left, from 1 down to 0, or `nil` when
        /// there is nothing to count down.
        var fractionRemaining: Double? {
            guard let secondsRemaining, period > 0 else { return nil }
            return min(max(secondsRemaining / Double(period), 0), 1)
        }

        var isExpiring: Bool {
            guard let secondsRemaining else { return false }
            return secondsRemaining <= Tokens.Ring.warningThreshold
        }
    }

    let model: Model

    @Environment(\.colorScheme) private var colorScheme

    /// Scaled rather than fixed, so the code follows the reader's text size setting.
    @ScaledMetric(relativeTo: .largeTitle) private var codeSize = Tokens.Text.codeSize

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
                Text(model.issuer)
                    .font(Tokens.Text.issuer)
                    .foregroundStyle(Tokens.OnCard.primary)

                Text(model.name)
                    .font(Tokens.Text.name)
                    .foregroundStyle(Tokens.OnCard.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(CodeFormatting.grouped(model.code))
                    // Monospaced with tabular figures, so digits keep their positions
                    // rather than jittering every time the code changes. Rounded keeps it
                    // from looking like a terminal.
                    .font(.system(size: codeSize, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(Tokens.OnCard.primary)
                    .padding(.top, Tokens.Spacing.tight)
            }

            Spacer(minLength: Tokens.Spacing.medium)

            if let fractionRemaining = model.fractionRemaining {
                CountdownRing(fractionRemaining: fractionRemaining, isExpiring: model.isExpiring)
            }
        }
        .padding(Tokens.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.gradient(for: model.color, in: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.issuer), \(model.name)")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let spoken = CodeFormatting.spokenDigits(model.code)

        guard let secondsRemaining = model.secondsRemaining else {
            return "Code \(spoken)"
        }

        return "Code \(spoken), \(Int(secondsRemaining.rounded())) seconds remaining"
    }
}

/// The depleting ring in the corner of a card.
private struct CountdownRing: View {
    let fractionRemaining: Double
    let isExpiring: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Tokens.OnCard.primary.opacity(0.25), lineWidth: Tokens.Ring.lineWidth)

            Circle()
                .trim(from: 0, to: fractionRemaining)
                .stroke(
                    isExpiring ? Tokens.OnCard.ringExpiring : Tokens.OnCard.ring,
                    style: StrokeStyle(lineWidth: Tokens.Ring.lineWidth, lineCap: .round)
                )
                // Trim starts at three o'clock, so the ring is rotated to deplete from
                // the top, which is the direction people read a clock face.
                .rotationEffect(.degrees(-90))
        }
        .frame(width: Tokens.Ring.size, height: Tokens.Ring.size)
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

private func sample(
    _ issuer: String,
    _ name: String,
    _ code: String,
    _ color: AccountColor,
    remaining: TimeInterval = 21
) -> AccountCard.Model {
    AccountCard.Model(
        issuer: issuer,
        name: name,
        code: code,
        secondsRemaining: remaining,
        period: 30,
        color: color
    )
}

private var samples: [AccountCard.Model] {
    [
        sample("Google", "xcany@example.com", "751702", .red),
        sample("AWS", "Production", "802283", .yellow, remaining: 3),
        sample("Okta", "xcany@example.com", "290344", .indigo),
        sample("GitHub", "octocat", "88259512", .gray, remaining: 27),
    ]
}

#Preview("Cards, dark") {
    ScrollView {
        VStack(spacing: Tokens.Spacing.cardGap) {
            ForEach(Array(samples.enumerated()), id: \.offset) { AccountCard(model: $0.element) }
        }
        .padding()
    }
    .background(Tokens.Surface.background)
    .preferredColorScheme(.dark)
}

#Preview("Cards, light") {
    ScrollView {
        VStack(spacing: Tokens.Spacing.cardGap) {
            ForEach(Array(samples.enumerated()), id: \.offset) { AccountCard(model: $0.element) }
        }
        .padding()
    }
    .background(Tokens.Surface.background)
    .preferredColorScheme(.light)
}

#Preview("Every colour") {
    ScrollView {
        VStack(spacing: Tokens.Spacing.cardGap) {
            ForEach(AccountColor.allCases, id: \.self) { color in
                AccountCard(model: sample(color.rawValue.capitalized, "someone@example.com", "123456", color))
            }
        }
        .padding()
    }
    .background(Tokens.Surface.background)
}
