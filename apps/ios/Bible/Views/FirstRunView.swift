import SwiftUI

/// The one screen a new reader sees: which translation, how the page looks, and then out of the way.
///
/// One screen rather than the Mac's three, but the same three questions and the same setting the Mac
/// keeps, so nothing here is a second source of truth. Everything it sets stays changeable in
/// Settings, and the choices save through `ReaderSettings` like every other preference.
///
/// It has to hold up at the largest Dynamic Type sizes and under VoiceOver: the whole screen
/// scrolls, nothing is laid out at a fixed height, and each appearance card carries its own label
/// and selected state rather than relying on the colour it shows.
struct FirstRunView: View {
    @Environment(Store.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    /// The appearance being previewed. Automatic follows the phone, so it previews what that means
    /// right now rather than a colour of its own.
    private var chosen: Appearance { store.settings.appearance }
    private var theme: Theme { Theme.named(chosen.resolved(scheme)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                heading
                translation
                appearance
                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .padding(.bottom, 32)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(theme.paper).ignoresSafeArea())
        .scrollBounceBehavior(.basedOnSize)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lamplit")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Color(theme.ink))
                .accessibilityAddTraits(.isHeader)
            // Left-aligned like the heading, and never truncated: if it wraps, the second line
            // sits under the first, not centred beneath a left-aligned title.
            Text("Read, search and listen, entirely offline.")
                .font(.body)
                .foregroundStyle(Color(theme.ink))
                .fixedSize(horizontal: false, vertical: true)
            Text("Choose how you read.")
                .font(.body)
                .foregroundStyle(Color(theme.ink2))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Translation

    /// A few common translations and a "More…" for the rest: seven in one list is a longer decision
    /// than the first screen should ask for, and the ones left behind are a tap away in Settings.
    private var translation: some View {
        @Bindable var store = store
        let common = ["kjv", "bsb", "web", "asv"]
        let first = store.translations.filter { common.contains($0.id) }
        let rest = store.translations.filter { !common.contains($0.id) }
        let now = store.translations.first { $0.id == store.settings.translation }
        return VStack(alignment: .leading, spacing: 10) {
            label("Translation")
            Menu {
                ForEach(first, id: \.id) { t in
                    Button("\(t.abbrev) — \(t.name)") { store.settings.translation = t.id }
                }
                if !rest.isEmpty {
                    Menu("More…") {
                        ForEach(rest, id: \.id) { t in
                            Button("\(t.abbrev) — \(t.name)") { store.settings.translation = t.id }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(now.map { "\($0.abbrev) — \($0.name)" } ?? "Choose a translation")
                        .foregroundStyle(Color(theme.ink))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(theme.ink3))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(theme.paper))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(theme.border), lineWidth: 1)
                )
            }
            .accessibilityLabel("Translation")
            .accessibilityValue(now?.name ?? "")
            .accessibilityIdentifier("translationMenu")
        }
    }

    // MARK: Appearance

    private var appearance: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 10) {
            label("Appearance")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 12) {
                ForEach(Appearance.allCases) { option in
                    AppearanceCard(
                        option: option, chosen: chosen == option, scheme: scheme
                    ) {
                        store.settings.appearance = option
                    }
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                store.settings.didFirstRun = true
                dismiss()
            } label: {
                Text("Start reading")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(theme.accent))
            .accessibilityHint("Opens the reader")

            Text("You can change these any time in Settings.")
                .font(.footnote)
                .foregroundStyle(Color(theme.ink2))
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(theme.ink2))
            .accessibilityAddTraits(.isHeader)
    }
}

/// One appearance, shown as a little page in that palette. The card is drawn from the same `Theme`
/// the reader uses, so a preview can never promise a colour the reader does not have.
private struct AppearanceCard: View {
    let option: Appearance
    let chosen: Bool
    let scheme: ColorScheme
    let pick: () -> Void

    private var theme: Theme { Theme.named(option.resolved(scheme)) }

    var body: some View {
        Button(action: pick) {
            VStack(spacing: 8) {
                page
                Text(option.label)
                    .font(.footnote)
                    .foregroundStyle(Color(theme.ink2))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.label)
        .accessibilityValue(chosen ? "Selected" : "")
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Uses the \(option.label.lowercased()) page")
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Three lines of "text" and a rubric line above them: enough to read the palette at a
            // glance, small enough that it stays a preview rather than a decoration.
            Rectangle().fill(Color(theme.rubric)).frame(width: 26, height: 3)
            ForEach(0..<3, id: \.self) { i in
                Rectangle()
                    .fill(Color(theme.ink).opacity(i == 2 ? 0.45 : 0.75))
                    .frame(width: i == 2 ? 34 : 56, height: 4)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 64)
        .background(Color(theme.paper))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color(theme.border), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(chosen ? Color(theme.accent) : .clear, lineWidth: 2)
        )
    }
}
