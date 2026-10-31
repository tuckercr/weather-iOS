import SwiftUI

/// Sunny (the dog) and Misty (the cat) acting out `mood`, drawn with simple shapes after the app
/// icon: a golden retriever with a blue collar and a grey-and-white tuxedo cat. Same shapes and
/// colours as the Android `PetScene`.
struct PetScene: View {
    let mood: PetMood
    var moonPhase = MoonPhase(at: Date())
    /// The offline error: the Wi-Fi router lies on its side next to Misty.
    var knockedOverRouter = false
    /// Today's seasonal theme's extras (costumes, a jack-o'-lantern, bats); none on an ordinary day.
    var decorations: Set<SceneDecoration> = []
    @Environment(\.southernHemisphere) private var southernHemisphere

    // The scene is authored on a 260 x 150 grid and scaled to fit.
    private static let sceneWidth: CGFloat = 260
    private static let sceneHeight: CGFloat = 150

    var body: some View {
        Canvas { context, size in
            Self.draw(
                in: context,
                scale: size.width / Self.sceneWidth,
                mood: mood,
                moonPhase: moonPhase,
                southernHemisphere: southernHemisphere,
                knockedOverRouter: knockedOverRouter,
                decorations: decorations
            )
        }
        .aspectRatio(Self.sceneWidth / Self.sceneHeight, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Sunny the dog and Misty the cat reacting to the weather")
    }
}

extension PetScene {
    /// The scene at `scale` points per scene unit, with its top-left at the context's origin. Shared
    /// by `PetScene` and `PetSceneIcon`. The sky's background colour is left to the caller.
    fileprivate static func draw(
        in context: GraphicsContext,
        scale: CGFloat,
        mood: PetMood,
        moonPhase: MoonPhase,
        southernHemisphere: Bool,
        knockedOverRouter: Bool = false,
        decorations: Set<SceneDecoration> = []
    ) {
        let painter = Painter(context: context, scale: scale)
        painter.sky(mood, moonPhase: moonPhase, southernHemisphere: southernHemisphere)
        if decorations.contains(.bats) { painter.bats(night: mood == .night) }
        painter.oval(Palette.ground, cx: 130, cy: 140, rx: 110, ry: 8)
        // The pets are authored cat-left, dog-right; mirrored so Sunny (the dog) stands on the
        // left, matching the name. The sky stays put, and the ground shadow is symmetrical.
        var mirrored = context
        mirrored.translateBy(x: sceneWidth * scale, y: 0)
        mirrored.scaleBy(x: -1, y: 1)
        let pets = Painter(context: mirrored, scale: scale)
        pets.cat(mood)
        pets.dog(mood)
        // A costume replaces the weather's own props (sunglasses, scarves); the umbrella stays.
        let dressedUp = !decorations.isDisjoint(with: [.witchHat, .bandana]) && mood != .night
        if !dressedUp || mood == .rain { pets.props(mood) }
        pets.decorations(decorations, mood: mood)
        if knockedOverRouter {
            // Tipped back on the ground to Misty's right, antennas splayed.
            let pivot = CGPoint(x: 216 * scale, y: 128 * scale)
            var tipped = context
            tipped.translateBy(x: pivot.x, y: pivot.y)
            tipped.rotate(by: .degrees(-18))
            tipped.translateBy(x: -pivot.x, y: -pivot.y)
            Painter(context: tipped, scale: scale).knockedOverRouter()
        }
    }
}

/// The pets in `mood` on their sky colour, square: the picture attached to notifications. Cut tight
/// round the pets (scene x 63...197, y 24...158) so they stay recognisable in a small thumbnail; the
/// sun and moon fall outside it, and the pets' props still show the mood. Same crop as Android.
struct PetSceneIcon: View {
    let mood: PetMood
    var southernHemisphere = false
    var moonPhase = MoonPhase(at: Date())

