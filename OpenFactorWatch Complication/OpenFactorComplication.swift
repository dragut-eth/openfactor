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
            // Sized to match the app icon rather than to fill the space. See `iconCubeFraction`.
            mark.scaleEffect(Self.iconCubeFraction)
        }
    }

    /// How much of the icon's canvas the cube occupies, **measured rather than chosen**.
    ///
    /// In `AppIcon-1024.png` the cube's ink is 720 of 1024 pixels tall, centered: 0.703. The
    /// first version of this view used `.padding(2)` instead, which filled the complication's
    /// circle to about 92 per cent, so on a watch face the cube stood visibly larger than the
    /// same cube in the app grid one screen away. Two renderings of one mark have to agree, and
    /// the icon artwork is the original, so the complication follows it.
    ///
    /// **Applied by scaling, not by a `GeometryReader`.** The reader version measured the space
    /// offered and sized the mark against it, which is fine in a circle and wrong in a corner:
    /// `.accessoryCorner` shares this branch, has a small curved content area, and a greedy
    /// reader inside it is how a corner mark ends up tiny or displaced. Scaling needs no
    /// measurement, changes no layout, and gives every family the same proportion.
    private static let iconCubeFraction: CGFloat = 0.703

    /// The extracted piece, which is also the watch app's icon.
    ///
    /// Drawn rather than shipped as an image, because a complication is a template: the
    /// system tints it with the watch face's colour, so what we supply is shape and
    /// opacity, not colour. The three faces are told apart by opacity alone, following the
    /// icon's light rule, which is what keeps it reading as a solid with a light on it
    /// rather than a flat hexagon.
    private var mark: some View {
        ZStack {
            CubeletFace(.top).fill(.white)
            CubeletFace(.left).fill(.white.opacity(0.72))
            CubeletFace(.right).fill(.white.opacity(0.45))
        }
        .aspectRatio(0.866, contentMode: .fit)
        .widgetAccentable()
    }
}

/// One face of the piece, in the icon's exact proportions.
///
/// The geometry falls out beautifully in unit terms, which is worth writing down because
/// it makes the shape auditable against `docs/design/icon-watch.svg` by arithmetic: the
/// bounding box has a width to height ratio of root three over two, the side vertices sit
/// at one quarter and three quarters of the height, and every other point is a midpoint or
/// a corner. The 0.866 aspect ratio applied by the caller is that root three over two.
struct CubeletFace: Shape {

    enum Face {
        case top, left, right
    }

    let face: Face

    init(_ face: Face) {
        self.face = face
    }

    func path(in rect: CGRect) -> Path {
        let quarter = rect.minY + rect.height * 0.25
        let threeQuarters = rect.minY + rect.height * 0.75

        let north = CGPoint(x: rect.midX, y: rect.minY)
        let east = CGPoint(x: rect.maxX, y: quarter)
        let west = CGPoint(x: rect.minX, y: quarter)
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let south = CGPoint(x: rect.midX, y: rect.maxY)

        let corners: [CGPoint] = switch face {
        case .top: [north, east, centre, west]
        case .left: [west, centre, south, CGPoint(x: rect.minX, y: threeQuarters)]
        case .right: [east, centre, south, CGPoint(x: rect.maxX, y: threeQuarters)]
        }

        var path = Path()
        path.addLines(corners)
        path.closeSubpath()
        return path
    }
}
