import SwiftUI

enum InterfaceStyle {
    static let accent = Color(red: 0.09, green: 0.40, blue: 0.91)
    static let sky = Color(red: 0.27, green: 0.68, blue: 0.99)
    static let cobalt = Color(red: 0.12, green: 0.30, blue: 0.77)
    static let controlHeight: CGFloat = 42
    static let rowInset: CGFloat = 12
}

struct PanelHeading: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(InterfaceStyle.accent)
                .frame(width: 38, height: 38)
                .background(InterfaceStyle.sky.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PanelSurface: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24)
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.28), in: shape)
            .overlay {
                shape.strokeBorder(InterfaceStyle.sky.opacity(0.22), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

struct ControlRowLabel: View {
    let title: LocalizedStringKey
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline.weight(.medium))
    }
}

struct AlignedSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                configuration.label
                Spacer(minLength: 8)
                Capsule()
                    .fill(configuration.isOn ? InterfaceStyle.accent : Color.secondary.opacity(0.30))
                    .overlay {
                        Circle()
                            .fill(.white)
                            .frame(width: 17, height: 17)
                            .offset(x: configuration.isOn ? 9 : -9)
                    }
                    .frame(width: 41, height: 23)
                    .opacity(isEnabled ? 1 : 0.6)
                    .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: configuration.isOn)
            }
            .frame(minHeight: 46)
            .padding(.horizontal, InterfaceStyle.rowInset)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(ClickablePointer())
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }
}

struct ClickablePointer: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.pointerStyle(isEnabled ? .link : nil)
    }
}

struct GlassChoiceButton: ViewModifier {
    let selected: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(selected ? InterfaceStyle.accent.opacity(0.42) : nil).interactive())
                .modifier(ClickablePointer())
        } else {
            content
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .background(InterfaceStyle.accent.opacity(selected ? 0.22 : 0), in: Capsule())
                .modifier(ClickablePointer())
        }
    }
}

struct GlassPrimaryButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .modifier(ClickablePointer())
        } else {
            content.buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .modifier(ClickablePointer())
        }
    }
}

struct GlassSecondaryButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .modifier(ClickablePointer())
        } else {
            content.buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .modifier(ClickablePointer())
        }
    }
}

struct GlassSurface: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
        }
    }
}
