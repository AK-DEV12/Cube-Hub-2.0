import AppKit
import Combine
import CubeHubCore
import SwiftUI

/// Cubby: a little stickerless cube who peeks out from behind the widget. At
/// rest its face is the front of the scrambled cube; it twists its layers during
/// a solve and is solved green when the timer stops.

enum CubeColor: CaseIterable {
    case white, yellow, red, orange, blue, green

    /// Standard colours with white on top and green in front.
    init(face: Face) {
        switch face {
        case .up: self = .white
        case .down: self = .yellow
        case .front: self = .green
        case .back: self = .blue
        case .right: self = .red
        case .left: self = .orange
        }
    }

    var color: Color {
        switch self {
        case .white: Color(red: 0.95, green: 0.94, blue: 0.90)
        case .yellow: Color(red: 1.00, green: 0.82, blue: 0.25)
        case .red: Color(red: 0.94, green: 0.30, blue: 0.30)
        case .orange: Color(red: 1.00, green: 0.55, blue: 0.20)
        case .blue: Color(red: 0.24, green: 0.55, blue: 1.00)
        case .green: Color(red: 0.21, green: 0.79, blue: 0.42)
        }
    }
}

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Steps the sticker colours forward ten times a second.
struct MascotAnimator {
    /// One outer layer mid-turn.
    struct Twist {
        var isRow: Bool
        /// 0 or 2: only outer layers turn, so the centre never moves.
        var index: Int
        var direction: Int
        var committed = false
    }

    static let solved = Array(repeating: CubeColor.green, count: 9)

    private(set) var stickers = MascotAnimator.solved
    private(set) var tick = 0
    private var twist: Twist?
    private var rng = SplitMix64(seed: 0xC0BE)

    /// The layer currently drawn half a sticker out of line.
    var turningLayer: Twist? {
        guard let twist, !twist.committed else { return nil }
        return twist
    }

    mutating func step(mood: MascotMood, target: [CubeColor]) {
        tick &+= 1
        switch mood {
        case .solving, .scrambling:
            // Three ticks a move: half-turned, landed, rest.
            if let current = twist {
                if current.committed {
                    twist = nil
                } else {
                    land(current)
                    twist?.committed = true
                }
            } else {
                twist = Twist(
                    isRow: Bool.random(using: &rng),
                    index: Bool.random(using: &rng) ? 0 : 2,
                    direction: Bool.random(using: &rng) ? 1 : -1
                )
            }
        case .solved, .celebrating:
            twist = nil
            stickers = Self.solved
        case .idle, .nervous, .ready:
            twist = nil
            stickers = target
        }
    }

    /// Slides the layer along by one sticker; a new colour comes round from the side.
    private mutating func land(_ twist: Twist) {
        let line = twist.isRow
            ? [3 * twist.index, 3 * twist.index + 1, 3 * twist.index + 2]
            : [twist.index, twist.index + 3, twist.index + 6]
        let incoming = CubeColor.allCases.randomElement(using: &rng)!
        if twist.direction > 0 {
            stickers[line[2]] = stickers[line[1]]
            stickers[line[1]] = stickers[line[0]]
            stickers[line[0]] = incoming
        } else {
            stickers[line[0]] = stickers[line[1]]
            stickers[line[1]] = stickers[line[2]]
            stickers[line[2]] = incoming
        }
    }
}

enum MascotSprite {
    /// The sprite is drawn on a square grid of chunky pixels, with headroom above for jumping.
    static let grid = 22

    private static let ink = Color(red: 0.11, green: 0.105, blue: 0.10)
    /// The grid column where the body starts.
    static let bodyLeft = 5
    private static let bodyTop = 8
    private static let jump = [0, -2, -4, -5, -5, -4, -2, 0]

