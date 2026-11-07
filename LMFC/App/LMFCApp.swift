import SwiftUI

enum InterfaceLanguage: String, CaseIterable {
    case english = "en"
    case spanish = "es"

    static var preferred: Self {
        Locale.preferredLanguages.first?.hasPrefix("es") == true ? .spanish : .english
    }

    var locale: Locale { Locale(identifier: rawValue) }
    var name: String { locale.localizedString(forLanguageCode: rawValue)?.capitalized ?? rawValue }
}

@main
struct LMFCApp: App {
    @AppStorage("interfaceLanguage") private var language = InterfaceLanguage.preferred
    @State private var session = CleaningSession(
        filter: EventTapKeyboardFilter(),
        access: SystemCleaningAccess()
    )

    var body: some Scene {
        Window("LMFC!", id: "main") {
            CleaningView(session: session, language: $language)
                .environment(\.locale, language.locale)
                .tint(InterfaceStyle.accent)
                .containerBackground(.ultraThinMaterial, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .windowResizability(.contentSize)
    }
}
