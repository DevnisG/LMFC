import SwiftUI

struct CleaningGuideView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cleaning Guide")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            HStack(alignment: .top, spacing: 8) {
                card("Keyboard", instruction: "Wipe the keys with a dry, lint-free cloth.", surface: "keyboard", motion: "arrow.left.and.right")
                card("Trackpad", instruction: "Wipe gently with a soft, dry cloth.", surface: "trackpad", motion: "arrow.up.and.down")
                card("Display", instruction: "Wipe with a lint-free cloth lightly dampened with water.", surface: "display", motion: "drop")
            }

            if let guideURL {
                Link("More cleaning details", destination: guideURL)
                    .font(.caption)
                    .modifier(ClickablePointer())
            }
        }
        .modifier(PanelSurface())
    }

    private var guideURL: URL? {
        let region = locale.language.languageCode?.identifier == "es" ? "es-es" : "en-us"
        return URL(string: "https://support.apple.com/\(region)/103258")
    }

    private func card(
        _ title: LocalizedStringKey,
        instruction: LocalizedStringKey,
        surface: String,
        motion: String
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: surface)
                    .font(.system(size: 24, weight: .regular))
                VStack(spacing: 2) {
                    Image(systemName: motion)
                        .font(.system(size: 9, weight: .semibold))
                    foldedCloth
                        .frame(width: 18, height: 12)
                        .rotationEffect(.degrees(-12))
                }
            }
            .foregroundStyle(colorScheme == .dark ? InterfaceStyle.sky : InterfaceStyle.accent)
            .frame(maxWidth: .infinity, minHeight: 34)
            .accessibilityHidden(true)

            Divider()
                .overlay(InterfaceStyle.sky.opacity(0.24))
                .accessibilityHidden(true)

            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(instruction)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
        .background(InterfaceStyle.sky.opacity(0.07), in: shape)
        .overlay {
            shape.strokeBorder(InterfaceStyle.sky.opacity(0.24))
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
    }

    private var foldedCloth: some View {
        RoundedRectangle(cornerRadius: 2)
            .strokeBorder(lineWidth: 1.2)
            .overlay(alignment: .top) {
                Rectangle()
                    .frame(height: 1)
                    .padding(.horizontal, 2)
                    .padding(.top, 4)
            }
    }
}
