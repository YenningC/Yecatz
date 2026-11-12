import Cocoa
import CoreText

private enum PixelType {
    static let font: NSFont = {
        if let url = Bundle.main.url(forResource: "pixel-zh-hans", withExtension: "ttf"),
           let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
           let descriptor = descriptors.first,
           let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            if let font = NSFont(name: name, size: 12) { return font }
        }
        return NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    }()

    static func drawBubble(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor(srgbRed: 0.18, green: 0.13, blue: 0.16, alpha: 1)
        ]
        let string = text as NSString
        let size = string.size(withAttributes: attributes)
        let width = min(214, max(56, ceil(size.width) + 20))
        let x = floor((220 - width) / 2)
        let y: CGFloat = 232
        let border = NSColor(srgbRed: 0.18, green: 0.13, blue: 0.16, alpha: 1)
        let paper = NSColor(srgbRed: 1, green: 0.96, blue: 0.90, alpha: 1)
        fill(NSRect(x: x, y: y + 2, width: width, height: 22), border)
        fill(NSRect(x: x + 2, y: y, width: width - 4, height: 26), border)
        fill(NSRect(x: x + 2, y: y + 4, width: width - 4, height: 18), paper)
        fill(NSRect(x: x + 4, y: y + 2, width: width - 8, height: 22), paper)
        fill(NSRect(x: 106, y: y - 4, width: 8, height: 4), border)
        fill(NSRect(x: 108, y: y - 2, width: 4, height: 6), paper)
        string.draw(at: NSPoint(x: floor((220 - size.width) / 2), y: floor(y + (26 - size.height) / 2)),
                    withAttributes: attributes)
    }
}

private func fill(_ rect: NSRect, _ color: NSColor) {
    color.setFill()
    NSBezierPath(rect: rect).fill()
}

private func polygon(_ points: [NSPoint]) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.close()
    return path
}

private func drawPixels(_ rows: [String], x: CGFloat, y: CGFloat, unit: CGFloat, colors: [Character: NSColor]) {
    for (row, line) in rows.reversed().enumerated() {
        for (column, pixel) in line.enumerated() {
            guard let color = colors[pixel] else { continue }
            fill(NSRect(x: x + CGFloat(column) * unit, y: y + CGFloat(row) * unit, width: unit, height: unit), color)
        }
    }
}

/// Composites complete articulated arms over the original head and suit.
private enum Wardrobe {
    static var reading = false
    static var suit: String { UserDefaults.standard.string(forKey: "wardrobe.suit") ?? "original" }
    static var tie: String { UserDefaults.standard.string(forKey: "wardrobe.tie") ?? "original" }
    static var neck: String { UserDefaults.standard.string(forKey: "wardrobe.neck") ?? "none" }
    static var pocket: String { UserDefaults.standard.string(forKey: "wardrobe.pocket") ?? "none" }
    static var coat: String { UserDefaults.standard.string(forKey: "wardrobe.coat") ?? "none" }
    static var gloves: String { UserDefaults.standard.string(forKey: "wardrobe.gloves") ?? "none" }
    static var mask: String { UserDefaults.standard.string(forKey: "wardrobe.mask") ?? "none" }
    static var secretStyle: Bool { UserDefaults.standard.bool(forKey: "wardrobe.secretStyle") }

    static func choice(_ key: String) -> String {
        switch key {
        case "suit": return suit
        case "tie": return tie
        case "neck": return neck
        case "pocket": return pocket
        case "coat": return coat
        case "gloves": return gloves
        case "mask": return mask
        default: return "none"
        }
    }

    static var fabric: NSColor {
        switch suit {
        case "navy": return NSColor(srgbRed: 0.204, green: 0.27, blue: 0.40, alpha: 1)
        case "wine": return NSColor(srgbRed: 0.33, green: 0.185, blue: 0.235, alpha: 1)
        case "green": return NSColor(srgbRed: 0.20, green: 0.28, blue: 0.25, alpha: 1)
        default: return NSColor(srgbRed: 0.204, green: 0.192, blue: 0.208, alpha: 1)
        }
    }

    static func styled(_ name: String, secretStage: Int = 3) -> NSImage {
        let original = NSImage(contentsOf: Bundle.main.url(forResource: name, withExtension: "png")!)!
        guard suit != "original" || tie != "original" || neck != "none" || pocket != "none" || coat != "none" || gloves != "none" || mask != "none" || (secretStyle && secretStage > 0) || (reading && name != "cat-entry") else { return original }
        let result = NSImage(size: original.size)
        result.lockFocus()
        original.draw(in: NSRect(origin: .zero, size: original.size))
        if mask == "jewel", let url = Bundle.main.url(forResource: "\(name)-clothes-jewel-erase", withExtension: "png", subdirectory: "Wardrobe"), let eraser = NSImage(contentsOf: url) {
            eraser.draw(in: NSRect(origin: .zero, size: original.size), from: .zero, operation: .destinationOut, fraction: 1)
        }
        for (part, value) in [("suit", suit), ("tie", tie)] where value != "original" {
            if let url = Bundle.main.url(forResource: "\(name)-\(part)-\(value)", withExtension: "png", subdirectory: "Wardrobe"),
               let layer = NSImage(contentsOf: url) {
                layer.draw(in: NSRect(origin: .zero, size: original.size))
            }
        }
        for value in [neck, pocket] where value != "none" {
            if let url = Bundle.main.url(forResource: "\(name)-accessory-\(value)", withExtension: "png", subdirectory: "Wardrobe"),
               let layer = NSImage(contentsOf: url) {
                layer.draw(in: NSRect(origin: .zero, size: original.size))
            }
        }
        for value in [coat, gloves, mask] where value != "none" {
            if let url = Bundle.main.url(forResource: "\(name)-clothes-\(value)", withExtension: "png", subdirectory: "Wardrobe"), let layer = NSImage(contentsOf: url) {
                layer.draw(in: NSRect(origin: .zero, size: original.size))
            }
        }
        if secretStyle && secretStage > 0 {
            let prefix = name == "cat-entry" ? "entry-" : ""
            for layerName in ["headphones", "glasses", "gold-chain"].prefix(secretStage) {
                if let url = Bundle.main.url(forResource: prefix + layerName, withExtension: "png", subdirectory: "Easter"),
                   let layer = NSImage(contentsOf: url) {
                    layer.draw(in: NSRect(origin: .zero, size: original.size))
                }
            }
        }
        if reading && name != "cat-entry", let url = Bundle.main.url(forResource: "reading-glasses", withExtension: "png"), let layer = NSImage(contentsOf: url) {
            layer.draw(in: NSRect(origin: .zero, size: original.size))
        }
        result.unlockFocus()
        return result
    }
}