    /// Cubby's silhouette for the menu bar, tinted by the system.
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            // Body, arms, feet.
            for rect in [(3, 2, 12, 12), (1, 7, 2, 2), (15, 7, 2, 2), (4, 14, 3, 2), (11, 14, 3, 2)] {
                NSRect(x: rect.0, y: rect.1, width: rect.2, height: rect.3).fill()
            }
            // Eyes and mouth are cut out.
            for rect in [(5, 7, 2, 2), (11, 7, 2, 2), (8, 10, 2, 1)] {
                NSRect(x: rect.0, y: rect.1, width: rect.2, height: rect.3).fill(using: .destinationOut)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func render(
        mood: MascotMood,
        stickers: [CubeColor],
        twist: MascotAnimator.Twist?,
        tick: Int,
        fill: (_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ color: Color) -> Void
    ) {
        var lift = 0
        var armsUp = false
        switch mood {
        case .nervous: lift = 1
        case .ready: lift = -1
        case .solved: armsUp = true
        case .celebrating:
            lift = jump[tick % jump.count]
            armsUp = true
        case .idle, .solving, .scrambling: break
        }
        let bx = bodyLeft
        let by = bodyTop + lift
        let beat = (tick / 2) % 2 == 0

        if mood == .celebrating {
            for i in 0..<12 {
                let x = (i * 7 + 2) % grid
                let y = (tick + i * 5) % grid
                fill(x, y, 1, 1, CubeColor.allCases[(i + tick / 3) % CubeColor.allCases.count].color)
            }
        }

        // Feet go down first so a crouching body covers their tops.
        var leftFoot = (x: bx + 1, y: grid - 2, height: 2)
        var rightFoot = (x: bx + 8, y: grid - 2, height: 2)
        switch mood {
        case .celebrating:
            leftFoot.y += lift
            rightFoot.y += lift
        case .ready:
            // Up on tiptoe.
            leftFoot.y -= 1
            leftFoot.height = 3
            rightFoot.y -= 1
            rightFoot.height = 3
        case .nervous:
            leftFoot.x -= 1
            rightFoot.x += 1
        case .solving:
            // Tapping: one foot off the ground at a time.
            if beat { leftFoot.height = 1 } else { rightFoot.height = 1 }
        case .idle, .solved, .scrambling: break
        }
        fill(leftFoot.x, leftFoot.y, 3, leftFoot.height, stickers[6].color)
        fill(rightFoot.x, rightFoot.y, 3, rightFoot.height, stickers[8].color)

        func nudge(row: Int, column: Int) -> (x: Int, y: Int) {
            guard let twist else { return (0, 0) }
            if twist.isRow, twist.index == row { return (twist.direction * 2, 0) }
            if !twist.isRow, twist.index == column { return (0, twist.direction * 2) }
            return (0, 0)
        }

        for row in 0..<3 {
            for column in 0..<3 {
                let offset = nudge(row: row, column: column)
                fill(bx + 4 * column + offset.x, by + 4 * row + offset.y, 4, 4, stickers[3 * row + column].color)
            }
        }

        let leftArm = stickers[3].color
        let rightArm = stickers[5].color
        if armsUp {
            fill(bx - 2, by + 4, 2, 2, leftArm)
            fill(bx - 3, by + 2, 2, 2, leftArm)
            fill(bx + 12, by + 4, 2, 2, rightArm)
            fill(bx + 13, by + 2, 2, 2, rightArm)
        } else {
            var leftY = by + 5 + nudge(row: 1, column: 0).y
            var rightY = by + 5 + nudge(row: 1, column: 2).y
            if mood == .solving {
                if beat { leftY -= 1 } else { rightY -= 1 }
            }
            fill(bx - 2, leftY, 2, 2, leftArm)
            fill(bx + 12, rightY, 2, 2, rightArm)
        }

        enum Mouth { case flat, wide, round, smile }
        var eyeY = by + 5
        var eyeHeight = 2
        var glance = 0
        var mouth = Mouth.flat
        switch mood {
        case .idle:
            if tick % 37 == 0 {
                // Blink.
                eyeY = by + 6
                eyeHeight = 1
            }
            switch (tick / 10) % 12 {
            case 5: glance = 1
            case 8: glance = -1
            default: break
            }
        case .nervous:
            mouth = .wide
        case .ready:
            eyeY = by + 4
            eyeHeight = 3
            mouth = .round
        case .solving:
            eyeY = by + 6
            eyeHeight = 1
        case .solved, .celebrating:
            eyeHeight = 1
            mouth = .smile
        case .scrambling:
            mouth = .round
        }
        fill(bx + 1 + glance, eyeY, 2, eyeHeight, ink)
        fill(bx + 9 + glance, eyeY, 2, eyeHeight, ink)

        switch mouth {
        case .flat:
            fill(bx + 5, by + 7, 2, 1, ink)
        case .wide:
            fill(bx + 4, by + 7, 4, 1, ink)
        case .round:
            fill(bx + 5, by + 6, 2, 2, ink)
        case .smile:
            fill(bx + 5, by + 7, 2, 1, ink)
            fill(bx + 4, by + 6, 1, 1, ink)
            fill(bx + 7, by + 6, 1, 1, ink)
        }
    }
}

struct MascotView: View {
    var mood: MascotMood
    var pattern: [CubeColor]
    var pixel: CGFloat = 5

    @State private var animator = MascotAnimator()
    private let clock = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        let frame = animator
        Canvas { context, _ in
            MascotSprite.render(mood: mood, stickers: frame.stickers, twist: frame.turningLayer, tick: frame.tick) { x, y, width, height, color in
                let rect = CGRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel, width: CGFloat(width) * pixel, height: CGFloat(height) * pixel)
                context.fill(Path(rect), with: .color(color))
            }
        }
        .frame(width: CGFloat(MascotSprite.grid) * pixel, height: CGFloat(MascotSprite.grid) * pixel)
        .onReceive(clock) { _ in animator.step(mood: mood, target: pattern) }
        .onAppear { animator.step(mood: mood, target: pattern) }
        .accessibilityLabel("Cubby, the cube mascot")
    }
}

/// The app icon: Cubby on a dark tile.
struct IconView: View {
    private let pattern: [CubeColor] = [.red, .white, .blue, .yellow, .green, .orange, .blue, .red, .yellow]
    private let pixel: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 186, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.19, green: 0.185, blue: 0.18), Color(red: 0.09, green: 0.088, blue: 0.085)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(width: 824, height: 824)
            Canvas { context, size in
                // The resting sprite spans columns 3..<19 and rows 8..<22 of its grid.
                let originX = (size.width - 16 * pixel) / 2 - 3 * pixel
                let originY = (size.height - 14 * pixel) / 2 - 8 * pixel
                MascotSprite.render(mood: .idle, stickers: pattern, twist: nil, tick: 1) { x, y, width, height, color in
                    let rect = CGRect(
                        x: originX + CGFloat(x) * pixel,
                        y: originY + CGFloat(y) * pixel,
                        width: CGFloat(width) * pixel,
                        height: CGFloat(height) * pixel
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: 1024, height: 1024)
    }
}
