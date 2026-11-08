import SwiftUI

enum TeenTheme {
    static let ink = Color(red: 0.025, green: 0.027, blue: 0.035)
    static let surface = Color(red: 0.075, green: 0.078, blue: 0.094)
    static let raised = Color(red: 0.115, green: 0.118, blue: 0.138)
    static let lime = Color(red: 0.58, green: 1.0, blue: 0.04)
    static let ice = Color(red: 0.18, green: 0.82, blue: 1.0)
    static let violet = Color(red: 0.60, green: 0.42, blue: 1.0)
    static let muted = Color.white.opacity(0.48)
    static let line = Color.white.opacity(0.10)
}

struct TeenCard<Content: View>: View {
    let accent: Color?
    @ViewBuilder var content: Content
    init(accent: Color? = nil, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(TeenTheme.surface)
                    .overlay(alignment: .topLeading) {
                        if let accent {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(LinearGradient(colors: [accent.opacity(0.16), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
            }
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(TeenTheme.line, lineWidth: 1))
    }
}

struct TeenMetric: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color
    var body: some View {
        TeenCard(accent: tint) {
            Image(systemName: icon).foregroundStyle(tint).font(.headline)
            Spacer(minLength: 14)
            Text(value).font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
            Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(TeenTheme.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 116)
    }
}

struct TeenSectionTitle: View {
    let title: String
    let detail: String?
    init(_ title: String, detail: String? = nil) { self.title = title; self.detail = detail }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(.title3, design: .rounded, weight: .bold))
            Spacer()
            if let detail { Text(detail).font(.caption.weight(.medium)).foregroundStyle(TeenTheme.muted) }
        }
        .padding(.horizontal, 2)
    }
}

struct TeenPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct TeenEmpty: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(TeenTheme.lime)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(TeenTheme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22)
    }
}

struct TeenPill: View {
    let title: String
    let tint: Color
    var body: some View {
        Text(title).font(.caption2.weight(.bold)).foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(tint.opacity(0.13), in: Capsule())
    }
}