    private static let side: CGFloat = 134
    private static let left: CGFloat = 63
    private static let top: CGFloat = 24

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(mood.skyColor))
            let scale = size.width / Self.side
            var cropped = context
            cropped.translateBy(x: -Self.left * scale, y: -Self.top * scale)
            PetScene.draw(
                in: cropped,
                scale: scale,
                mood: mood,
                moonPhase: moonPhase,
                southernHemisphere: southernHemisphere
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private enum Palette {
    static let catFur = Color(hex: 0x5F5E5A)
    static let catBelly = Color(hex: 0xF1EFE8)
    static let catInnerEar = Color(hex: 0xED93B1)
    static let catNose = Color(hex: 0xE8849A)
    static let collar = Color(hex: 0x185FA5)
    static let mouth = Color(hex: 0x412402)
    static let tongueSoft = Color(hex: 0xED93B1)
    static let shine = Color.white
    static let dogFur = Color(hex: 0xE9B158)
    static let dogFace = Color(hex: 0xFAC775)
    static let dogEar = Color(hex: 0xBA7517)
    static let outline = Color(hex: 0x10324A)
    static let umbrella = Color(hex: 0x185FA5)
    static let sun = Color(hex: 0xEF9F27)
    static let sunHot = Color(hex: 0xD85A30)
    static let scarf = Color(hex: 0xD85A30)
    static let scarfAlt = Color(hex: 0x993556)
    static let tongue = Color(hex: 0xD4537E)
    static let cloud = Color.white
    static let stormCloud = Color(hex: 0x5F6B7A)
    static let bolt = Color(hex: 0xFAC775)
    static let moon = Color(hex: 0xF1EFE8)
    /// The moon's unlit part: just darker than the night sky, so the disc shows faintly.
    static let moonUnlit = Color(hex: 0x34416E)
    static let ground = Color.black.opacity(0.2)
    static let router = Color(hex: 0x4A5A6A)
    static let routerLight = Color(hex: 0x97C459)
    static let bat = Color(hex: 0x412402)
    static let batNight = Color(hex: 0x0B0B0B)
    static let batPurple = Color(hex: 0x7F77DD)
    static let star = Color(hex: 0xCECBF6)
    static let witchHat = Color(hex: 0x26215C)
    static let hatBand = Color(hex: 0xEF9F27)
    static let bandana = Color(hex: 0xD85A30)
    static let pumpkin = Color(hex: 0xD85A30)
    static let pumpkinLit = Color(hex: 0xEF9F27)
    static let pumpkinFace = Color(hex: 0x412402)
    static let pumpkinGlow = Color(hex: 0xFAEEDA)
    static let pumpkinStem = Color(hex: 0x3B6D11)
}

/// Draws in scene units, scaling everything by `scale`.
private struct Painter {
    let context: GraphicsContext
    let scale: CGFloat

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }

    func oval(_ color: Color, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat) {
        let rect = CGRect(x: (cx - rx) * scale, y: (cy - ry) * scale, width: rx * 2 * scale, height: ry * 2 * scale)
        context.fill(Path(ellipseIn: rect), with: .color(color))
    }

    func circle(_ color: Color, cx: CGFloat, cy: CGFloat, r: CGFloat) {
        oval(color, cx: cx, cy: cy, rx: r, ry: r)
    }

    func rect(_ color: Color, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        context.fill(Path(CGRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)), with: .color(color))
    }

    func poly(_ color: Color, _ points: [(CGFloat, CGFloat)]) {
        var path = Path()
        path.addLines(points.map { point($0.0, $0.1) })
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }

    func cloud(_ color: Color, cx: CGFloat, cy: CGFloat) {
        oval(color, cx: cx, cy: cy + 6, rx: 28, ry: 12)
        circle(color, cx: cx - 10, cy: cy, r: 13)
        circle(color, cx: cx + 8, cy: cy - 4, r: 16)
    }

    /// The moon at `phase`: the unlit disc, the lit half, then the terminator, an ellipse that adds
    /// to the lit half (gibbous) or cuts into it (crescent). Waxing is lit on the right in the north
    /// and on the left in the south.
    func moon(_ phase: MoonPhase, southernHemisphere: Bool, cx: CGFloat, cy: CGFloat, r: CGFloat) {
        circle(Palette.moonUnlit, cx: cx, cy: cy, r: r)
        switch phase {
        case .new: return
        case .full:
            circle(Palette.moon, cx: cx, cy: cy, r: r)
            return
        default: break
        }
        let litOnRight = phase.isWaxing != southernHemisphere
        var half = context
        half.clip(to: Path(CGRect(x: (litOnRight ? cx : cx - r) * scale, y: (cy - r) * scale, width: r * scale, height: r * 2 * scale)))
        half.fill(Path(ellipseIn: CGRect(x: (cx - r) * scale, y: (cy - r) * scale, width: r * 2 * scale, height: r * 2 * scale)), with: .color(Palette.moon))
        let rx = abs(cos(phase.drawAngleDegrees * .pi / 180)) * r
        oval(phase.isGibbous ? Palette.moon : Palette.moonUnlit, cx: cx, cy: cy, rx: rx, ry: r)
    }

