import SwiftUI

/// The Mac's Settings, in the Mac's order: Reading, Read aloud, Appearance, Translations, Data,
/// About. Shortcuts is the one tab the phone leaves out, because there is no keyboard to shortcut
/// on and nothing else would be reached from it.
///
/// The labels and section names are the Mac's; the wording that has been polished on the phone is
/// left exactly as it was.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let theme: Theme

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("Reading") {
                    HStack(spacing: 14) {
                        Image(systemName: "textformat.size.smaller")
                            .foregroundStyle(.secondary)
                        Slider(value: $store.settings.textSize, in: ReaderSettings.textSizes, step: 1)
                            .accessibilityLabel("Text size")
                            .accessibilityIdentifier("Text size")
                            .accessibilityValue("\(Int(store.settings.textSize)) points")
                        Image(systemName: "textformat.size.larger")
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 14) {
                        Image(systemName: "text.alignleft")
                            .foregroundStyle(.secondary)
                        Slider(value: $store.settings.lineSpacing, in: ReaderSettings.lineSpacings, step: 0.1)
                            .accessibilityLabel("Line spacing")
                            .accessibilityValue(store.settings.lineSpacing.formatted(.number.precision(.fractionLength(1))))
                        Image(systemName: "text.justify")
                            .foregroundStyle(.secondary)
                    }
                    Text("Text follows the system’s text size too.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Toggle("Words of Jesus in red", isOn: $store.settings.redLetters)
                    Toggle("Verse numbers", isOn: $store.settings.verseNumbers)
                    Toggle("One verse per line", isOn: $store.settings.versePerLine)
                    Toggle("Section headings", isOn: $store.settings.headings)
                    Toggle("Search whole words only", isOn: $store.settings.wholeWords)
                }
                .listRowBackground(Color(theme.fillStrong))

                Section("Read aloud") {
                    NavigationLink {
                        ReadAloudSettings(theme: theme)
                    } label: {
                        LabeledContent("Voice", value: store.speaker.voice)
                    }
                }
                .listRowBackground(Color(theme.fillStrong))

                Section("Appearance") {
                    HStack(spacing: 12) {
                        ForEach(Appearance.allCases) { appearance in
                            ThemeSwatch(
                                appearance: appearance, selected: store.settings.appearance == appearance, accent: theme
                            ) {
                                store.settings.appearance = appearance
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color(theme.fillStrong))

                Section("Translations") {
                    ForEach(store.translations, id: \.id) { t in
                        Button {
                            store.settings.translation = t.id
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(t.abbrev) — \(t.name)")
                                        .foregroundStyle(Color(theme.ink))
                                    if let description = t.description {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 0)
                                if store.settings.translation == t.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color(theme.accent))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(store.settings.translation == t.id ? "Selected" : "")
                    }
                }
                .listRowBackground(Color(theme.fillStrong))

                Section("Data") {
                    ExportButton(title: "Export as Markdown", format: .markdown, file: "Lamplit notes.md")
                    ExportButton(title: "Export as JSON", format: .json, file: "Lamplit notes.json")
                }
                .listRowBackground(Color(theme.fillStrong))

                Section("About") {
                    NavigationLink {
                        AboutView(theme: theme)
                    } label: {
                        Label("About and licences", systemImage: "info.circle")
                    }
                }
                .listRowBackground(Color(theme.fillStrong))
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

/// Settings → Read aloud: the Mac's tab, which is the voice list and the sample buttons.
struct ReadAloudSettings: View {
    @Environment(Store.self) private var store
    let theme: Theme

    private var speaker: Speaker { store.speaker }

    var body: some View {
        List {
            // The Mac's Read aloud tab opens with this switch; it will say these words once the Mac
            // follows. The bar in the margin is what shows where the voice is; "highlight" belongs
            // to the reader's own colour highlights, not to this.
            Section {
                Toggle(
                    "Show where the voice is",
                    isOn: Binding(
                        get: { store.settings.highlightSentence },
                        set: { store.settings.highlightSentence = $0 }))
                    .accessibilityIdentifier("highlightSentence")
            } footer: {
                Text("A bar in the margin follows the voice")
            }
            .listRowBackground(Color(theme.fillStrong))
            // Settings are for choosing, not doing. The Mac's Read aloud tab has no Start button,
            // and since Read opens paused this one only opened a paused bar behind the sheet.
            VoiceList(theme: theme)
        }
        .navigationTitle("Read aloud")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { speaker.stopAudition() }
    }
}

private struct ThemeSwatch: View {
    let appearance: Appearance
    let selected: Bool
    let accent: Theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    if appearance == .system {
                        HStack(spacing: 0) {
                            Color(Theme.light.paper)
                            Color(Theme.dark.paper)
                        }
                    } else {
                        Color(Theme.named(appearance.resolved(.light)).paper)
                    }
                    Text("Aa")
                        .font(.reading(17))
                        .foregroundStyle(appearance == .system ? Color.gray : Color(Theme.named(appearance.resolved(.light)).ink))
                }
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? Color(accent.accent) : Color(accent.border), lineWidth: selected ? 2.5 : 1)
                }
                Text(appearance.label)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color(accent.accent) : .secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(appearance.label) theme")
        .accessibilityIdentifier("\(appearance.label) theme")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Writes the export to a file and offers it to share or save.
private struct ExportButton: View {
    @Environment(Store.self) private var store
    let title: String
    let format: ExportFormat
    let file: String
    @State private var url: URL?

    var body: some View {
        Group {
            if let url {
                ShareLink(item: url) { Label(title, systemImage: "square.and.arrow.up") }
            } else {
                Label(title, systemImage: "square.and.arrow.up").foregroundStyle(.secondary)
            }
        }
        .task {
            guard let text = store.export(format) else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file)
            if (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil { self.url = url }
        }
    }
}
