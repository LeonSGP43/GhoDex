import SwiftUI

struct SettingsView: View {
    // We need access to our app delegate to know if we're quitting or not.
    @EnvironmentObject private var appDelegate: AppDelegate
    @AppStorage(AppLanguageSetting.storageKey)
    private var selectedLanguageRawValue: String = AppLanguageSetting.storedSelection().rawValue

    private var selectedLanguage: Binding<AppLanguageSetting> {
        Binding(
            get: {
                AppLanguageSetting(rawValue: selectedLanguageRawValue) ?? .system
            },
            set: { newValue in
                selectedLanguageRawValue = newValue.rawValue
                newValue.apply()
            }
        )
    }

    private var needsRestart: Bool {
        (AppLanguageSetting(rawValue: selectedLanguageRawValue) ?? .system) != AppLanguageSetting.launchedSetting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Image("AppIconImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Settings.title)
                        .font(.title)
                    Text(L10n.Settings.body)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.Settings.languageTitle)
                    .font(.headline)
                Picker(L10n.Settings.languageTitle, selection: selectedLanguage) {
                    ForEach(AppLanguageSetting.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(L10n.Settings.languageDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if needsRestart {
                HStack {
                    Text(L10n.Settings.languageRestartRequired)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.Settings.restartNow) {
                        appDelegate.relaunchApplication()
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 520, maxWidth: 520, minHeight: 260, maxHeight: 320)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