private struct PetPose {
    static let spriteRect = NSRect(x: 20, y: 4, width: 180, height: 220)
    private static let restingArm = [
        NSPoint(x: 52, y: 44), NSPoint(x: 80, y: 44),
        NSPoint(x: 80, y: 63), NSPoint(x: 82, y: 79),
        NSPoint(x: 85, y: 94), NSPoint(x: 88, y: 109),
        NSPoint(x: 52, y: 109)
    ]
    private static let jacketEdge = [
        NSPoint(x: 77, y: 45), NSPoint(x: 77, y: 67),
        NSPoint(x: 79, y: 84), NSPoint(x: 83, y: 100),
        NSPoint(x: 87, y: 109), NSPoint(x: 96, y: 109),
        NSPoint(x: 96, y: 45)
    ]
    private static let seam = NSColor(srgbRed: 0.075, green: 0.064, blue: 0.075, alpha: 1)
    private static var fabric: NSColor { Wardrobe.fabric }
    private static var fabricLight: NSColor {
        Wardrobe.suit == "original"
            ? NSColor(srgbRed: 0.25, green: 0.235, blue: 0.25, alpha: 1)
            : (Wardrobe.fabric.blended(withFraction: 0.2, of: .white) ?? Wardrobe.fabric)
    }
    private static let cuff = NSColor(srgbRed: 0.95, green: 0.89, blue: 0.86, alpha: 1)

    private static let closedPaw = [
        "..########..", "..#oooooo#..", ".#ooooooo#..",
        ".#ooooooo##.", "#oooosoooo#.", "#ooosooosoo#",
        "#ooosooosoo#", ".#ooosooo##.", "..########.."
    ]
    private static let openPaw = [
        "...######...", "...#oooo#...", "..##oooo##..",
        ".#oooooooo#.", "#ooospsoooo#", "#oospppsooo#",
        "#oosooooos##", ".#ooosooos#.", ".#o#o#o#o#..",
        "..#.#.#.#..."
    ]
    private static var pawColors: [Character: NSColor] {
      if Wardrobe.gloves != "none" {
        let white = Wardrobe.gloves == "glove-white"
        return ["#": NSColor(white: 0.13, alpha: 1),
                "o": NSColor(white: white ? 0.87 : 0.24, alpha: 1),
                "s": NSColor(white: white ? 0.68 : 0.16, alpha: 1),
                "p": NSColor(white: white ? 0.96 : 0.34, alpha: 1)]
      }
      return [
        "#": NSColor(srgbRed: 0.20, green: 0.12, blue: 0.08, alpha: 1),
        "o": NSColor(srgbRed: 0.83, green: 0.55, blue: 0.31, alpha: 1),
        "s": NSColor(srgbRed: 0.66, green: 0.39, blue: 0.22, alpha: 1),
        "p": NSColor(srgbRed: 0.93, green: 0.60, blue: 0.48, alpha: 1)
      ]
    }

    let cat: NSImage
    let leftAngle: CGFloat
    let rightAngle: CGFloat

    func draw(openLeftPaw: Bool = false, clawReach: CGFloat = 0,
              props: (NSPoint, NSPoint) -> Void = { _, _ in }) {
        let left = Arm(bend: leftAngle, mirrored: false)
        let right = Arm(bend: -rightAngle, mirrored: true)
        drawBody(arms: [left, right])
        left.drawSleeve()
        right.drawSleeve()
        props(left.grip, right.grip)
        left.drawPaw(open: openLeftPaw, claws: clawReach)
        right.drawPaw(open: false, claws: clawReach)
    }