    func sky(_ mood: PetMood, moonPhase: MoonPhase, southernHemisphere: Bool) {
        switch mood {
        case .sunny:
            circle(Palette.sun, cx: 220, cy: 32, r: 18)
        case .hot:
            circle(Palette.sunHot, cx: 220, cy: 32, r: 24)
        case .night:
            moon(moonPhase, southernHemisphere: southernHemisphere, cx: 215, cy: 30, r: 16)
        case .cloudy:
            cloud(Palette.cloud, cx: 210, cy: 30)
        case .rain:
            for (x, y) in [(30, 14), (60, 36), (200, 58), (232, 20), (45, 70), (245, 44)] as [(CGFloat, CGFloat)] {
                rect(Palette.umbrella, x: x, y: y, width: 3, height: 11)
            }
        case .storm:
            cloud(Palette.stormCloud, cx: 200, cy: 28)
            poly(Palette.bolt, [(205, 40), (196, 58), (204, 58), (198, 74), (214, 52), (206, 52), (212, 40)])
        case .snow, .cold:
            for (x, y) in [(30, 18), (70, 44), (200, 22), (240, 50), (110, 12), (180, 40)] as [(CGFloat, CGFloat)] {
                circle(Palette.cloud, cx: x, cy: y, r: 4)
            }
        }
    }

    /// A tuxedo cat, as on the app icon: grey with pink inner ears, a white blaze down the face
    /// into white cheeks, a small pink nose, a "w" mouth and whiskers.
    func cat(_ mood: PetMood) {
        // A storm sends the cat low (hiding); otherwise it sits upright.
        let dy: CGFloat = mood == .storm ? 14 : 0
        oval(Palette.catFur, cx: 95, cy: 112 + dy / 2, rx: 24, ry: 26 - dy / 2)
        circle(Palette.catFur, cx: 95, cy: 80 + dy, r: 20)
        poly(Palette.catFur, [(78, 68 + dy), (82, 50 + dy), (92, 64 + dy)])
        poly(Palette.catFur, [(98, 64 + dy), (108, 50 + dy), (112, 68 + dy)])
        poly(Palette.catInnerEar, [(81, 64 + dy), (83.5, 55 + dy), (89, 62 + dy)])
        poly(Palette.catInnerEar, [(101, 62 + dy), (106.5, 55 + dy), (109, 64 + dy)])
        poly(Palette.catBelly, [(93, 66 + dy), (97, 66 + dy), (101, 86 + dy), (89, 86 + dy)])
        oval(Palette.catBelly, cx: 90, cy: 90 + dy, rx: 7.5, ry: 6.5)
        oval(Palette.catBelly, cx: 100, cy: 90 + dy, rx: 7.5, ry: 6.5)
        oval(Palette.catBelly, cx: 95, cy: 118 + dy / 2, rx: 12, ry: 14 - dy / 3)
        poly(Palette.catNose, [(92.6, 85.5 + dy), (97.4, 85.5 + dy), (95, 88.6 + dy)])
        var mouth = Path()
        mouth.move(to: point(95, 88.6 + dy))
        mouth.addLine(to: point(95, 90.3 + dy))
        mouth.move(to: point(91.6, 90.3 + dy))
        mouth.addQuadCurve(to: point(95, 90.3 + dy), control: point(93.3, 92.6 + dy))
        mouth.addQuadCurve(to: point(98.4, 90.3 + dy), control: point(96.7, 92.6 + dy))
        context.stroke(mouth, with: .color(Palette.outline), style: StrokeStyle(lineWidth: 1.1 * scale, lineCap: .round))
        var whiskers = Path()
        for (from, to) in [((85.0, 89.0), (71.0, 86.5)), ((85.0, 91.5), (71.0, 92.5)),
                           ((105.0, 89.0), (119.0, 86.5)), ((105.0, 91.5), (119.0, 92.5))] {
            whiskers.move(to: point(from.0, from.1 + dy))
            whiskers.addLine(to: point(to.0, to.1 + dy))
        }
        // Dark whiskers vanish into the night sky, so they're pale after dark.
        let whiskerColor = mood == .night ? Palette.catBelly.opacity(0.6) : Palette.outline.opacity(0.75)
        context.stroke(whiskers, with: .color(whiskerColor), style: StrokeStyle(lineWidth: 0.8 * scale, lineCap: .round))
        eyes(mood, left: 88, right: 102, y: 78 + dy)
    }

