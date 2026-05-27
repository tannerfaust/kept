import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
typealias PlatformImage = NSImage
#endif

extension PlatformImage {
    static func from(data: Data) -> PlatformImage? {
        #if canImport(UIKit)
        UIImage(data: data)
        #else
        NSImage(data: data)
        #endif
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

enum KeptColor {
    static let ink = Color.black
    static let mist = Color(red: 0.96, green: 0.96, blue: 0.98)
    static let coral = Color(red: 1.00, green: 0.20, blue: 0.40)  // Neon Red/Pink (#FF3366)
    static let citron = Color(red: 0.80, green: 1.00, blue: 0.00) // Neon Lime (#CCFF00)
    static let cyan = Color(red: 0.00, green: 0.94, blue: 1.00)   // Neon Cyan (#00F0FF)
    static let violet = Color(red: 0.74, green: 0.00, blue: 1.00) // Neon Violet (#BD00FF)
    static let green = Color(red: 0.00, green: 1.00, blue: 0.40)  // Neon Green (#00FF66)
}

extension View {
    @ViewBuilder
    func keptGlass(cornerRadius: CGFloat = 24, interactive: Bool = false) -> some View {
        self
            .background(Color.white)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.black, lineWidth: 2)
            )
            .shadow(color: Color.black, radius: 0, x: 4, y: 4) // Brutalist solid offset shadow
    }

    func cardShadow() -> some View {
        self // Shadows are handled in keptGlass or keptGlow directly to keep the theme high-contrast
    }

    func keptGlow(color: Color, radius: CGFloat = 12) -> some View {
        self.shadow(color: color.opacity(0.65), radius: radius, x: 0, y: 0)
    }
}

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64

        switch clean.count {
        case 6:
            red = (value >> 16) & 0xff
            green = (value >> 8) & 0xff
            blue = value & 0xff
        default:
            red = 0x00
            green = 0x00
            blue = 0x00
        }

        self.init(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255
        )
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.98)
            
            // Subtle engineering/planner grid pattern
            GeometryReader { geo in
                Path { path in
                    let step: CGFloat = 32
                    // Vertical lines
                    for x in stride(from: 0, to: geo.size.width, by: step) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                    // Horizontal lines
                    for y in stride(from: 0, to: geo.size.height, by: step) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                }
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
            }
        }
        .ignoresSafeArea()
    }
}

struct MetricPill: View {
    var title: String
    var value: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .black))
                .foregroundStyle(KeptColor.ink)
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(Color.black.opacity(0.6))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.black, lineWidth: 2)
        )
        .shadow(color: Color.black, radius: 0, x: 3, y: 3)
    }
}

struct ScoreRing: View {
    var score: Double
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.03, min(score, 1)))
                .stroke(
                    AngularGradient(
                        colors: [KeptColor.green, KeptColor.citron, KeptColor.coral],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int((score * 100).rounded()))%")
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                    .foregroundStyle(Color.black)
                Text("Integrity")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color.black.opacity(0.6))
            }
        }
        .accessibilityLabel("Integrity score \(Int((score * 100).rounded())) percent")
    }
}

// MARK: - StampSlamModifier

struct StampSlamModifier: ViewModifier {
    var isActive: Bool

    @State private var animating = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(animating ? 1.0 : 2.0)
            .rotationEffect(.degrees(animating ? -6 : -12))
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    animating = false
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.5, blendDuration: 0)) {
                        animating = true
                    }
                } else {
                    animating = false
                }
            }
    }
}

extension View {
    func stampSlam(isActive: Bool) -> some View {
        modifier(StampSlamModifier(isActive: isActive))
    }
}

// MARK: - ConfettiBurst

struct ConfettiParticle: Identifiable {
    let id = UUID()
    let symbol: String
    let color: Color
    let angle: Double   // radians
    let distance: CGFloat
    let rotationOffset: Double
}

struct ConfettiBurstView: View {
    var isActive: Bool

    @State private var animating = false

    private static let symbols = ["star.fill", "sparkle", "heart.fill", "star.circle.fill", "sparkles"]
    private static let colors: [Color] = [
        KeptColor.coral,
        KeptColor.citron,
        KeptColor.cyan,
        KeptColor.violet,
        KeptColor.green
    ]

    private let particles: [ConfettiParticle] = (0..<12).map { i in
        ConfettiParticle(
            symbol: symbols[i % symbols.count],
            color: colors[i % colors.count],
            angle: Double(i) * (2 * .pi / 12) + Double.random(in: -0.3...0.3),
            distance: CGFloat.random(in: 40...90),
            rotationOffset: Double.random(in: -45...45)
        )
    }

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Image(systemName: particle.symbol)
                    .font(.system(size: CGFloat.random(in: 10...18), weight: .bold))
                    .foregroundStyle(particle.color)
                    .offset(
                        x: animating ? cos(particle.angle) * particle.distance : 0,
                        y: animating ? sin(particle.angle) * particle.distance : 0
                    )
                    .rotationEffect(.degrees(animating ? particle.rotationOffset : 0))
                    .scaleEffect(animating ? 1.0 : 0.3)
                    .opacity(animating ? 0 : 1)
            }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                animating = false
                withAnimation(.easeOut(duration: 0.7)) {
                    animating = true
                }
            } else {
                animating = false
            }
        }
        .allowsHitTesting(false)
    }
}

struct ConfettiBurstModifier: ViewModifier {
    var isActive: Bool

    func body(content: Content) -> some View {
        content.overlay {
            ConfettiBurstView(isActive: isActive)
        }
    }
}

extension View {
    func confettiBurst(isActive: Bool) -> some View {
        modifier(ConfettiBurstModifier(isActive: isActive))
    }
}

// MARK: - PulseGlowModifier

struct PulseGlowModifier: ViewModifier {
    var isActive: Bool
    var color: Color

    @State private var animating = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(animating ? 1.08 : 1.0)
            .shadow(color: animating ? color.opacity(0.6) : Color.clear, radius: animating ? 12 : 0)
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    animating = false
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5, blendDuration: 0)) {
                        animating = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0)) {
                            animating = false
                        }
                    }
                } else {
                    animating = false
                }
            }
    }
}

extension View {
    func pulseGlow(isActive: Bool, color: Color = KeptColor.cyan) -> some View {
        modifier(PulseGlowModifier(isActive: isActive, color: color))
    }
}

// MARK: - HapticFeedback

enum HapticFeedback {
    static func impact() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    static func warning() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif
    }
}
