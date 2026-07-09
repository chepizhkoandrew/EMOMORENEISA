import SwiftUI

/// A compact interface-language picker. Reads and updates the shared
/// `LocalizationManager`; every localized view refreshes instantly on change.
struct LanguagePickerView: View {
    @State private var loc = LocalizationManager.shared

    var body: some View {
        Picker(L("App Language"), selection: Binding(
            get: { loc.language },
            set: { loc.setLanguage($0) }
        )) {
            ForEach(AppLanguage.allCases) { lang in
                Text("\(lang.flag)  \(lang.nativeName)").tag(lang)
            }
        }
    }
}

/// Inline row variant for menus/lists that shows the current language and
/// cycles to the next one on tap (used where a full `Picker` doesn't fit).
struct LanguageMenuButton: View {
    @State private var loc = LocalizationManager.shared

    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    loc.setLanguage(lang)
                } label: {
                    if lang == loc.language {
                        Label("\(lang.flag)  \(lang.nativeName)", systemImage: "checkmark")
                    } else {
                        Text("\(lang.flag)  \(lang.nativeName)")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(loc.language.flag)
                Text(L("Language"))
            }
        }
    }
}