    /// A golden retriever, as on the app icon: floppy ears, eyebrows, a shiny nose, an open smile
    /// and a blue collar with a sun tag. Asleep at night the mouth is closed.
    func dog(_ mood: PetMood) {
        oval(Palette.dogFur, cx: 160, cy: 110, rx: 28, ry: 28)
        // A rim of body fur round the face, so it doesn't vanish into the sunny sky (the same colour).
        circle(Palette.dogFur, cx: 160, cy: 76, r: 25.5)
        collar()
        circle(Palette.dogFace, cx: 160, cy: 76, r: 23)
        tiltedOval(Palette.dogEar, cx: 139, cy: 80, rx: 8, ry: 15, degrees: 12, pivotY: 70)
        tiltedOval(Palette.dogEar, cx: 181, cy: 80, rx: 8, ry: 15, degrees: -12, pivotY: 70)
        collarTag()
        var brows = Path()
        for x in [152.0, 168.0] {
            brows.move(to: point(x - 3.5, 66))
            brows.addQuadCurve(to: point(x + 3.5, 66), control: point(x, 63.5))
        }
        context.stroke(brows, with: .color(Palette.dogEar), style: StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round))
        eyes(mood, left: 152, right: 168, y: 72)
        oval(Palette.outline, cx: 160, cy: 81, rx: 5.6, ry: 4)
        if mood != .night { oval(Palette.shine.opacity(0.6), cx: 158.4, cy: 79.8, rx: 1.6, ry: 0.9) }
        if mood == .night {
            var smile = Path()
            smile.move(to: point(154, 88))
            smile.addQuadCurve(to: point(166, 88), control: point(160, 93))
            context.stroke(smile, with: .color(Palette.outline), style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round))
        } else {
            var mouth = Path()
            mouth.move(to: point(153, 86.5))
            mouth.addQuadCurve(to: point(167, 86.5), control: point(160, 97))
            mouth.closeSubpath()
            context.fill(mouth, with: .color(Palette.mouth))
            // Panting in the heat: the tongue hangs out.
            if mood == .hot {
                oval(Palette.tongue, cx: 160, cy: 95, rx: 3.8, ry: 6)
            } else {
                oval(Palette.tongueSoft, cx: 160, cy: 92.2, rx: 3.4, ry: 2.6)
            }
        }
    }

    /// A blue collar round Sunny's neck: it dips under the chin, behind the face, with its ends
    /// under the ears.
    private func collar() {
        var band = Path()
        band.move(to: point(140, 94))
        band.addQuadCurve(to: point(180, 94), control: point(160, 109))
        band.addLine(to: point(180, 99))
        band.addQuadCurve(to: point(140, 99), control: point(160, 115))
        band.closeSubpath()
        context.fill(band, with: .color(Palette.collar))
    }

    /// The sun tag, hanging from the front of the collar.
    private func collarTag() {
        circle(Palette.dogEar, cx: 160, cy: 109.5, r: 4.2)
        circle(Palette.dogFace, cx: 160, cy: 109.5, r: 3.3)
        circle(Palette.shine, cx: 160, cy: 109.5, r: 1.4)
    }

    /// An oval turned `degrees` about the point above its centre at `pivotY`, as ears hang from the
    /// head.
    private func tiltedOval(_ color: Color, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, degrees: Double, pivotY: CGFloat) {
        var turned = context
        turned.translateBy(x: cx * scale, y: pivotY * scale)
        turned.rotate(by: .degrees(degrees))
        turned.translateBy(x: -cx * scale, y: -pivotY * scale)
        let rect = CGRect(x: (cx - rx) * scale, y: (cy - ry) * scale, width: rx * 2 * scale, height: ry * 2 * scale)
        turned.fill(Path(ellipseIn: rect), with: .color(color))
    }

    /// Open eyes with a catch-light, or closed, smiling curves when the pets are asleep at night.
    private func eyes(_ mood: PetMood, left: CGFloat, right: CGFloat, y: CGFloat) {
        for x in [left, right] {
            if mood == .night {
                var line = Path()
                line.move(to: point(x - 3, y))
                line.addQuadCurve(to: point(x + 3, y), control: point(x, y + 2))
                context.stroke(line, with: .color(Palette.outline), style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round))
            } else {
                circle(Palette.outline, cx: x, cy: y, r: 2.95)
                circle(Palette.shine, cx: x + 0.9, cy: y - 0.9, r: 0.95)
            }
        }
    }

    /// A bat: two wings meeting at the body, `width` scene units across.
    private func bat(_ color: Color, x: CGFloat, y: CGFloat, width: CGFloat = 16) {
        let w = width / 2
        var path = Path()
        path.move(to: point(x, y))
        path.addQuadCurve(to: point(x + w, y), control: point(x + w / 2, y - w))
        path.addQuadCurve(to: point(x + width, y), control: point(x + w * 1.5, y - w))
        path.addQuadCurve(to: point(x + w, y + w * 0.7), control: point(x + w * 1.5, y + w * 0.2))
        path.addQuadCurve(to: point(x, y), control: point(x + w / 2, y + w * 0.2))
        context.fill(path, with: .color(color))
    }

    /// Bats by day; by night bats and a few stars round the moon.
    func bats(night: Bool) {
        if night {
            for (x, y) in [(30, 16), (78, 30), (140, 12)] as [(CGFloat, CGFloat)] {
                circle(Palette.star, cx: x, cy: y, r: 1.4)
            }
            bat(Palette.batNight, x: 168, y: 24, width: 22)
            bat(Palette.batPurple, x: 30, y: 54, width: 18)
        } else {
            bat(Palette.bat, x: 24, y: 34, width: 22)
            bat(Palette.bat, x: 188, y: 62, width: 16)
        }
    }

    /// The costumes and props in `decorations`. Asleep at night the pets have taken their costumes
    /// off; the jack-o'-lantern on Misty's side is lit then. Drawn in the pets' mirrored space, so
    /// Misty is at x 95 and the pumpkin at x 38.
    func decorations(_ decorations: Set<SceneDecoration>, mood: PetMood) {
        let night = mood == .night
        let dy: CGFloat = mood == .storm ? 14 : 0
        if decorations.contains(.witchHat), !night {
            poly(Palette.witchHat, [(80, 62 + dy), (99, 22 + dy), (111, 62 + dy)])
            oval(Palette.witchHat, cx: 95, cy: 63 + dy, rx: 27, ry: 4.5)
            rect(Palette.hatBand, x: 81, y: 56 + dy, width: 29, height: 5)
        }
        if decorations.contains(.bandana), !night {
            poly(Palette.bandana, [(142, 97), (178, 97), (160, 111)])
            circle(Palette.pumpkinFace, cx: 153, cy: 101, r: 1.6)
            circle(Palette.pumpkinFace, cx: 167, cy: 101, r: 1.6)
        }
        if decorations.contains(.jackOLantern) { jackOLantern(lit: night) }
    }

    private func jackOLantern(lit: Bool) {
        let body = lit ? Palette.pumpkinLit : Palette.pumpkin
        let face = lit ? Palette.pumpkinGlow : Palette.pumpkinFace
        oval(body, cx: 38, cy: 126, rx: 21, ry: 16)
        rect(Palette.pumpkinStem, x: 35.5, y: 104, width: 5, height: 8)
        poly(face, [(26, 123), (31, 116), (36, 123)])
        poly(face, [(40, 123), (45, 116), (50, 123)])
        poly(face, [(25, 130), (51, 130), (47, 136), (43, 133), (38, 137), (33, 133), (29, 136)])
    }

    func knockedOverRouter() {
        for (from, to) in [((202.0, 122.0), (196.0, 104.0)), ((230.0, 122.0), (236.0, 106.0))] {
            var antenna = Path()
            antenna.move(to: point(from.0, from.1))
            antenna.addLine(to: point(to.0, to.1))
            context.stroke(antenna, with: .color(Palette.outline), lineWidth: 2.5 * scale)
        }
        let body = CGRect(x: 196 * scale, y: 120 * scale, width: 40 * scale, height: 14 * scale)
        context.fill(Path(roundedRect: body, cornerRadius: 3 * scale), with: .color(Palette.router))
        for x in [206.0, 214.0, 222.0] {
            circle(Palette.routerLight, cx: x, cy: 127, r: 1.8)
        }
    }

    func props(_ mood: PetMood) {
        switch mood {
        case .rain:
            var canopy = Path()
            canopy.move(to: point(70, 56))
            canopy.addQuadCurve(to: point(190, 56), control: point(128, 0))
            canopy.closeSubpath()
            context.fill(canopy, with: .color(Palette.umbrella))
            rect(Palette.outline, x: 128, y: 54, width: 3, height: 42)
        case .sunny:
            // Sunglasses on the dog.
            rect(Palette.outline, x: 146, y: 68, width: 12, height: 7)
            rect(Palette.outline, x: 162, y: 68, width: 12, height: 7)
            rect(Palette.outline, x: 157, y: 70, width: 6, height: 2)
        case .snow, .cold:
            rect(Palette.scarf, x: 136, y: 94, width: 48, height: 9)
            rect(Palette.scarfAlt, x: 72, y: 96, width: 46, height: 8)
        default:
            break
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(PetMood.allCases, id: \.self) { mood in
                PetScene(mood: mood)
                    .padding()
                    .background(mood.skyColor, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
    }
}
