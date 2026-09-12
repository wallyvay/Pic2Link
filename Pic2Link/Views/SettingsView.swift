import SwiftUI

/// 多图床配置设置视图
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var localization = LocalizationManager.shared

    @State private var profiles: [ImageHostProfile]
    @State private var activeProfileID: UUID?
    @State private var selectedProfileID: UUID?
    @State private var shortcut: KeyboardShortcut
    @State private var launchAtLogin: Bool
    @State private var uploadCompression: UploadCompressionSettings
    @State private var captionBeforeUpload: Bool

    @State private var isValidating = false
    @State private var validationMessage = ""
    @State private var isValidationSuccess = false

    let settings: AppSettings
    let onSave: (AppSettings) -> Void
    let onValidate: (ImageHostProfile) async throws -> Bool

    init(settings: AppSettings, onSave: @escaping (AppSettings) -> Void, onValidate: @escaping (ImageHostProfile) async throws -> Bool) {
        self.settings = settings
        self.onSave = onSave
        self.onValidate = onValidate

        let normalizedProfiles = settings.profiles.isEmpty ? AppSettings.default.profiles : settings.profiles
        let initialSelection = settings.activeProfileID ?? normalizedProfiles.first?.id

        _profiles = State(initialValue: normalizedProfiles)
        _activeProfileID = State(initialValue: settings.activeProfileID ?? normalizedProfiles.first?.id)
        _selectedProfileID = State(initialValue: initialSelection)
        _shortcut = State(initialValue: settings.uploadShortcut)
        _launchAtLogin = State(initialValue: settings.launchAtLogin)
        _uploadCompression = State(initialValue: settings.uploadCompression)
        _captionBeforeUpload = State(initialValue: settings.captionBeforeUpload)
    }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                profileSidebar
                    .frame(minWidth: 210, idealWidth: 230, maxWidth: 260)

                editorPane
                    .frame(minWidth: 420)
            }

            Divider()

            footerBar
        }
        .frame(width: 780, height: 620)
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            validationMessage = ""
        }
    }

    private var profileSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("settings.profileList"))
                .font(.headline)
                .accessibilityIdentifier("settings.profileList.title")

            List(selection: $selectedProfileID) {
                ForEach(profiles) { profile in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.displayName)
                            Text(profile.provider.displayName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if profile.id == activeProfileID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .tag(profile.id)
                }
            }
            .listStyle(.sidebar)

            HStack {
                Menu {
                    ForEach(ImageHostProvider.allCases) { provider in
                        Button(provider.displayName) {
                            addProfile(provider: provider)
                        }
                    }
                } label: {
                    Label(L10n.tr("settings.addProfile"), systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .help(L10n.tr("settings.addProfile"))

                Button(role: .destructive) {
                    deleteSelectedProfile()
                } label: {
                    Label(L10n.tr("common.delete"), systemImage: "trash")
                }
                .disabled(selectedProfile == nil || profiles.count <= 1)
            }

            Button(L10n.tr("settings.setCurrent")) {
                if let selectedProfileID {
                    activeProfileID = selectedProfileID
                }
            }
            .disabled(selectedProfile == nil || selectedProfileID == activeProfileID)
        }
        .padding()
    }

    private var editorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                languageSection

                if let profile = selectedProfile {
                    profileEditor(for: profile)
                    shortcutSection
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(L10n.tr("caption.enabled"), isOn: $captionBeforeUpload)
                            .accessibilityIdentifier("settings.caption.toggle")
                        Text(L10n.tr("caption.description"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    compressionSection
                    appBehaviorSection
                    validationSection
                } else {
                    ContentUnavailableView(
                        L10n.tr("settings.noSelection.title"),
                        systemImage: "tray",
                        description: Text(L10n.tr("settings.noSelection.description"))
                    )
                        .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding()
        }
        .accessibilityIdentifier("settings.editor.scroll")
    }

    private var footerBar: some View {
        HStack(spacing: 12) {
            Button(action: validateSelectedProfile) {
                if isValidating {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(L10n.tr("settings.validating"))
                } else {
                    Image(systemName: "checkmark.circle")
                    Text(L10n.tr("settings.validate"))
                }
            }
            .disabled(isValidating || selectedProfile == nil)

            Spacer()

            Button(L10n.tr("common.cancel")) {
                dismiss()
            }

            Button(L10n.tr("common.save")) {
                let finalProfiles = profiles.isEmpty ? AppSettings.default.profiles : profiles
                let finalActiveID = activeProfileID ?? finalProfiles.first?.id
                onSave(AppSettings(
                    profiles: finalProfiles,
                    activeProfileID: finalActiveID,
                    uploadShortcut: shortcut,
                    launchAtLogin: launchAtLogin,
                    uploadCompression: uploadCompression,
                    captionBeforeUpload: captionBeforeUpload
                ))
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(shortcut == .selectedPhotos)
        }
        .padding()
    }

    @ViewBuilder
    private func profileEditor(for profile: ImageHostProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("settings.profileConfiguration"))
                .font(.headline)

            ConfigField(
                title: L10n.tr("field.profileName"),
                placeholder: L10n.tr("field.profileName.placeholder"),
                text: binding(for: \.name)
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("field.provider"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker(L10n.tr("field.provider"), selection: binding(for: \.provider)) {
                    ForEach(ImageHostProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
            }

            Text(profile.provider.helpText)
                .font(.caption)
                .foregroundColor(.secondary)

            providerFields(for: profile)
        }
    }

    @ViewBuilder
    private func providerFields(for profile: ImageHostProfile) -> some View {
        ConfigField(
            title: profile.provider.containerFieldTitle,
            placeholder: profile.provider.containerFieldPlaceholder,
            text: binding(for: \.bucketName)
        )

        switch profile.provider {
        case .alibabaOSS:
            commonCloudFields(includeRegion: false, includePublicURL: true)
        case .synologyC2, .jdCloud, .baiduBOS, .amazonS3, .googleCloudStorage, .cloudflareR2, .backblazeB2, .genericS3Compatible:
            commonCloudFields(includeRegion: true, includePublicURL: true)
        case .tencentCOS:
            commonCloudFields(includeRegion: true, includePublicURL: true)
        case .qiniu:
            commonCloudFields(includeRegion: false, includePublicURL: true)
        case .upyun:
            ConfigField(title: L10n.tr("field.operator"), placeholder: L10n.tr("field.operator.placeholder"), text: binding(for: \.operatorName))
            ConfigField(title: L10n.tr("field.operatorPassword"), placeholder: L10n.tr("field.operatorPassword.placeholder"), text: binding(for: \.password), isSecure: true)
            ConfigField(title: L10n.tr("field.apiEndpoint"), placeholder: profile.provider.defaultEndpoint, text: binding(for: \.endpoint))
            ConfigField(title: L10n.tr("field.publicURL"), placeholder: "https://img.example.com", text: binding(for: \.publicURL))
            commonPathFields
        case .webDAV:
            ConfigField(title: L10n.tr("field.username"), placeholder: L10n.tr("field.username.placeholder"), text: binding(for: \.accessKey))
            ConfigField(title: L10n.tr("field.password"), placeholder: L10n.tr("field.password.placeholder"), text: binding(for: \.secretKey), isSecure: true)
            ConfigField(title: L10n.tr("field.endpoint"), placeholder: profile.provider.defaultEndpoint, text: binding(for: \.endpoint))
            ConfigField(title: L10n.tr("field.publicURL"), placeholder: "https://files.example.com", text: binding(for: \.publicURL))
            commonPathFields
        case .flickr:
            ConfigField(title: L10n.tr("field.apiKey"), placeholder: L10n.tr("field.apiKey"), text: binding(for: \.apiKey))
            ConfigField(title: L10n.tr("field.sharedSecret"), placeholder: L10n.tr("field.sharedSecret"), text: binding(for: \.sharedSecret), isSecure: true)
            ConfigField(title: L10n.tr("field.authToken"), placeholder: L10n.tr("field.authToken"), text: binding(for: \.authToken), isSecure: true)
        case .imgur:
            ConfigField(title: L10n.tr("field.clientID"), placeholder: L10n.tr("field.clientID"), text: binding(for: \.clientID))
        }
    }

    private func commonCloudFields(includeRegion: Bool, includePublicURL: Bool) -> some View {
        Group {
            ConfigField(title: L10n.tr("field.accessKey"), placeholder: L10n.tr("field.accessKey"), text: binding(for: \.accessKey))
            ConfigField(title: L10n.tr("field.secretKey"), placeholder: L10n.tr("field.secretKey.placeholder"), text: binding(for: \.secretKey), isSecure: true)
            ConfigField(title: L10n.tr("field.endpoint"), placeholder: selectedProfile?.provider.defaultEndpoint ?? "", text: binding(for: \.endpoint))

            if includeRegion {
                ConfigField(title: L10n.tr("field.region"), placeholder: L10n.tr("field.region.placeholder"), text: binding(for: \.region))
            }

            if includePublicURL {
                ConfigField(title: L10n.tr("field.publicURL"), placeholder: "https://img.example.com", text: binding(for: \.publicURL))
            }

            commonPathFields
        }
    }

    private var commonPathFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            ConfigField(title: L10n.tr("field.basePath"), placeholder: L10n.tr("field.basePath.placeholder"), text: binding(for: \.basePath))

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("field.pathStyle"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker(L10n.tr("field.pathStyle"), selection: binding(for: \.pathStyle)) {
                    ForEach(PathStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("settings.shortcut"))
                .font(.headline)

            HStack(spacing: 12) {
                Toggle("⌘", isOn: $shortcut.command)
                    .toggleStyle(.checkbox)
                Toggle("⌥", isOn: $shortcut.option)
                    .toggleStyle(.checkbox)
                Toggle("^", isOn: $shortcut.control)
                    .toggleStyle(.checkbox)
                Toggle("⇧", isOn: $shortcut.shift)
                    .toggleStyle(.checkbox)
            }

            Picker(L10n.tr("settings.key"), selection: $shortcut.key) {
                ForEach(ShortcutKey.allCases) { key in
                    Text(key.rawValue).tag(key)
                }
            }
            .pickerStyle(.menu)

            Text(L10n.tr("settings.currentShortcut", shortcut.displayString))
                .font(.caption)
                .foregroundColor(.secondary)

            Text(L10n.tr(shortcut == .selectedPhotos ? "selection.shortcutReserved" : SelectionApplication.localizedKey("selection.shortcutHelp")))
                .accessibilityIdentifier("settings.selection.help")
                .font(.caption)
                .foregroundStyle(shortcut == .selectedPhotos ? Color.red : Color.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .cornerRadius(10)
    }

    private var appBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("settings.appBehavior"))
                .font(.headline)

            Toggle(L10n.tr("settings.launchAtLogin"), isOn: $launchAtLogin)
                .toggleStyle(.switch)

            Text(L10n.tr("settings.launchAtLogin.help"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .cornerRadius(10)
    }

    private var compressionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.tr("settings.compression"), systemImage: "arrow.down.right.and.arrow.up.left")
                    .font(.headline)
                    .accessibilityIdentifier("settings.compression.title")

                Spacer()

                Toggle(L10n.tr("settings.compression"), isOn: $uploadCompression.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("settings.compression.toggle")
            }

            Text(L10n.tr("settings.compression.help"))
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Picker(L10n.tr("compression.mode.label"), selection: $uploadCompression.mode) {
                    ForEach(UploadResizeMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("settings.compression.mode")

                compressionValueEditor

                Text(L10n.tr("compression.singleMode.help"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .disabled(!uploadCompression.isEnabled)
            .opacity(uploadCompression.isEnabled ? 1 : 0.58)

            Divider()

            Toggle(
                L10n.tr("settings.livePhotoGIF"),
                isOn: $uploadCompression.convertClipboardLivePhotosToGIF
            )
            .toggleStyle(.switch)
            .accessibilityIdentifier("settings.compression.livePhotoGIF.toggle")

            Text(L10n.tr("settings.livePhotoGIF.help"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .cornerRadius(10)
    }

    @ViewBuilder
    private var compressionValueEditor: some View {
        switch uploadCompression.mode {
        case .width:
            compressionDimensionField(
                title: L10n.tr("compression.width"),
                value: $uploadCompression.width
            )

        case .height:
            compressionDimensionField(
                title: L10n.tr("compression.height"),
                value: $uploadCompression.height
            )

        case .percentage:
            HStack {
                Text(L10n.tr("compression.percentage"))
                Spacer()
                TextField(
                    L10n.tr("compression.percentage"),
                    value: $uploadCompression.percentage,
                    format: .number.precision(.fractionLength(0...1))
                )
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                Text("%")
                    .foregroundColor(.secondary)
            }

        case .free, .maximum:
            HStack(spacing: 14) {
                compressionDimensionField(
                    title: L10n.tr("compression.width"),
                    value: $uploadCompression.width
                )
                compressionDimensionField(
                    title: L10n.tr("compression.height"),
                    value: $uploadCompression.height
                )
            }

            if uploadCompression.mode == .maximum {
                Text(L10n.tr("compression.maximum.hint"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func compressionDimensionField(title: String, value: Binding<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(L10n.tr("compression.unit.pixels"))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var validationSection: some View {
        if !validationMessage.isEmpty {
            HStack {
                Image(systemName: isValidationSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isValidationSuccess ? .green : .red)
                Text(validationMessage)
                    .font(.caption)
                    .foregroundColor(isValidationSuccess ? .green : .red)
            }
            .padding(.top, 4)
        }
    }

    private var selectedProfile: ImageHostProfile? {
        guard let selectedProfileID else { return nil }
        return profiles.first(where: { $0.id == selectedProfileID })
    }

    private func binding<Value>(for keyPath: WritableKeyPath<ImageHostProfile, Value>) -> Binding<Value> {
        Binding(
            get: {
                guard let selectedProfileID,
                      let index = profiles.firstIndex(where: { $0.id == selectedProfileID }) else {
                    return ImageHostProfile.sample[keyPath: keyPath]
                }
                return profiles[index][keyPath: keyPath]
            },
            set: { newValue in
                guard let selectedProfileID,
                      let index = profiles.firstIndex(where: { $0.id == selectedProfileID }) else {
                    return
                }

                profiles[index][keyPath: keyPath] = newValue

                if keyPath == \.provider {
                    var updated = ImageHostProfile.blank(provider: profiles[index].provider)
                    updated.id = profiles[index].id
                    updated.name = profiles[index].name
                    profiles[index] = updated
                }
            }
        )
    }

    private func addProfile(provider: ImageHostProvider) {
        let profile = ImageHostProfile.blank(provider: provider)
        profiles.append(profile)
        selectedProfileID = profile.id
        if activeProfileID == nil {
            activeProfileID = profile.id
        }
        validationMessage = ""
    }

    private func deleteSelectedProfile() {
        guard let selectedProfileID else { return }
        profiles.removeAll { $0.id == selectedProfileID }

        if activeProfileID == selectedProfileID {
            activeProfileID = profiles.first?.id
        }

        self.selectedProfileID = profiles.first?.id
        validationMessage = ""
    }

    private func validateSelectedProfile() {
        guard let profile = selectedProfile else { return }
        isValidating = true
        validationMessage = ""

        Task {
            do {
                let success = try await onValidate(profile)
                await MainActor.run {
                    isValidating = false
                    isValidationSuccess = success
                    validationMessage = success ? L10n.tr("validation.success") : L10n.tr("validation.failed")
                }
            } catch {
                await MainActor.run {
                    isValidating = false
                    isValidationSuccess = false
                    validationMessage = L10n.tr("validation.error", error.localizedDescription)
                }
            }
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("settings.language"))
                .font(.headline)
                .accessibilityIdentifier("settings.language.title")

            Picker(
                L10n.tr("settings.language.picker"),
                selection: Binding(
                    get: { localization.currentLanguage },
                    set: { localization.setLanguage($0) }
                )
            ) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("settings.language.picker")

            Text(L10n.tr("settings.language.help"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .cornerRadius(10)
    }
}

struct ConfigField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            if isSecure {
                SecureField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}