    private func drawBody(arms: [Arm]) {
        let mask = NSBezierPath(rect: Self.spriteRect)
        for arm in arms where arm.isMoving {
            let resting = polygon(Self.restingArm.map(arm.screenPoint))
            mask.append(resting)

            // The sleeve hides this edge of the jacket in the original pose.
            NSGraphicsContext.saveGraphicsState()
            resting.addClip()
            Self.seam.setFill()
            polygon(Self.jacketEdge.map(arm.screenPoint)).fill()
            Self.fabric.setFill()
            polygon(Self.jacketEdge.map { arm.screenPoint(NSPoint(x: $0.x + 2, y: $0.y + 2)) }).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.saveGraphicsState()
        mask.windingRule = .evenOdd
        mask.addClip()
        cat.draw(in: Self.spriteRect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }

    private struct Arm {
        let bend: CGFloat
        let mirrored: Bool
        let shoulder = NSPoint(x: 83, y: 103)

        var isMoving: Bool { abs(bend) >= 0.5 }
        var forearmAngle: CGFloat { max(-164, -3 + 1.10 * bend) }
        var elbow: NSPoint { advance(shoulder, length: 23, angle: -22 + 0.27 * bend) }
        var wrist: NSPoint { advance(elbow, length: 20, angle: forearmAngle) }

        var grip: NSPoint {
            if !isMoving { return screenPoint(NSPoint(x: 71, y: 53)) }
            return screenPoint(advance(wrist, length: 6, angle: forearmAngle))
        }

        func screenPoint(_ point: NSPoint) -> NSPoint {
            mirrored ? NSPoint(x: 220 - point.x, y: point.y) : point
        }

        private func advance(_ start: NSPoint, length: CGFloat, angle: CGFloat) -> NSPoint {
            let radians = angle * .pi / 180
            return NSPoint(x: start.x + length * sin(radians), y: start.y - length * cos(radians))
        }

        private func moveToWrist(angle: CGFloat) {
            let position = screenPoint(wrist)
            let pose = NSAffineTransform()
            pose.translateX(by: position.x, yBy: position.y)
            if mirrored { pose.scaleX(by: -1, yBy: 1) }
            pose.rotate(byDegrees: angle)
            pose.concat()
        }

        func drawSleeve() {
            guard isMoving else { return }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setShouldAntialias(false)
            // One filled bend shares the outline at the elbow, with no cut edge between bones.
            let sleeve = NSBezierPath()
            sleeve.move(to: screenPoint(shoulder))
            sleeve.line(to: screenPoint(elbow))
            sleeve.line(to: screenPoint(wrist))
            sleeve.lineCapStyle = .round
            sleeve.lineJoinStyle = .round
            seam.setStroke()
            sleeve.lineWidth = 17
            sleeve.stroke()
            fabric.setStroke()
            sleeve.lineWidth = 13
            sleeve.stroke()

            let fold = NSBezierPath()
            fold.move(to: screenPoint(advance(shoulder, length: 5, angle: -22 + 0.27 * bend)))
            fold.line(to: screenPoint(advance(elbow, length: 4, angle: 65 + 0.27 * bend)))
            fold.lineWidth = 2
            fabricLight.setStroke()
            fold.stroke()

            moveToWrist(angle: forearmAngle)
            fill(NSRect(x: -8, y: -3, width: 16, height: 8), seam)
            fill(NSRect(x: -6, y: -1, width: 12, height: 4), cuff)
            NSGraphicsContext.restoreGraphicsState()
        }

        func drawPaw(open: Bool, claws: CGFloat) {
            guard isMoving else { return }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setShouldAntialias(false)
            moveToWrist(angle: forearmAngle + (open ? -9 : 0))
            let rows = open ? openPaw : closedPaw
            let unit: CGFloat = 1.35
            drawPixels(rows, x: -8.1, y: -CGFloat(rows.count) * unit + 1, unit: unit, colors: pawColors)
            // The claw tips extend from the fingers and follow the wrist.
            if claws > 0 {
                NSColor(srgbRed: 1, green: 0.92, blue: 0.75, alpha: claws).setFill()
                for offset: CGFloat in [-4, 0, 4] {
                    polygon([
                        NSPoint(x: offset - 1, y: -10),
                        NSPoint(x: offset + 2, y: -10),
                        NSPoint(x: offset + 1, y: -10 - 8 * claws)
                    ]).fill()
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

private struct TrashPerformance {
    static let duration: TimeInterval = 3.8

    let cat: NSImage
    let time: TimeInterval

    private func ease(_ start: Double, _ end: Double) -> CGFloat {
        let progress = min(1, max(0, (time - start) / (end - start)))
        return CGFloat(progress * progress * (3 - 2 * progress))
    }

    func draw() {
        let leftAngle = 104 * (ease(0.8, 1.42) - ease(2.85, 3.52))
        let rightAngle = -102 * (ease(0.20, 0.95) - ease(2.83, 3.5))
        PetPose(cat: cat, leftAngle: leftAngle, rightAngle: rightAngle).draw { leftPaw, rightPaw in
            drawDocument(at: rightPaw, raise: ease(0.20, 0.95))
            drawLighter(at: leftPaw)
        }
        if !Wardrobe.secretStyle { drawGlasses() }
    }

    private func drawGlasses() {
        let on = ease(0, 0.42) - ease(3.3, 3.75)
        let y = 143 + (1 - on) * 14
        let ink = NSColor(white: 0.06, alpha: on)
        fill(NSRect(x: 71, y: y + 15, width: 78, height: 3), ink)
        for x: CGFloat in [73, 121] {
            let lens = [
                NSPoint(x: x, y: y + 17), NSPoint(x: x + 26, y: y + 17),
                NSPoint(x: x + 24, y: y + 6), NSPoint(x: x + 20, y: y + 2),
                NSPoint(x: x + 6, y: y + 2), NSPoint(x: x + 2, y: y + 6)
            ]
            NSColor(white: 0.07, alpha: on * 0.83).setFill()
            polygon(lens).fill()
            let glint = CGFloat(sin(time * 7)) * 3
            fill(NSRect(x: x + 5 + glint, y: y + 12, width: 8, height: 2),
                 NSColor(white: 0.83, alpha: on * 0.52))
        }
    }

    private func drawDocument(at paw: NSPoint, raise: CGFloat) {
        let burn = ease(1.46, 2.75)
        let paper = NSRect(x: -4, y: 0, width: 24, height: 29)
        let transform = NSAffineTransform()
        transform.translateX(by: paw.x, yBy: paw.y + 2)
        transform.rotate(byDegrees: 22 * (1 - raise) - 10)
        NSGraphicsContext.saveGraphicsState()
        transform.concat()

        if burn < 1 {
            let edge = burn * paper.height
            let leftEdge = edge + min(edge, 2)
            let rightEdge = edge - min(edge, 2)
            let shape = polygon([
                NSPoint(x: paper.minX, y: min(leftEdge, paper.maxY)),
                NSPoint(x: 2, y: edge),
                NSPoint(x: 8, y: min(edge + min(edge, 3), paper.maxY)),
                NSPoint(x: 15, y: rightEdge),
                NSPoint(x: paper.maxX, y: edge),
                NSPoint(x: paper.maxX, y: paper.maxY),
                NSPoint(x: paper.minX, y: paper.maxY)
            ])
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            fill(paper, NSColor(red: 0.98, green: 0.94, blue: 0.82, alpha: raise))
            for y: CGFloat in [8, 13, 18, 23] {
                fill(NSRect(x: 0, y: y, width: y == 8 ? 11 : 16, height: 1.4),
                     NSColor(white: 0.34, alpha: raise * 0.58))
            }
            if burn > 0 {
                fill(NSRect(x: paper.minX, y: edge - 2, width: paper.width, height: 5),
                     NSColor(red: 0.28, green: 0.13, blue: 0.08, alpha: 1))
            }
            NSGraphicsContext.restoreGraphicsState()
            let heat = ease(1.46, 1.64) * (1 - ease(2.55, 2.83))
            for index in 0..<3 {
                drawFlame(at: NSPoint(x: CGFloat(index * 8), y: edge - 1),
                          height: heat * (8 + 3 * CGFloat(sin(time * 24 + Double(index)))),
                          phase: Double(index))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        drawEmbers(at: NSPoint(x: paw.x + 7, y: paw.y + 7))
    }

    private func drawLighter(at paw: NSPoint) {
        let visible = ease(0.80, 1.15) - ease(2.65, 3.05)
        let origin = NSPoint(x: paw.x + 2, y: paw.y + 3)
        fill(NSRect(x: origin.x, y: origin.y, width: 7, height: 10),
             NSColor(white: 0.10, alpha: visible))
        fill(NSRect(x: origin.x + 1, y: origin.y + 7, width: 5, height: 3),
             NSColor(white: 0.65, alpha: visible))
        let heat = ease(1.37, 1.48) - ease(1.87, 2.10)
        drawFlame(at: NSPoint(x: origin.x + 3, y: origin.y + 10), height: 9 * heat, phase: 0)
    }

    private func drawFlame(at base: NSPoint, height: CGFloat, phase: Double) {
        guard height > 0 else { return }
        let flicker = CGFloat(sin(time * 26 + phase))
        for (scale, color): (CGFloat, NSColor) in [
            (1, .systemOrange), (0.57, NSColor(red: 1, green: 0.87, blue: 0.32, alpha: 1))
        ] {
            let h = height * scale
            color.setFill()
            polygon([
                NSPoint(x: base.x - h * 0.29, y: base.y),
                NSPoint(x: base.x - h * 0.35, y: base.y + h * 0.40),
                NSPoint(x: base.x + h * 0.12 * flicker, y: base.y + h),
                NSPoint(x: base.x + h * 0.34, y: base.y + h * 0.42),
                NSPoint(x: base.x + h * 0.22, y: base.y)
            ]).fill()
        }
    }

    private func drawEmbers(at origin: NSPoint) {
        for index in 0..<22 {
            let start = 1.49 + Double(index) * 0.057
            let age = CGFloat(time - start)
            guard age >= 0, age < 0.85 else { continue }
            let drift = CGFloat(sin(Double(index) * 2.4))
            let x = origin.x + drift * (5 + age * 20)
            let y = origin.y + 20 * CGFloat(min(1, (start - 1.49) / 1.25)) + age * (16 + 7 * drift)
            let size = (index.isMultiple(of: 3) ? 3.0 : 2.0) * (1 - age * 0.72)
            fill(NSRect(x: x, y: y, width: size, height: size),
                 NSColor(red: 1, green: 0.58 + drift * 0.14, blue: 0.17, alpha: 1 - age / 0.85))
        }
    }
}

private enum Interaction {
    case wave, flower, tear, monster, hug

    static let frames = 10
    static let frameDuration: TimeInterval = 0.1

    static func random() -> Self {
        if Int.random(in: 0..<25) == 0 { return .monster }
        return [Self.wave, .flower, .tear].randomElement()!
    }

    var dialogue: String {
        switch self {
        case .wave: return "Hi，I'm Yecatz"
        case .flower: return "Enjoy Ur Day :)"
        case .tear: return "I hate being bi-polar..."
        case .monster: return "I'm motfuc Monster！"
        case .hug: return "♡ 给你一个抱抱 ♡"
        }
    }

    func draw(cat: NSImage, frame: Int) {
        switch self {
        case .wave:
            let angles: [CGFloat] = [-25, -80, -125, -146, -123, -146, -146, -146, -85, -30]
            PetPose(cat: cat, leftAngle: angles[frame], rightAngle: 0).draw(openLeftPaw: true)
        case .flower:
            let reach: [CGFloat] = [0.12, 0.38, 0.72, 1, 1, 1, 1, 0.78, 0.49, 0.21]
            let amount = reach[frame]
            PetPose(cat: cat, leftAngle: 0, rightAngle: -100 * amount).draw { _, paw in
                drawRose(at: paw, reach: amount)
            }
        case .tear:
            cat.draw(in: PetPose.spriteRect, from: .zero, operation: .sourceOver, fraction: 1)
            drawTear(frame: frame)
        case .monster:
            drawMonster(cat: cat, frame: frame)
        case .hug:
            cat.draw(in: PetPose.spriteRect, from: .zero, operation: .sourceOver, fraction: 1)
            drawHeartsAndBubbles(frame: frame)
        }
    }

    private func drawRose(at paw: NSPoint, reach: CGFloat) {
        let unit = 1.25 + reach
        let x = paw.x.rounded()
        let y = paw.y.rounded()
        let green = NSColor(srgbRed: 0.20, green: 0.53, blue: 0.27, alpha: reach)
        fill(NSRect(x: x, y: y - 3 * unit, width: unit, height: 11 * unit), green)
        fill(NSRect(x: x - 3 * unit, y: y + 2 * unit, width: 3 * unit, height: 2 * unit), green)
        fill(NSRect(x: x + unit, y: y + 4 * unit, width: 3 * unit, height: 2 * unit), green)
        let petals = [
            ".rr.rr.",
            "rRrrRRr",
            "rRRRRRr",
            ".rRRRr.",
            "..rrr.."
        ]
        drawPixels(petals, x: x - 3 * unit, y: y + 7 * unit, unit: unit, colors: [
            "r": NSColor(srgbRed: 0.62, green: 0.04, blue: 0.18, alpha: reach),
            "R": NSColor(srgbRed: 1, green: 0.22, blue: 0.32, alpha: reach)
        ])
    }

    private func drawTear(frame: Int) {
        // Yecatz's right eye is on the viewer's left.
        let unit = min(3.0, 1.7 + CGFloat(frame) * 0.48)
        let x = CGFloat(87 - min(8, frame)) - 2.5 * unit
        let y = CGFloat(148 - frame * (frame + 3) / 2) - 7 * unit
        let alpha = frame < 8 ? 1 : (10 - CGFloat(frame)) * 0.33
        drawPixels(["..d..", "..db.", ".dbb.", ".dBbd", "dBBbd", "dbbbd", ".ddd."],
                   x: x, y: y, unit: unit, colors: [
            "d": NSColor(srgbRed: 0.05, green: 0.36, blue: 0.77, alpha: alpha),
            "b": NSColor(srgbRed: 0.18, green: 0.72, blue: 1, alpha: alpha),
            "B": NSColor(srgbRed: 0.77, green: 0.97, blue: 1, alpha: alpha)
        ])
        if frame >= 3 {
            let streakY = CGFloat(147 - min(frame, 8) * 3)
            fill(NSRect(x: 85, y: streakY, width: 2, height: 145 - streakY),
                 NSColor(srgbRed: 0.38, green: 0.78, blue: 1, alpha: alpha * 0.63))
        }
    }

    private func drawMonster(cat: NSImage, frame: Int) {
        let lunges: [CGFloat] = [0.04, 0.08, 0.16, 0.29, 0.63, 1, 0.78, 0.58, 0.30, 0.08]
        let reach = lunges[frame]
        let claws: [CGFloat] = [0, 0.20, 0.45, 0.80, 1, 1, 1, 0.80, 0.50, 0.15]
        NSGraphicsContext.saveGraphicsState()
        let lunge = NSAffineTransform()
        lunge.translateX(by: 110 + (frame.isMultiple(of: 2) ? 1 : -1) * 5 * reach, yBy: 13 + 4 * reach)
        lunge.scale(by: 1 + 0.13 * reach)
        lunge.translateX(by: -110, yBy: -13)
        lunge.concat()
        let angle = 129 * claws[frame]
        PetPose(cat: cat, leftAngle: -angle, rightAngle: angle).draw(clawReach: claws[frame])

        let heat = min(1, CGFloat(frame + 1) * 0.32) * (1 - CGFloat(max(0, frame - 7)) * 0.25)
        let red = NSColor(srgbRed: 0.69, green: 0.02, blue: 0.09, alpha: heat)
        fill(NSRect(x: 71, y: 158, width: 78, height: 3), red)
        for x: CGFloat in [73, 121] {
            red.setFill()
            polygon([
                NSPoint(x: x, y: 160), NSPoint(x: x + 26, y: 160),
                NSPoint(x: x + 23, y: 149), NSPoint(x: x + 19, y: 146),
                NSPoint(x: x + 6, y: 146), NSPoint(x: x + 3, y: 149)
            ]).fill()
            let flameRows = frame.isMultiple(of: 2)
                ? ["..r....", "..r.r..", ".rRrr..", "rrRRrr.", ".rRRRr."]
                : ["....r..", ".r..r..", ".rrRr..", "rrRRRr.", ".rRRrr."]
            drawPixels(flameRows, x: x + 4, y: 153, unit: 2.35 + reach, colors: [
                "r": NSColor(srgbRed: 1, green: 0.17, blue: 0.11, alpha: heat),
                "R": NSColor(srgbRed: 1, green: 0.72, blue: 0.23, alpha: heat)
            ])
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawHeartsAndBubbles(frame: Int) {
        let heart = [".pp.pp.", "pPPpPPp", "pPPPPPp", ".pPPPp.", "..pPp..", "...p..."]
        let bubble = [".bbb.", "bh..b", "b...b", "b...b", ".bbb."]
        let offsets = [42, 51, 48, 55, 65, 34, 53, 70]
        let heights = [68, 82, 110, 56, 71, 98, 62, 100]
        for i in 0..<8 {
            let age = frame - i / 2
            guard age >= 0 else { continue }
            let side: CGFloat = i.isMultiple(of: 2) ? -1 : 1
            let x = 110 + side * CGFloat(offsets[i] + age * (2 + i % 3))
            let y = CGFloat(heights[i] + age * (8 + i % 4))
            let alpha = min(1, CGFloat(age + 1) * 0.48) * (1 - CGFloat(max(0, age - 5)) * 0.21)
            let isHeart = i < 4 || i == 6
            drawPixels(isHeart ? heart : bubble, x: x - 6, y: y, unit: i < 2 ? 2.4 : 1.8, colors: [
                "p": NSColor(srgbRed: 0.82, green: 0.20, blue: 0.49, alpha: alpha),
                "P": NSColor(srgbRed: 1, green: 0.51, blue: 0.71, alpha: alpha),
                "b": NSColor(srgbRed: 1, green: 0.71, blue: 0.86, alpha: alpha * 0.86),
                "h": NSColor(srgbRed: 1, green: 0.93, blue: 0.98, alpha: alpha)
            ])
        }
    }

}

final class PetView: NSView {
    var cat = Wardrobe.styled("cat")
    var blinkCat = Wardrobe.styled("cat-blink")
    var entryCat = Wardrobe.styled("cat-entry")
    private lazy var jewelSparks: [NSImage?] = (0..<4).map { index in
        Bundle.main.url(forResource: "cat-clothes-jewel-spark-\(index)", withExtension: "png", subdirectory: "Wardrobe").flatMap(NSImage.init(contentsOf:))
    }
    private lazy var entryJewelSparks: [NSImage?] = (0..<4).map { index in
        Bundle.main.url(forResource: "cat-entry-clothes-jewel-spark-\(index)", withExtension: "png", subdirectory: "Wardrobe").flatMap(NSImage.init(contentsOf:))
    }

    private var secretStart: TimeInterval?
    private var secretStage = 3

    func equipSecretStyle() {
        UserDefaults.standard.set(true, forKey: "wardrobe.secretStyle")
        secretStart = ProcessInfo.processInfo.systemUptime
        secretStage = 0
        cancelInteraction()
        refreshWardrobe()
    }

    func refreshWardrobe() {
        cat = Wardrobe.styled("cat", secretStage: secretStage)
        blinkCat = Wardrobe.styled("cat-blink", secretStage: secretStage)
        entryCat = Wardrobe.styled("cat-entry", secretStage: secretStage)
        needsDisplay = true
    }
    private var trashAnimationStart: TimeInterval?
    private var trashAnimationTimer: Timer?
    private var clickAnimation: (action: Interaction, start: TimeInterval)?
    private var pendingSingleClick: Timer?
    var entryFrame: Int?
    var entryLift: CGFloat = 0
    var message = "Hi，I'm Yecatz"
    var transferState: TransferSession.State = .idle {
        didSet {
            if transferState != .idle {
                cancelInteraction()
                messageUntil = .distantPast
            }
            needsDisplay = true
        }
    }
    var tick = 0
    var nextBlink = Date().addingTimeInterval(Double.random(in: 2...5))
    var blinkUntil: Date = .distantPast
    func animate() {
        tick += 1
        if let start = secretStart {
            let stage = min(3, Int((ProcessInfo.processInfo.systemUptime - start) / 0.30) + 1)
            if stage != secretStage {
                secretStage = stage
                refreshWardrobe()
            }
            if stage == 3 { secretStart = nil }
        }
        let now = Date()
        if now >= nextBlink {
            blinkUntil = now.addingTimeInterval(0.18)
            nextBlink = now.addingTimeInterval(Double.random(in: 3...7))
        }
        if trashAnimationStart == nil { needsDisplay = true }
    }
    var messageUntil: Date = .distantPast
    var dragOffset: NSPoint?
    var moved = false
    private var chatButtonPressed = false
    private var hovering = false
    private var hoverTracking: NSTrackingArea?
    static let chatButtonRect = NSRect(x: 186, y: 234, width: 26, height: 17)
    static let readingButtonRect = NSRect(x: 154, y: 234, width: 26, height: 17)
    private static let transferBoxRect = NSRect(x: 82, y: 58, width: 56, height: 38)
    override var isOpaque: Bool { false }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { super.init(coder: coder); registerForDraggedTypes([.fileURL]) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        hoverTracking = area
    }
    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if transferState != .idle {
            guard transferState == .connected,
                  let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
                  urls.count == 1 else { return [] }
            return .copy
        }
        if Wardrobe.reading {
            guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], urls.count == 1 else { return [] }
            return .copy
        }
        return sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .delete : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        if transferState != .idle {
            guard transferState == .connected, urls.count == 1,
                  Self.transferBoxRect.contains(convert(sender.draggingLocation, from: nil)) else { return false }
            (NSApp.delegate as? AppDelegate)?.sendTransferFile(urls[0])
            return true
        }
        if Wardrobe.reading {
            guard urls.count == 1 else { return false }
            (NSApp.delegate as? AppDelegate)?.summarizeFile(urls[0])
            return true
        }
        var failures = 0
        var successes = 0
        for url in urls {
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil); successes += 1 }
            catch { failures += 1 }
        }
        if successes > 0 {
            (NSApp.delegate as? AppDelegate)?.cancelEntry()
            cancelInteraction()
            startTrashAnimation()
        }
        message = failures == 0 ? "已放入废纸篓" : "已移除 \(successes)，失败 \(failures)"
        messageUntil = Date().addingTimeInterval(4)
        needsDisplay = true
        return successes > 0
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if transferState != .idle {
            guard transferState == .connected,
                  Self.transferBoxRect.contains(convert(sender.draggingLocation, from: nil)) else { return [] }
            return draggingEntered(sender)
        }
        return draggingEntered(sender)
    }

    private func startTrashAnimation() {
        trashAnimationStart = ProcessInfo.processInfo.systemUptime
        trashAnimationTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, let start = self.trashAnimationStart else {
                    timer.invalidate()
                    return
                }
                if ProcessInfo.processInfo.systemUptime - start >= TrashPerformance.duration {
                    self.trashAnimationStart = nil
                    self.trashAnimationTimer = nil
                    timer.invalidate()
                }
                self.needsDisplay = true
            }
        }
        trashAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        let uptime = ProcessInfo.processInfo.systemUptime
        let breath = CGFloat(sin(Double(tick) * 0.10))
        let height: CGFloat = 220 + breath * 2
        let width: CGFloat = 180 + breath * 0.8
        if transferState == .connected {
            PetPose(cat: cat, leftAngle: 25, rightAngle: -25).draw { _, _ in
                let outline = NSColor(srgbRed: 0.26, green: 0.16, blue: 0.10, alpha: 1)
                let cardboard = NSColor(srgbRed: 0.72, green: 0.49, blue: 0.30, alpha: 1)
                let light = NSColor(srgbRed: 0.84, green: 0.64, blue: 0.42, alpha: 1)
                fill(NSRect(x: 82, y: 58, width: 56, height: 38), outline)
                fill(NSRect(x: 84, y: 60, width: 52, height: 34), cardboard)
                fill(NSRect(x: 84, y: 87, width: 52, height: 7), light)
                fill(NSRect(x: 106, y: 60, width: 8, height: 34), light)
                fill(NSRect(x: 105, y: 87, width: 10, height: 7), outline.withAlphaComponent(0.38))
                fill(NSRect(x: 88, y: 64, width: 8, height: 2), outline.withAlphaComponent(0.45))
            }
        } else if let start = trashAnimationStart {
            TrashPerformance(cat: cat, time: uptime - start).draw()
        } else if let click = clickAnimation,
                  uptime - click.start < Double(Interaction.frames) * Interaction.frameDuration {
            let frame = Int((uptime - click.start) / Interaction.frameDuration)
            click.action.draw(cat: cat, frame: min(Interaction.frames - 1, frame))
        } else if let entryFrame = entryFrame {
            let cellWidth = entryCat.size.width / 4
            let source = NSRect(x: CGFloat(entryFrame) * cellWidth, y: 0, width: cellWidth, height: entryCat.size.height)
            let target = NSRect(x: 20, y: 2 + entryLift, width: 180, height: 220)
            entryCat.draw(in: target, from: source, operation: .sourceOver, fraction: 1)
        } else {
            let image = Date() < blinkUntil ? blinkCat : cat
            image.draw(in: NSRect(x: (220 - width) / 2, y: 4, width: width, height: height), from: .zero, operation: .sourceOver, fraction: 1)
        }
        if Wardrobe.mask == "jewel" {
            let sparkleFrame = (tick / 4) % 4
            if let frame = entryFrame, transferState == .idle, trashAnimationStart == nil, !interactionActive,
               let sparkle = entryJewelSparks[sparkleFrame] {
                let cellWidth = sparkle.size.width / 4
                sparkle.draw(in: NSRect(x: 20, y: 2 + entryLift, width: 180, height: 220),
                             from: NSRect(x: CGFloat(frame) * cellWidth, y: 0, width: cellWidth, height: sparkle.size.height),
                             operation: .sourceOver, fraction: 1)
            } else if let sparkle = jewelSparks[sparkleFrame] {
                let fixed = transferState != .idle || trashAnimationStart != nil || interactionActive
                let target = fixed ? PetPose.spriteRect : NSRect(x: (220 - width) / 2, y: 4, width: width, height: height)
                if let click = clickAnimation, click.action == .monster,
                   uptime - click.start < Double(Interaction.frames) * Interaction.frameDuration {
                    let frame = min(Interaction.frames - 1, Int((uptime - click.start) / Interaction.frameDuration))
                    let reach: [CGFloat] = [0.04, 0.08, 0.16, 0.29, 0.63, 1, 0.78, 0.58, 0.30, 0.08]
                    NSGraphicsContext.saveGraphicsState()
                    let transform = NSAffineTransform()
                    transform.translateX(by: 110 + (frame.isMultiple(of: 2) ? 1 : -1) * 5 * reach[frame], yBy: 13 + 4 * reach[frame])
                    transform.scale(by: 1 + 0.13 * reach[frame]); transform.translateX(by: -110, yBy: -13); transform.concat()
                    sparkle.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
                    NSGraphicsContext.restoreGraphicsState()
                } else {
                    sparkle.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
                }
            }
        }
        if Date() < messageUntil {
            PixelType.drawBubble(message)
        } else if showsChatButton {
            drawChatButton()
            drawReadingButton()
        }
    }

    private var interactionActive: Bool {
        guard let click = clickAnimation else { return false }
        return ProcessInfo.processInfo.systemUptime - click.start
            < Double(Interaction.frames) * Interaction.frameDuration
    }

    private var showsChatButton: Bool {
        transferState == .idle && hovering && Date() >= messageUntil && !interactionActive && trashAnimationStart == nil
    }

    func showHourlyThought(_ text: String) -> Bool {
        guard transferState == .idle, !interactionActive, trashAnimationStart == nil, entryFrame == nil,
              dragOffset == nil, pendingSingleClick == nil, Date() >= messageUntil else { return false }
        message = text
        messageUntil = Date().addingTimeInterval(9)
        needsDisplay = true
        return true
    }

    private func drawChatButton() {
        let rect = Self.chatButtonRect
        let ink = NSColor(srgbRed: 0.18, green: 0.14, blue: 0.16, alpha: 1)
        let paper = NSColor(srgbRed: 0.99, green: 0.97, blue: 0.92, alpha: 0.94)
        let pill = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        paper.setFill()
        pill.fill()
        ink.withAlphaComponent(0.72).setStroke()
        pill.lineWidth = 1
        pill.stroke()
        let dot: CGFloat = 3
        for index in 0..<3 {
            let centerX = rect.midX + CGFloat(index - 1) * 6
            fill(NSRect(x: centerX - dot / 2, y: rect.midY - dot / 2 + 0.5, width: dot, height: dot), ink)
        }
    }

    private func drawReadingButton() {
        let rect = Self.readingButtonRect
        let ink = NSColor(srgbRed: 0.18, green: 0.14, blue: 0.16, alpha: 1)
        (Wardrobe.reading ? NSColor(srgbRed: 0.92, green: 0.79, blue: 0.60, alpha: 1) : NSColor(srgbRed: 0.99, green: 0.97, blue: 0.92, alpha: 0.94)).setFill()
        let pill = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        pill.fill(); ink.withAlphaComponent(0.72).setStroke(); pill.lineWidth = 1; pill.stroke()
        for x: CGFloat in [rect.minX + 4, rect.minX + 15] {
            let lens = NSBezierPath(rect: NSRect(x: x, y: rect.minY + 5, width: 7, height: 6))
            ink.setStroke(); lens.lineWidth = 1; lens.stroke()
        }
        fill(NSRect(x: rect.minX + 11, y: rect.minY + 8, width: 4, height: 1), ink)
    }

    func cancelInteraction() {
        pendingSingleClick?.invalidate()
        pendingSingleClick = nil
        clickAnimation = nil
    }

    private func play(_ action: Interaction) {
        guard trashAnimationStart == nil else { return }
        clickAnimation = (action, ProcessInfo.processInfo.systemUptime)
        message = action.dialogue
        messageUntil = Date().addingTimeInterval(3)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if transferState != .idle {
            (NSApp.delegate as? AppDelegate)?.cancelEntry()
            dragOffset = event.locationInWindow
            moved = false
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if Self.readingButtonRect.contains(point), showsChatButton {
            chatButtonPressed = true
            (NSApp.delegate as? AppDelegate)?.cancelEntry()
            Wardrobe.reading.toggle()
            refreshWardrobe()
            return
        }
        if Self.chatButtonRect.contains(point), showsChatButton {
            chatButtonPressed = true
            (NSApp.delegate as? AppDelegate)?.showChat()
            return
        }
        (NSApp.delegate as? AppDelegate)?.cancelEntry()
        if event.clickCount > 1 {
            pendingSingleClick?.invalidate()
            pendingSingleClick = nil
        }
        dragOffset = event.locationInWindow
        moved = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window = window, let offset = dragOffset else { return }
        let mouse = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: mouse.x - offset.x, y: mouse.y - offset.y))
        moved = true
        (NSApp.delegate as? AppDelegate)?.chatMoved()
    }
    override func mouseUp(with event: NSEvent) {
        defer { dragOffset = nil }
        if chatButtonPressed {
            chatButtonPressed = false
            return
        }
        guard transferState == .idle, !moved, trashAnimationStart == nil else { return }
        pendingSingleClick?.invalidate()
        pendingSingleClick = nil
        if event.clickCount == 1 && event.modifierFlags.contains(.option) {
            play(.monster)
        } else if event.clickCount == 2 {
            play(.hug)
        } else if event.clickCount == 1 {
            let timer = Timer(timeInterval: NSEvent.doubleClickInterval, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.pendingSingleClick = nil
                    self?.play(.random())
                }
            }
            pendingSingleClick = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        guard transferState == .idle else { return }
        (NSApp.delegate as? AppDelegate)?.showChat()
    }

    func transferNotice(_ text: String) {
        message = String(text.prefix(19))
        messageUntil = Date().addingTimeInterval(5)
        needsDisplay = true
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var status: NSStatusItem!
    var timer: Timer?
    private var hourlyTimer: Timer?
    private var hourlyThoughtPending = false
    private var thoughtIndex = 0
    private let thoughts = [
        "慢一点，也是在往前。",
        "有些路，走着才看得清。",
        "给想法留一点空白。",
        "今天的事，不必全带到明天。",
        "允许答案晚一点来。",
        "日子不用每页都写满。",
        "先看脚下，再看远方。",
        "疲惫时，先把自己照顾好。",
        "耐心也可以是一种决定。",
        "热闹过后，安静也很好。",
        "你可以边走边改变主意。",
        "偶尔绕路，也会看见风景。"
    ].shuffled()
    var pet: PetView!
    var chat: ChatController!
    private let transfer = TransferSession()
    private var updateTask: Task<Void, Never>?
    var entryStart: Date?
    var entryFrom: CGFloat = 0
    var entryTo: CGFloat = 0
    let walkDuration: TimeInterval = 2.0
    let stepFrames = [0, 2, 1, 2]
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        window = NSWindow(contentRect: NSRect(x: screen.maxX - 240, y: screen.minY + 15, width: 220, height: 265), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        pet = PetView(frame: NSRect(x: 0, y: 0, width: 220, height: 265))
        window.contentView = pet
        chat = ChatController()
        chat.attach(to: window)
        chat.onFavoriteOutfit = { [weak self] in
            guard let self, self.pet.transferState == .idle else { return }
            self.cancelEntry()
            self.pet.equipSecretStyle()
        }
        configureTransfer()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.toolTip = "Yecatz"
        status.button?.setAccessibilityLabel("Yecatz")
        if let tie = NSImage(named: "tie-status") {
            tie.isTemplate = true
            tie.size = NSSize(width: 18, height: 18)
            status.button?.image = tie
            status.button?.imagePosition = .imageOnly
        } else {
            status.button?.title = "Yecatz"
        }
        let menu = NSMenu()
        menu.addItem(menuItem("和 Yecatz 聊天", action: #selector(showChat)))
        menu.addItem(menuItem("聊天设置…", action: #selector(openChatSettings)))
        menu.addItem(menuItem("打开记忆文件", action: #selector(openMemoryFile)))
        menu.addItem(menuItem("打开音乐文件夹", action: #selector(openMusicFolder)))
        menu.addItem(menuItem("生成连接码…", action: #selector(hostTransfer)))
        menu.addItem(menuItem("输入连接码…", action: #selector(joinTransfer)))
        menu.addItem(menuItem("断开传输连接", action: #selector(disconnectTransfer)))
        let wardrobeItem = NSMenuItem(title: "衣橱", action: nil, keyEquivalent: "")
        let wardrobeMenu = NSMenu(title: "衣橱")
        for (title, key, choices) in [
            ("西装颜色", "suit", [("原色", "original"), ("深海蓝", "navy"), ("酒红", "wine"), ("墨绿", "green")]),
            ("领带颜色", "tie", [("原色", "original"), ("暗红", "red"), ("蓝色", "blue"), ("金色", "gold")]),
            ("颈部配饰", "neck", [("不佩戴", "none"), ("酒红围巾", "scarf-wine"), ("奶油围巾", "scarf-cream"), ("黑色领结", "bow-black"), ("暗红领结", "bow-red")]),
            ("口袋巾", "pocket", [("不佩戴", "none"), ("象牙白", "pocket-white"), ("暗红", "pocket-red")]),
            ("礼服", "coat", [("不佩戴", "none"), ("礼服", "formal"), ("燕尾服", "tails")]),
            ("手套", "gloves", [("不佩戴", "none"), ("白色", "glove-white"), ("黑色", "glove-black")]),
            ("口罩", "mask", [("不佩戴", "none"), ("黑色", "walker"), ("镶钻全脸面罩", "jewel")])
        ] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            for (label, value) in choices {
                let choice = menuItem(label, action: #selector(chooseWardrobe(_:)))
                choice.representedObject = ["key": key, "value": value]
                choice.state = Wardrobe.choice(key) == value ? .on : .off
                submenu.addItem(choice)
            }
            item.submenu = submenu
            wardrobeMenu.addItem(item)
        }
        wardrobeItem.submenu = wardrobeMenu
        menu.addItem(wardrobeItem)
        menu.addItem(menuItem("检查更新…", action: #selector(checkForUpdates)))
        menu.addItem(.separator())
        let hourlyItem = menuItem("每小时一句", action: #selector(toggleHourlyThoughts(_:)))
        hourlyItem.state = hourlyThoughtsEnabled ? .on : .off
        menu.addItem(hourlyItem)
        menu.addItem(menuItem("显示 Yecatz", action: #selector(showPet)))
        menu.addItem(menuItem("隐藏 Yecatz", action: #selector(hidePet)))
        menu.addItem(menuItem("再走进来一次", action: #selector(replayEntry)))
        menu.addItem(.separator())
        menu.addItem(menuItem("退出 Yecatz", action: #selector(quit), key: "q"))
        status.menu = menu
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        if let timer = timer { RunLoop.main.add(timer, forMode: .common) }
        if hourlyThoughtsEnabled { startHourlyThoughts() }
        replayEntry()
        checkUpdates(manual: false)
    }
    private func menuItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.attributedTitle = NSAttributedString(string: title, attributes: [.font: PixelType.font])
        return item
    }

    @objc private func chooseWardrobe(_ item: NSMenuItem) {
        guard let info = item.representedObject as? [String: String],
              let key = info["key"], let value = info["value"],
              ["suit", "tie", "neck", "pocket", "coat", "gloves", "mask"].contains(key) else { return }
        UserDefaults.standard.set(value, forKey: "wardrobe.\(key)")
        UserDefaults.standard.set(false, forKey: "wardrobe.secretStyle")
        item.menu?.items.forEach { $0.state = $0 === item ? .on : .off }
        pet.refreshWardrobe()
    }

    func advance() {
        pet.animate()
        if hourlyThoughtPending, window.isVisible, chat.canShowHourlyThought,
           pet.showHourlyThought(thoughts[thoughtIndex]) {
            hourlyThoughtPending = false
            thoughtIndex = (thoughtIndex + 1) % thoughts.count
        }
        if let start = entryStart {
            let elapsed = max(0, Date().timeIntervalSince(start))
            let progress = min(1, elapsed / walkDuration)
            let distance = progress * (1.35 - 0.35 * progress)
            window.setFrameOrigin(NSPoint(x: entryFrom + (entryTo - entryFrom) * distance, y: window.frame.origin.y))
            chat.parentMoved()
            if elapsed < walkDuration {
                let step = Int(elapsed / 0.12) % stepFrames.count
                pet.entryFrame = stepFrames[step]
                pet.entryLift = step.isMultiple(of: 2) ? 0 : 2
            } else if elapsed < walkDuration + 0.18 {
                pet.entryFrame = 2
                pet.entryLift = 0
            } else if elapsed < walkDuration + 0.38 {
                pet.entryFrame = 3
                pet.entryLift = 0
            } else {
                cancelEntry()
            }
        }
    }
    func cancelEntry() {
        entryStart = nil
        pet.entryFrame = nil
        pet.entryLift = 0
        pet.needsDisplay = true
    }
    @objc func replayEntry() {
        chat.hideAll()
        pet.cancelInteraction()
        let frame = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        entryFrom = frame.maxX
        entryTo = max(frame.minX, frame.maxX - window.frame.width - 20)
        window.setFrameOrigin(NSPoint(x: entryFrom, y: frame.minY + 15))
        chat.parentMoved()
        pet.entryFrame = 0
        pet.entryLift = 0
        pet.needsDisplay = true
        entryStart = Date()
        window.orderFrontRegardless()
    }
    @objc func showPet() { window.orderFrontRegardless() }
    @objc func showChat() { if pet.transferState == .idle { chat.showComposer() } }
    func summarizeFile(_ url: URL) { chat.summarizeFile(url) }
    @objc func openChatSettings() { chat.showSettings() }
    @objc func openMemoryFile() { chat.openMemoryFile() }
    @objc func openMusicFolder() { chat.openMusicFolder() }
    func sendTransferFile(_ url: URL) { transfer.sendFile(url) }

    private func configureTransfer() {
        transfer.onState = { [weak self] state in
            guard let self else { return }
            if state != .idle {
                self.cancelEntry()
                self.chat.hideAll()
            }
            self.pet.transferState = state
        }
        transfer.onMessage = { [weak self] in self?.pet.transferNotice($0) }
        transfer.onCode = { code in
            let field = NSTextField(string: code)
            field.isEditable = false
            field.isSelectable = true
            field.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            field.frame = NSRect(x: 0, y: 0, width: 370, height: 26)
            let alert = NSAlert()
            alert.messageText = "Yecatz 连接码"
            alert.informativeText = "将八位数字私下发给对方，5 分钟内有效。短码不适合传输敏感文件。"
            alert.accessoryView = field
            alert.addButton(withTitle: "复制连接码")
            alert.addButton(withTitle: "关闭")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            }
        }
        transfer.confirmPair = { name, finish in
            let alert = NSAlert()
            alert.messageText = "有一只 Yecatz 想连接"
            alert.informativeText = "设备：\(name)\n请确认是你分享连接码的对象。"
            alert.addButton(withTitle: "连接")
            alert.addButton(withTitle: "拒绝")
            NSApp.activate(ignoringOtherApps: true)
            finish(alert.runModal() == .alertFirstButtonReturn)
        }
        transfer.chooseDestination = { name, size, finish in
            let panel = NSSavePanel()
            panel.title = "接收文件"
            panel.message = "对方向你发送文件（\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))）。选择保存位置后开始接收。"
            panel.nameFieldStringValue = name
            panel.canCreateDirectories = true
            NSApp.activate(ignoringOtherApps: true)
            finish(panel.runModal() == .OK ? panel.url : nil)
        }
    }

    @objc private func hostTransfer() { transfer.startHosting() }

    @objc private func joinTransfer() {
        let field = NSTextField(string: "")
        field.placeholderString = "输入八位数字"
        field.frame = NSRect(x: 0, y: 0, width: 370, height: 26)
        let alert = NSAlert()
        alert.messageText = "连接另一只 Yecatz"
        alert.informativeText = "输入对方生成的八位数字，双方需要处在可以互访的同一局域网。"
        alert.accessoryView = field
        alert.addButton(withTitle: "连接")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let code = TransferCode(field.stringValue) else {
            pet.transferNotice("连接码不正确。")
            return
        }
        transfer.connect(code)
    }

    @objc private func disconnectTransfer() { transfer.disconnect() }
    @objc private func checkForUpdates() { checkUpdates(manual: true) }

    private func checkUpdates(manual: Bool) {
        guard updateTask == nil,
              let owner = Bundle.main.object(forInfoDictionaryKey: "YecatzUpdateOwner") as? String,
              let repository = Bundle.main.object(forInfoDictionaryKey: "YecatzUpdateRepository") as? String,
              let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return }
        let checker = GitHubUpdateChecker(owner: owner, repository: repository)
        updateTask = Task { [weak self] in
            defer { self?.updateTask = nil }
            do {
                let result = try await checker.check(current: current)
                let alert = NSAlert()
                switch result {
                case .update(let version, let url):
                    alert.messageText = "Yecatz 有新版本"
                    alert.informativeText = "发现 \(version)，当前版本为 \(current)。前往 GitHub 查看更新并下载。"
                    alert.addButton(withTitle: "前往下载")
                    alert.addButton(withTitle: "稍后")
                    if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
                case .current:
                    guard manual else { return }
                    alert.messageText = "已经是最新版本"
                    alert.informativeText = "当前版本：\(current)"
                    alert.addButton(withTitle: "好")
                    alert.runModal()
                }
            } catch {
                guard manual else { return }
                let alert = NSAlert()
                alert.messageText = "暂时无法检查更新"
                alert.informativeText = "请检查网络，并确认 GitHub 仓库是公开的且已发布正式版本。"
                alert.addButton(withTitle: "好")
                alert.runModal()
            }
        }
    }
    private var hourlyThoughtsEnabled: Bool { !UserDefaults.standard.bool(forKey: "hourlyThoughts.disabled") }

    private func startHourlyThoughts() {
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.hourlyThoughtPending = true }
        }
        timer.tolerance = 3
        hourlyTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func toggleHourlyThoughts(_ item: NSMenuItem) {
        let enabled = !hourlyThoughtsEnabled
        UserDefaults.standard.set(!enabled, forKey: "hourlyThoughts.disabled")
        item.state = enabled ? .on : .off
        if enabled {
            startHourlyThoughts()
        } else {
            hourlyTimer?.invalidate()
            hourlyTimer = nil
            hourlyThoughtPending = false
        }
    }
    @objc func hidePet() {
        chat.hideAll()
        window.orderOut(nil)
    }
    func applicationWillTerminate(_ notification: Notification) { transfer.shutdown() }
    @objc func quit() { NSApp.terminate(nil) }
    func chatMoved() { chat.parentMoved() }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
