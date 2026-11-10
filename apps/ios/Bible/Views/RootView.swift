import SwiftUI
import UIKit

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicType

    /// The toolbar's own height: 4 pt of padding above a 44 pt control, as `TopBar` draws it. The
    /// paper behind the bars is solid to this line and fades from it.
    private static let toolbarHeight: CGFloat = 48

    var body: some View {
        @Bindable var store = store
        let theme = Theme.named(store.settings.appearance.resolved(scheme))
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            ZStack(alignment: .top) {
                ReaderContainer(
                    store: store, theme: theme, style: typography(theme), translation: store.settings.translation,
                    readingLine: safeTop + 60, selection: store.selection, speaking: store.speakingVerses,
                    voice: store.followingVoice,
                    marksVersion: store.marksVersion,
                    jump: store.jump
                )
                .overlay(alignment: .top) {
                    // The paper under the status bar and the toolbar. Solid behind the toolbar
                    // itself, so no verse shows between or around the buttons, and the fade starts
                    // at the toolbar's bottom edge — same fade length, same toolbar height as
                    // before. With the bars away there is nothing to back, so it keeps the short
                    // band it always had.
                    VStack(spacing: 0) {
                        Color(theme.paper)
                            .frame(height: store.barsHidden ? (safeTop + 28) * 0.55 : safeTop + Self.toolbarHeight)
                        LinearGradient(
                            colors: [Color(theme.paper), Color(theme.paper).opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: (safeTop + 28) * 0.45)
                    }
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
                }
                .ignoresSafeArea()

                TopBar(theme: theme)
                    .padding(.top, 4)
                    .offset(y: store.barsHidden ? -(safeTop + 72) : 0)
                    .opacity(store.barsHidden ? 0 : 1)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 10) {
                    if let toast = store.toast {
                        Text(toast)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .solidCard(in: Capsule(), theme: theme)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if store.selection != nil {
                        SelectionBar(theme: theme)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    // The bar is last, so nothing that opens below it can push it up. The verse menu
                    // used to sit under it and lift it, which put the bar's stop button exactly
                    // where a thumb looks for the menu's close button.
                    //
                    // It stays for as long as the reading is open, whichever way the page is
                    // scrolled: the toolbar and status bar may hide for a full page of text, but the
                    // thing reading to you may not.
                    if store.speaker.phase.isOn {
                        ListeningBar(theme: theme)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        // The bar belongs at the bottom of the page, and a sheet with a keyboard covers it rather
        // than the bar riding up over the sheet's own controls. This has to be on the outermost view:
        // the keyboard shrinks the GeometryReader and its overlay rises with it, whatever the content
        // inside says. Nothing on the root needs keyboard avoidance — the reference field is in the
        // top bar.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.smooth(duration: 0.28), value: store.barsHidden)
        .animation(.smooth(duration: 0.28), value: store.selection != nil)
        .animation(.smooth(duration: 0.28), value: store.toast)
        .statusBarHidden(store.barsHidden)
        .preferredColorScheme(preferredScheme)
        .tint(Color(theme.accent))
        .sensoryFeedback(.selection, trigger: store.selection)
        .sheet(item: $store.sheet) { sheet in
            Group {
                switch sheet {
                case .books: BookPicker(theme: theme)
                case .search: SearchView(theme: theme)
                case .settings: SettingsView(theme: theme)
                case .study: StudyView(theme: theme)
                case .related: RelatedSheet(ref: verseAnchor, theme: theme)
                case .words: WordsSheet(ref: verseAnchor, theme: theme)
                case .voiceChooser: VoiceChooserSheet(theme: theme)
                case .note(let ref): NoteEditor(ref: ref, theme: theme)
                case .lookup(let look): LookupCard(lookup: look, theme: theme)
                }
            }
            .environment(store)
            .sheetChrome(theme)
        }
        // A first launch is asked once, on its own, before the page is reachable at all. The binding
        // writes the answer back through the settings the reader already saves.
        .fullScreenCover(isPresented: firstRun) { FirstRunView().environment(store) }
    }

    private var firstRun: Binding<Bool> {
        Binding(
            get: { !store.settings.didFirstRun },
            set: { showing in if !showing { store.settings.didFirstRun = true } }
        )
    }

    /// The verse a look-up sheet speaks about: the one tapped, or where the page is standing.
    private var verseAnchor: VerseRef {
        store.selectionRef ?? store.ref(chapter: store.position.chapter, verse: store.position.verse)
    }

    private var preferredScheme: ColorScheme? {
        switch store.settings.appearance {
        case .system: nil
        case .light, .sepia: .light
        case .dark: .dark
        }
    }

    /// The reading size follows Dynamic Type: the setting is the size at the default text size.
    private func typography(_ theme: Theme) -> Typography {
        let s = store.settings
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicType))
        let size = UIFontMetrics(forTextStyle: .body).scaledValue(for: CGFloat(s.textSize), compatibleWith: traits)
        return Typography(
            size: min(size, 44).rounded(), lineSpacing: CGFloat(s.lineSpacing), redLetters: s.redLetters,
            options: store.contentOptions, theme: theme.name, width: 0)
    }
}

/// The reference, translation and tools over the top of the page.
struct TopBar: View {
    @Environment(Store.self) private var store
    let theme: Theme

    @State private var topWidth: CGFloat = 0
    @State private var toolsWidth: CGFloat = 0
    @State private var badgeWidth: CGFloat = 0

    /// This view's own numbers, named once: the reference's leading and trailing padding, the
    /// separator between it and the badge, and the outer stack's spacing.
    private static let refLeading: CGFloat = 16
    private static let refTrailing: CGFloat = 10
    private static let ruleWidth: CGFloat = 1
    private static let stackSpacing: CGFloat = 10

    /// What the reference's text may use.
    private var room: CGFloat {
        topWidth - toolsWidth - badgeWidth - Self.ruleWidth
            - Self.refLeading - Self.refTrailing - Self.stackSpacing * 2
    }

    /// The full name if it fits, otherwise the short form. Deterministic: ViewThatFits was never
    /// offered the width that was really there, so in landscape it chose the short form with room
    /// to spare.
    private var placeText: String {
        let place = store.placeTitle
        guard room > 0 else { return place.short }
        return Self.width(of: place.full) <= room ? place.full : place.short
    }

    /// The width this text takes in the font the label draws it in, Dynamic Type included.
    private static func width(of text: String) -> CGFloat {
        let base = UIFont.preferredFont(forTextStyle: .subheadline)
        let font = UIFont.systemFont(ofSize: base.pointSize, weight: .semibold)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    var body: some View {
        let place = store.placeTitle
        return HStack(spacing: 10) {
            HStack(spacing: 0) {
                Button {
                    store.sheet = .books
                } label: {
                    // The full name if it fits, otherwise the short form: the chapter is never
                    // dropped, because where you are is the point of the control.
                    // Each child measures its own natural width, so ViewThatFits picks the first
                    // that fits the width actually offered. fixedSize on the container instead
                    // handed it an unlimited proposal, which made the full name always "fit".
                    Text(placeText)
                    // The badge's own style, one step down from .headline, so the pill reads as one
                    // control and a narrow phone gives the reference back a character's room.
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.leading, 16)
                    .padding(.trailing, 10)
                    .frame(minHeight: 44)
                }
                // VoiceOver says the whole name: it should never read "Matt".
                .accessibilityLabel("\(place.full). Choose a book and chapter")
                .accessibilityIdentifier("reference")

                Rectangle()
                    .fill(Color(theme.separator))
                    .frame(width: 1, height: 20)

                Menu {
                    Picker("Translation", selection: Binding(
                        get: { store.settings.translation },
                        set: { store.settings.translation = $0 }
                    )) {
                        ForEach(store.translations, id: \.id) { t in
                            Text("\(t.abbrev) · \(t.name)").tag(t.id)
                        }
                    }
                } label: {
                    Text(store.translation?.abbrev ?? "")
                        .font(.subheadline.weight(.semibold))
                        // A badge that wraps is not a badge: KJV must stay on one line.
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.leading, 10)
                        .padding(.trailing, 16)
                        // Measured after its own padding: the badge's padding is room the reference
                        // cannot have, and leaving it out let the label claim 26 pt it did not own.
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { badgeWidth = $0 }
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Translation: \(store.translation?.name ?? "")")
                .accessibilityIdentifier("translation")
            }
            .foregroundStyle(Color(theme.ink))
            // Offered its room before the Spacer takes any of it, so a narrow phone gives the
            // reference every point there is rather than a share.
            .layoutPriority(1)
            .glass(in: Capsule(), theme: theme)

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                listenTool
                tool("magnifyingglass", "Search", id: "search") { store.sheet = .search }
                tool("gearshape", "Settings", id: "settings") { store.sheet = .settings }
                tool("bookmark", "Bookmarks, highlights and notes", id: "study") { store.sheet = .study }
            }
            .padding(.horizontal, 4)
            // The four tools keep their room; the reference takes what is left.
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { toolsWidth = $0 }
            .glass(in: Capsule(), theme: theme)
        }
        // Measured before the outer padding, so the 32 pt the page insets take are not counted as
        // room. With the padding on, `topWidth` was the full width and the reference claimed those
        // 32 pt too — with the badge's 26, that is the 58 pt that squeezed "Matthew 23" to "Matthe…".
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { topWidth = $0 }
        .padding(.horizontal, 16)
    }

    /// Read Aloud: one button that starts and stops, and opens its own panel on a long press.
    @ViewBuilder
    private var listenTool: some View {
        let phase = store.speaker.phase
        // The Mac's speaker, coloured while it is reading and never filled.
        let symbol = phase.isOn ? "speaker.wave.2" : "speaker"
        Button {
            store.toggleReading()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(phase.isOn ? Color(theme.accent) : Color(theme.ink))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(phase.isOn ? "Stop reading aloud" : "Read aloud")
        .accessibilityIdentifier("listen")
    }

    private func tool(_ symbol: String, _ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .foregroundStyle(Color(theme.ink))
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}
