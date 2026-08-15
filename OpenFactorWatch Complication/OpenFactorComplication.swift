import SwiftUI
import WidgetKit

/// A complication that launches the app, and shows nothing.
///
/// **It deliberately holds no data at all.** The obvious complication for an authenticator
/// is a live code on the watch face, and it is the wrong feature: a watch face is readable
/// by anyone standing next to you, glanced at over a shoulder, photographed across a table.
/// A second factor sitting there permanently is a second factor shown to the room all day.
/// Decided by Xavier, and it matches the same call made for the account list, where codes
/// are shown one at a time on request rather than all at once.
///
/// The consequence worth stating: this extension never reads the Keychain, so it has no
/// entitlement to reach the shared access group and could not show a code if a future
/// change asked it to. That is the design, not an oversight. Anything that gives this target
/// Keychain access is reversing a security decision and should be treated as such.
@main
struct OpenFactorComplicationBundle: WidgetBundle {
    var body: some Widget {
        OpenFactorComplication()
    }
}

struct OpenFactorComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenFactorLauncher", provider: Provider()) { _ in
            ComplicationView()
        }
        .configurationDisplayName("OpenFactor")
        .description("Opens OpenFactor. It never shows a code on your watch face.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}

/// One entry, never refreshed, because there is nothing to refresh.
///
/// A timeline of one with a distant policy costs the system nothing and, more to the point,
/// gives this extension no reason to ever wake up and do work near secret material.
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry() }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry()], policy: .never))
    }
}

struct Entry: TimelineEntry {
    /// Required by the protocol. Fixed rather than `Date()`, since a timeline that never
    /// reloads has no use for the current time and reading a clock here would be noise.
    let date = Date(timeIntervalSince1970: 0)
}

/// The mark, sized by family.
///
/// The inline family is text only, which is why it says the app's name rather than drawing
/// anything, and it is the one place the name earns its space: on a watch face full of other
/// apps' complications, an unlabelled shape is a puzzle.
struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("OpenFactor")

        case .accessoryRectangular:
            HStack(spacing: 6) {
                mark
                Text("OpenFactor").font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:
            mark
        }
    }

    /// A nod to the app icon, drawn rather than shipped as an image so it inherits the
    /// complication tint instead of fighting it.
    private var mark: some View {
        Image(systemName: "square.grid.2x2")
            .font(.title3)
            .widgetAccentable()
    }
}
