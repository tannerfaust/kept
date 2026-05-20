import SwiftUI

enum DefyColor {
    static let ink = Color(red: 0.06, green: 0.07, blue: 0.10)
    static let mist = Color(red: 0.95, green: 0.97, blue: 0.98)
    static let coral = Color(red: 1.00, green: 0.34, blue: 0.30)
    static let citron = Color(red: 0.82, green: 0.95, blue: 0.25)
    static let cyan = Color(red: 0.18, green: 0.76, blue: 0.92)
    static let violet = Color(red: 0.48, green: 0.38, blue: 0.92)
    static let green = Color(red: 0.24, green: 0.74, blue: 0.38)
}

extension View {
    @ViewBuilder
    func defyGlass(cornerRadius: CGFloat = 24, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    func cardShadow() -> some View {
        shadow(color: .black.opacity(0.10), radius: 24, x: 0, y: 16)
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
            red = 0xff
            green = 0x56
            blue = 0x4d
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
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.99, blue: 0.94),
                    Color(red: 0.91, green: 0.98, blue: 1.00),
                    Color(red: 1.00, green: 0.94, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [.white.opacity(0.0), DefyColor.citron.opacity(0.20), .white.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .rotationEffect(.degrees(-14))
            .scaleEffect(1.4)
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
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(DefyColor.ink)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .defyGlass(cornerRadius: 18)
    }
}

struct ScoreRing: View {
    var score: Double
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.5), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.03, min(score, 1)))
                .stroke(
                    AngularGradient(colors: [DefyColor.green, DefyColor.citron, DefyColor.coral], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int((score * 100).rounded()))%")
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                Text("Integrity")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Integrity score \(Int((score * 100).rounded())) percent")
    }
}
