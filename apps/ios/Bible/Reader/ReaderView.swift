import ObjectiveC
import UIKit

@MainActor
protocol ReaderViewDelegate: AnyObject {
    /// The verse at the reading line changed.
    func reader(_ reader: ReaderView, didReach chapter: Int, verse: Int)
    func reader(_ reader: ReaderView, didTapVerse verse: Int, inChapter chapter: Int)
    func reader(_ reader: ReaderView, didTapNoteOf verse: Int, inChapter chapter: Int)
    /// A tap away from any verse.
    func readerDidTapPage(_ reader: ReaderView)
    /// A word held down on the page, and the verse it belongs to.
    func reader(_ reader: ReaderView, didLookUp word: String, inChapter chapter: Int, verse: Int)
    /// The reader is scrolling on through the text (`true`) or back.
    func reader(_ reader: ReaderView, isReadingOn: Bool)
}

/// Verses picked in one chapter.
struct VerseSelection: Equatable {
    var chapter: Int
    var verses: Set<Int>
}

/// Where the reader gets a chapter's text (in the current translation and options) and its
/// highlights, notes and bookmarks. Called off the main thread too.
struct ChapterSource: Sendable {
    let content: @Sendable (Int) -> ChapterContent
    let marks: @Sendable (Int) -> [VerseMarks]

    func marksByVerse(_ index: Int) -> [Int: VerseMarks] {
        Dictionary(marks(index).map { (Int($0.verse), $0) }, uniquingKeysWith: { a, _ in a })
    }

    static func typeset(_ source: ChapterSource?, _ index: Int, _ style: Typography) -> ChapterLayout {
        let content = source?.content(index) ?? ChapterContent(
            index: UInt16(index), book: 0, chapter: 1, status: .missing, bookName: "", bookTitle: "", blocks: [])
        let layout = ChapterLayout(content: content, typography: style)
        layout.marks = source?.marksByVerse(index) ?? [:]
        return layout
    }
}

/// The reader: the whole Bible as one continuous scroll. It keeps a window of typeset chapters
/// around what's on screen, adding chapters as they come near and dropping those far away, and
/// moves the content (with the offset) when it adds or drops above, so scrolling never ends
/// until Genesis 1 or Revelation 22. Text is drawn into fixed-height tiles, so only what's on
/// screen is ever drawn.
final class ReaderView: UIScrollView, UIScrollViewDelegate {
    weak var readerDelegate: ReaderViewDelegate?

    /// The page tap's delegate. Deliberately not the reader itself: a UIScrollView is the delegate of
    /// its own pan recogniser, so any UIGestureRecognizerDelegate method implemented on the reader
    /// would also govern scrolling. That is exactly how the freeze happened: refusing touches while
    /// decelerating refused them to the scroll view's own pan too, leaving it stuck dragging and
    /// decelerating with the pan at .possible.
    private let tapGate = TapGate()

    /// The press-and-hold's delegate. Its own object for the same reason as the tap's: a
    /// UIScrollView is the delegate of its own pan, so a gesture delegate method on the reader
    /// would govern scrolling too. That mistake froze the page once already.
    private let pressGate = PressGate()

    var source: ChapterSource?

    /// Distance from the top of the view to the line the reading position is read at (just
    /// under the toolbar).
    var readingLine: CGFloat = 100 {
        didSet {
            guard readingLine != oldValue else { return }
            contentInset.top = readingLine
        }
    }

    var selection: VerseSelection? {
        didSet {
            guard selection != oldValue else { return }
            redrawTiles()
            // The page held still for the verse menu; once it closes, it catches up with the voice.
            if selection == nil { followVoice() }
        }
    }

    /// The verse Read Aloud is saying, or `nil`. Kept to whole-chapter comparison below, so a verse
    /// number from another chapter cannot tint the page you are looking at.
    var speaking: Int? {
        didSet {
            if speaking != oldValue { redrawTiles() }
        }
    }

    /// The word whose card is open, tinted so the reader can see what is being explained.
    var lookedUp: (chapter: Int, range: NSRange)? {
        didSet {
            if lookedUp?.range != oldValue?.range || lookedUp?.chapter != oldValue?.chapter {
                redrawTiles()
                if lookedUp == nil { followVoice() }
            }
        }
    }

    /// Where the voice is while it is sounding, for the page to follow; `nil` when nothing is being
    /// said, paused included. The Mac's `Listen::following`.
    var voice: VoicePosition? {
        didSet {
            if voice != oldValue { followVoice() }
        }
    }

    /// When the reader last moved the page themselves. For `FollowTheVoice.yield` after it, the page
    /// is theirs.
    private var userScrolledAt = Date.distantPast

    private(set) var theme = Theme.light
    private var style: Typography?
    private var sourceKey: AnyHashable?

    private struct Placed {
        let layout: ChapterLayout
        var y: CGFloat
        var maxY: CGFloat { y + layout.height }
    }

    private var placed: [Placed] = []
    private var pendingJump: (chapter: Int, verse: Int, animated: Bool, flash: Bool)?
    private var reported: (chapter: Int, verse: Int)?
    private var lastOffset: CGFloat = 0
    private var travel: CGFloat = 0
    private var accessibilityCache: [UIAccessibilityElement]?

    /// The chapter the accessibility tree was built around, so it can follow the page as it moves.
    /// A chapter number, not a position in `placed`: prepending and pruning shift the positions while
    /// the page stays on the same chapter.
    private var accessibilityAnchor: Int?

    private let tileHeight: CGFloat = 256
    private var tileOrigin: CGFloat = 0
    #if DEBUG
        /// Layout passes and refused shifts, so the trail shows churn rather than guessing at it.
        private(set) var fillPasses = 0
        private(set) var shiftRefusals = 0
        /// Writes to the scroll view's own state, and reparenting, which can cancel a gesture.
        private(set) var offsetWrites = 0
        private(set) var insetWrites = 0
        private(set) var sizeWrites = 0
        private(set) var enableWrites = 0
        private(set) var windowMoves = 0
    #endif
    private var tiles: [Int: Tile] = [:]
    private var spareTiles: [Tile] = []

    /// Typesetting a chapter takes a few milliseconds, enough to drop a frame mid-fling, so the
    /// chapter beyond each end of the window is typeset here before it's needed.
    private let typesetQueue = DispatchQueue(label: "au.com.onyxit.lamplit.dev.typeset", qos: .userInitiated)
    private var ahead: [Int: ChapterLayout] = [:]
    private var queued: Set<Int> = []
    /// Bumped when text, type or marks change, so work queued before is thrown away.
    private var generation = 0

    static let chapterCount = 1189

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        contentInsetAdjustmentBehavior = .never
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        alwaysBounceVertical = true
        scrollsToTop = true
        decelerationRate = .normal
        contentInset = UIEdgeInsets(top: readingLine, left: 0, bottom: 0, right: 0)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tapGate.reader = self
        tap.delegate = tapGate
        addGestureRecognizer(tap)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
        press.minimumPressDuration = 0.45
        pressGate.reader = self
        press.delegate = pressGate
        addGestureRecognizer(press)
        isAccessibilityElement = false
        #if DEBUG
            panGestureRecognizer.addTarget(self, action: #selector(panStateChanged(_:)))
            // A UIScrollView is the delegate of its own pan, so any gesture delegate method defined
            // on this class also governs scrolling — that is what let tap logic refuse the scroll
            // view's own touches and froze the page. `class_copyMethodList` lists only what this
            // class defines, not what it inherits, so this fires only if someone puts one back.
            var methodCount: UInt32 = 0
            if let methods = class_copyMethodList(ReaderView.self, &methodCount) {
                defer { free(methods) }
                for index in 0..<Int(methodCount) {
                    let name = NSStringFromSelector(method_getName(methods[index]))
                    assert(
                        !name.hasPrefix("gestureRecognizer:"),
                        "ReaderView defines \(name). It is its own pan's delegate, so this would govern scrolling too. Put tap logic in TapGate."
                    )
                }
            }
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    #if DEBUG
        /// Every state the pan goes through. A jump back to `.possible` mid-drag is the freeze.
        @objc private func panStateChanged(_ gesture: UIGestureRecognizer) {
            let name: String
            switch gesture.state {
            case .possible: name = "possible"
            case .began: name = "began"
            case .changed: name = "changed"
            case .ended: name = "ended"
            case .cancelled: name = "cancelled"
            case .failed: name = "failed"
            @unknown default: name = "unknown"
            }
            Breadcrumbs.mark("pan \(name) offset=\(Int(contentOffset.y))")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            windowMoves += 1
            Breadcrumbs.mark("moved to window (\(window == nil ? "gone" : "in"))")
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            Breadcrumbs.mark("touches cancelled")
            super.touchesCancelled(touches, with: event)
        }

        override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
            offsetWrites += 1
            if animated { Breadcrumbs.mark("setContentOffset(animated) to \(Int(contentOffset.y))") }
            super.setContentOffset(contentOffset, animated: animated)
        }

        override var contentInset: UIEdgeInsets {
            didSet {
                insetWrites += 1
                if contentInset != oldValue { Breadcrumbs.mark("contentInset \(Int(oldValue.top)) -> \(Int(contentInset.top))") }
            }
        }

        override var contentSize: CGSize {
            didSet { sizeWrites += 1 }
        }

        override var isScrollEnabled: Bool {
            didSet {
                enableWrites += 1
                if isScrollEnabled != oldValue { Breadcrumbs.mark("isScrollEnabled = \(isScrollEnabled)") }
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            Breadcrumbs.mark("drag began")
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            Breadcrumbs.mark("drag ended, willDecelerate=\(decelerate)")
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            Breadcrumbs.mark("deceleration ended offset=\(Int(contentOffset.y))")
        }

    #endif

    // MARK: Configuration

    /// Sets the type and the text source (`key` changes with the translation or content
    /// options). Changing either typesets everything again, keeping the reading position.
    func configure(style: Typography, theme: Theme, key: AnyHashable) {
        let themeChanged = theme != self.theme
        self.theme = theme
        backgroundColor = theme.paper
        if style != self.style || key != sourceKey {
            self.style = style
            sourceKey = key
            discardAhead()
            relayout()
        } else if themeChanged {
            for tile in tiles.values { tile.backgroundColor = theme.paper }
            redrawTiles()
        }
    }

    func jump(to chapter: Int, verse: Int, animated: Bool, flash: Bool) {
        pendingJump = (chapter, verse, animated, flash)
        setNeedsLayout()
    }

    /// Reads highlights, notes and bookmarks again and redraws.
    func reloadMarks() {
        discardAhead()
        for p in placed { p.layout.marks = source?.marksByVerse(p.layout.index) ?? [:] }
        accessibilityCache = nil
        redrawTiles()
    }

    // MARK: Layout

    private var effectiveStyle: Typography? {
        guard var s = style, bounds.width > 0 else { return nil }
        s.width = bounds.width
        s.safeLeft = safeAreaInsets.left
        s.safeRight = safeAreaInsets.right
        return s
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let style = effectiveStyle else { return }
        if let first = placed.first, first.layout.typography != style {
            relayout()
            return
        }
        if let jump = pendingJump {
            pendingJump = nil
            perform(jump, style: style)
        }
        if placed.isEmpty { return }
        fill(style)
        // Last line of defence: the visible page must sit inside the strip. If it ever does not,
        // nothing draws and dragging goes nowhere — a frozen page over a reading that carries on.
        if let last = placed.last, contentOffset.y > last.maxY {
            reset(around: last.layout.index, style: style)
            contentOffset.y = 0
            fill(style)
        }
        updateTiles()
        report()
        typesetAhead(style)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    private func perform(_ jump: (chapter: Int, verse: Int, animated: Bool, flash: Bool), style: Typography) {
        let chapter = min(max(jump.chapter, 0), Self.chapterCount - 1)
        if jump.animated, let p = placed.first(where: { $0.layout.index == chapter }) {
            let target = offset(for: p, verse: jump.verse)
            if abs(target - contentOffset.y) < bounds.height * 3 {
                setContentOffset(CGPoint(x: 0, y: target), animated: true)
                if jump.flash { flash(chapter: chapter, verse: jump.verse) }
                return
            }
        }
        reset(around: chapter, style: style)
        guard let p = placed.first else { return }
        contentOffset = CGPoint(x: 0, y: offset(for: p, verse: jump.verse))
        fill(style)
        if jump.flash { flash(chapter: chapter, verse: jump.verse) }
        // A move to another chapter is a layout change worth announcing; scrolling is not.
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    /// The offset that puts a verse (or the chapter's head, for verse 1) at the reading line.
    private func offset(for p: Placed, verse: Int) -> CGFloat {
        if verse > 1, let top = p.layout.top(of: verse) {
            return p.y + top - readingLine - p.layout.typography.s(12)
        }
        return p.y - readingLine
    }

    /// Typesets again (new type, translation or width), keeping the verse at the reading line
    /// where it was.
    private func relayout() {
        guard let style = effectiveStyle, !placed.isEmpty, let anchor = readingPosition() else { return }
        reset(around: anchor.chapter, style: style)
        guard let p = placed.first else { return }
        let top = p.layout.top(of: anchor.verse) ?? 0
        contentOffset = CGPoint(x: 0, y: p.y + top + anchor.lines * style.lineHeight - readingLine)
        fill(style)
        updateTiles()
    }

    private func reset(around chapter: Int, style: Typography) {
        for tile in tiles.values { recycle(tile) }
        tiles.removeAll()
        placed = [Placed(layout: typeset(chapter, style), y: 0)]
        tileOrigin = 0
        contentSize = CGSize(width: bounds.width, height: placed[0].maxY)
        accessibilityCache = nil
        reported = nil
    }

    private func typeset(_ index: Int, _ style: Typography) -> ChapterLayout {
        if let layout = ahead.removeValue(forKey: index), layout.typography == style { return layout }
        return ChapterSource.typeset(source, index, style)
    }

    /// Queues the chapters just past each end of the window.
    private func typesetAhead(_ style: Typography) {
        guard let first = placed.first?.layout.index, let last = placed.last?.layout.index else { return }
        let wanted = [last + 1, first - 1].filter { (0..<Self.chapterCount).contains($0) }
        ahead = ahead.filter { wanted.contains($0.key) }
        for index in wanted where ahead[index] == nil && !queued.contains(index) {
            queued.insert(index)
            let (source, generation) = (source, generation)
            typesetQueue.async { [weak self] in
                let layout = ChapterSource.typeset(source, index, style)
                DispatchQueue.main.async {
                    guard let self, generation == self.generation else { return }
                    self.queued.remove(index)
                    self.ahead[index] = layout
                }
            }
        }
    }

    private func discardAhead() {
        generation += 1
        ahead.removeAll()
        queued.removeAll()
    }

    /// Adds chapters within a screen and a half of the visible area and drops those beyond four.
    private func fill(_ style: Typography) {
        let height = max(bounds.height, 1)
        let ahead = height * 1.5
        let keep = height * 4
        var changed = false
        #if DEBUG
            fillPasses += 1
        #endif
        while let last = placed.last, last.maxY < contentOffset.y + height + ahead,
            last.layout.index + 1 < Self.chapterCount
        {
            placed.append(Placed(layout: typeset(last.layout.index + 1, style), y: last.maxY))
            changed = true
        }
        while let first = placed.first, first.y > contentOffset.y - ahead, first.layout.index > 0 {
            let layout = typeset(first.layout.index - 1, style)
            guard shift(by: layout.height) else {
                #if DEBUG
                    // The prefetched layout has already been taken out of `ahead` by typeset(), so a
                    // refusal here costs a synchronous re-typeset on the next layout pass.
                    shiftRefusals += 1
                #endif
                break
            }
            placed.insert(Placed(layout: layout, y: 0), at: 0)
            changed = true
        }
        while placed.count > 1, let last = placed.last, last.y > contentOffset.y + height + keep {
            placed.removeLast()
            changed = true
        }
        while placed.count > 1, placed[0].maxY < contentOffset.y - keep {
            let h = placed[0].layout.height
            guard shift(by: -h) else { break }
            placed.removeFirst()
            changed = true
        }
        if changed {
            contentSize = CGSize(width: bounds.width, height: placed.last?.maxY ?? 0)
            accessibilityCache = nil
        }
    }

    /// Moves everything by `dy` (down if positive) without anything moving on screen.
    ///
    /// The scroll view clamps its own offset to the content it had when the offset was set, so the
    /// strip and the page can end up disagreeing — the offset moves by less than `placed` did and
    /// the visible area falls into a gap thousands of points from the nearest verse, which reads as
    /// a frozen page. So the offset is clamped here first and the strip is moved by what the scroll
    /// view actually allowed. `false` means there was no room, and the caller must not insert.
    @discardableResult
    private func shift(by dy: CGFloat) -> Bool {
        let room = max(0, contentSize.height + dy - bounds.height)
        let target = min(max(contentOffset.y + dy, 0), room)
        let applied = target - contentOffset.y
        guard abs(applied - dy) < 0.5 else { return false }
        for i in placed.indices { placed[i].y += applied }
        tileOrigin += applied
        for tile in tiles.values { tile.frame.origin.y += applied }
        for layer in flashLayers { layer.position.y += applied }
        contentSize.height += applied
        contentOffset.y = target
        lastOffset = target
        return true
    }

    // MARK: Tiles

    fileprivate final class Tile: UIView {
        weak var reader: ReaderView?

        override func draw(_ rect: CGRect) {
            reader?.drawTile(self, rect)
        }
    }

    private func updateTiles() {
        guard bounds.height > 0 else { return }
        let top = contentOffset.y - tileHeight
        let bottom = contentOffset.y + bounds.height + tileHeight
        let first = Int(((top - tileOrigin) / tileHeight).rounded(.down))
        let last = Int(((bottom - tileOrigin) / tileHeight).rounded(.down))
        let contentBottom = contentSize.height
        for (k, tile) in tiles where k < first || k > last {
            recycle(tile)
            tiles[k] = nil
        }
        for k in first...max(first, last) where tiles[k] == nil {
            let y = tileOrigin + CGFloat(k) * tileHeight
            guard y + tileHeight > 0, y < contentBottom else { continue }
            let tile = spareTiles.popLast() ?? makeTile()
            tile.frame = CGRect(x: 0, y: y, width: bounds.width, height: tileHeight)
            tile.backgroundColor = theme.paper
            tile.setNeedsDisplay()
            insertSubview(tile, at: 0)
            tiles[k] = tile
        }
    }

    private func makeTile() -> Tile {
        let tile = Tile()
        tile.reader = self
        tile.isOpaque = true
        tile.contentMode = .redraw
        tile.isUserInteractionEnabled = false
        return tile
    }

    private func recycle(_ tile: Tile) {
        tile.removeFromSuperview()
        if spareTiles.count < 6 { spareTiles.append(tile) }
    }

    private func redrawTiles() {
        for tile in tiles.values { tile.setNeedsDisplay() }
    }

    fileprivate func drawTile(_ tile: Tile, _ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let area = rect.offsetBy(dx: 0, dy: tile.frame.minY)
        for p in placed where p.maxY > area.minY && p.y < area.maxY {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: p.y - tile.frame.minY)
            let selected = selection?.chapter == p.layout.index ? selection?.verses ?? [] : []
            p.layout.draw(
                area.offsetBy(dx: 0, dy: -p.y),
                decorations: .init(
                    theme: theme, selected: selected, speaking: speaking,
                    lookedUp: lookedUp?.chapter == p.layout.index ? lookedUp?.range : nil))
            ctx.restoreGState()
        }
        LaunchClock.mark("First page drawn")
    }

    // MARK: Flash

    private var flashLayers: [CALayer] = []

    /// Briefly marks a verse arrived at from search or a reference.
    func flash(chapter: Int, verse: Int) {
        guard verse > 0, let p = placed.first(where: { $0.layout.index == chapter }) else { return }
        let bands = p.layout.bands(of: verse)
        guard !bands.isEmpty else { return }
        let path = UIBezierPath()
        for band in bands {
            path.append(UIBezierPath(roundedRect: band.offsetBy(dx: 0, dy: p.y), cornerRadius: p.layout.typography.s(4)))
        }
        let layer = CAShapeLayer()
        layer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
        layer.path = path.cgPath
        layer.fillColor = theme.accent.withAlphaComponent(theme.isDark ? 0.28 : 0.16).cgColor
        layer.opacity = 0
        self.layer.addSublayer(layer)
        flashLayers.append(layer)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.12, 0.55, 1]
        fade.duration = 1.8
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak layer] in
            layer?.removeFromSuperlayer()
            self?.flashLayers.removeAll { $0 === layer }
        }
        layer.add(fade, forKey: "flash")
        CATransaction.commit()
    }

    // MARK: Position

    /// The chapter and verse at the reading line, and how many lines below the verse's top the
    /// line is (negative in the chapter's head).
    private func readingPosition() -> (chapter: Int, verse: Int, lines: CGFloat)? {
        let line = contentOffset.y + readingLine
        guard let p = placed.first(where: { line < $0.maxY }) ?? placed.last else { return nil }
        let local = line - p.y
        let verse = p.layout.verse(atY: local + p.layout.typography.s(12))
        let top = p.layout.top(of: verse) ?? 0
        return (p.layout.index, verse, (local - top) / p.layout.typography.lineHeight)
    }

    private func report() {
        guard let position = readingPosition() else { return }
        if reported?.chapter != position.chapter || reported?.verse != position.verse {
            reported = (position.chapter, position.verse)
            readerDelegate?.reader(self, didReach: position.chapter, verse: position.verse)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // A finger on the page, or the fling it left behind. The page's own following is neither.
        if isTracking || isDragging || isDecelerating { userScrolledAt = Date() }
        let dy = contentOffset.y - lastOffset
        lastOffset = contentOffset.y
        // The tree covers what is on screen and one chapter either side, so it is rebuilt when a
        // different chapter comes into view rather than for every point of movement.
        if let onScreen = indexOfChapterOnScreen(),
            placed[onScreen].layout.index != accessibilityAnchor
        {
            accessibilityCache = nil
        }
        guard isDragging || isDecelerating else { return }
        if (travel >= 0) != (dy >= 0) { travel = 0 }
        travel += dy
        if contentOffset.y < -readingLine + 8 {
            readerDelegate?.reader(self, isReadingOn: false)
        } else if abs(travel) > 24 {
            readerDelegate?.reader(self, isReadingOn: travel > 0)
            travel = 0
        }
    }

    /// The status bar takes you to the top of the chapter you're in, not of the loaded window.
    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        guard let position = readingPosition(),
            let p = placed.first(where: { $0.layout.index == position.chapter })
        else { return false }
        setContentOffset(CGPoint(x: 0, y: offset(for: p, verse: 1)), animated: true)
        return false
    }

    // MARK: Following the voice

    /// The page follows the voice, as the Mac's `Reader::follow` does: it moves only when the verse
    /// being said is about to leave the comfortable part of the screen (`FollowTheVoice`), and never
    /// while the reader is using the page: while they scroll, for a while after they scroll, or while
    /// the verse menu or a word's card is open. Once the menu or the card closes, the page catches up.
    private func followVoice() {
        guard let voice, let style = effectiveStyle, !placed.isEmpty,
            selection == nil, lookedUp == nil,
            !isTracking, !isDragging, !isDecelerating,
            Date().timeIntervalSince(userScrolledAt) >= FollowTheVoice.yield
        else { return }
        guard let p = placed.first(where: { $0.layout.index == voice.chapter }),
            let verseTop = p.layout.top(of: voice.verse)
        else {
            // Not in the loaded window: the reader is more than a chapter away from the voice. As on
            // the Mac, coming back from that far is a jump, not a scroll.
            jump(to: voice.chapter, verse: voice.verse, animated: false, flash: false)
            return
        }
        let top = p.y + verseTop
        let bottom = p.y + (p.layout.bands(of: voice.verse).last?.maxY ?? verseTop + style.lineHeight)
        guard
            let move = FollowTheVoice.move(
                top: top - contentOffset.y, height: max(bottom - top, 1), toolbar: readingLine,
                viewport: bounds.height)
        else { return }
        let lowest = -adjustedContentInset.top
        let highest = max(lowest, contentSize.height + adjustedContentInset.bottom - bounds.height)
        let target = min(max(contentOffset.y + move, lowest), highest)
        guard abs(target - contentOffset.y) > 1 else { return }
        setContentOffset(CGPoint(x: 0, y: target), animated: true)
    }

    // MARK: Taps

    /// A word held down: tint it and ask for its card. One gesture, one report — the press fires on
    /// .began only, so holding on does not open card after card.
    @objc private func pressed(_ press: UILongPressGestureRecognizer) {
        guard press.state == .began else { return }
        let point = press.location(in: self)
        guard let p = placed.first(where: { point.y >= $0.y && point.y < $0.maxY }) else { return }
        let local = CGPoint(x: point.x, y: point.y - p.y)
        guard let hit = p.layout.word(at: local) else { return }
        lookedUp = (p.layout.index, hit.range)
        readerDelegate?.reader(
            self, didLookUp: hit.word, inChapter: p.layout.index,
            verse: p.layout.verse(at: local) ?? 1)
    }

    @objc private func tapped(_ tap: UITapGestureRecognizer) {
        let point = tap.location(in: self)
        guard let p = placed.first(where: { point.y >= $0.y && point.y < $0.maxY }) else {
            readerDelegate?.readerDidTapPage(self)
            return
        }
        let local = CGPoint(x: point.x, y: point.y - p.y)
        for (verse, mark) in p.layout.marks where mark.note {
            if let frame = p.layout.markerFrame(of: verse), frame.insetBy(dx: -14, dy: -14).contains(local) {
                readerDelegate?.reader(self, didTapNoteOf: verse, inChapter: p.layout.index)
                return
            }
        }
        if let verse = p.layout.verse(at: local) {
            readerDelegate?.reader(self, didTapVerse: verse, inChapter: p.layout.index)
        } else {
            readerDelegate?.readerDidTapPage(self)
        }
    }

    // MARK: Accessibility

    /// The position in `placed` of the first chapter with content on screen, or nil when nothing is
    /// placed yet. Both the tree itself and the check that keeps it following the page need this.
    private func indexOfChapterOnScreen() -> Int? {
        guard !placed.isEmpty else { return nil }
        let visible = CGRect(origin: contentOffset, size: bounds.size)
        return placed.firstIndex { $0.y < visible.maxY && $0.maxY > visible.minY } ?? 0
    }

    override var accessibilityElements: [Any]? {
        get {
            if let accessibilityCache { return accessibilityCache }
            guard let onScreen = indexOfChapterOnScreen() else {
                accessibilityCache = []
                return []
            }
            // Only the chapters on screen and one either side get elements. The strip holds a
            // window of chapters above and below the page, and building an element for every verse
            // in all of them gave VoiceOver a tree to wade through that was mostly off screen.
            let first = max(0, onScreen - 1)
            let last = min(placed.count - 1, onScreen + 1)
            accessibilityAnchor = placed[onScreen].layout.index
            var elements: [UIAccessibilityElement] = []
            for p in placed[first...last] {
                let layout = p.layout
                var chapter: [UIAccessibilityElement] = []
                for heading in layout.headingElements {
                    let e = UIAccessibilityElement(accessibilityContainer: self)
                    e.accessibilityLabel = heading.text
                    e.accessibilityTraits = .header
                    e.accessibilityFrameInContainerSpace = heading.frame.offsetBy(dx: 0, dy: p.y)
                    chapter.append(e)
                }
                for top in layout.verseTops {
                    guard let text = layout.spokenText(of: top.verse) else { continue }
                    let bands = layout.bands(of: top.verse)
                    guard let first = bands.first else { continue }
                    let e = VerseElement(accessibilityContainer: self)
                    e.reader = self
                    e.chapter = layout.index
                    e.verse = top.verse
                    let ref = VerseRef(book: layout.content.book, chapter: layout.content.chapter, verse: UInt8(top.verse))
                    let reference = rangeLabel(from: ref, to: ref)
                    // The reference is in the hint: spoken when a verse is focused, not before
                    // every verse while reading on.
                    e.accessibilityLabel = "\(top.verse). \(text)"
                    e.accessibilityHint = "\(reference). Double-tap to select."
                    e.accessibilityTraits = .staticText
                    e.accessibilityIdentifier = reference
                    e.accessibilityFrameInContainerSpace = bands.dropFirst().reduce(first) { $0.union($1) }
                        .offsetBy(dx: 0, dy: p.y)
                    chapter.append(e)
                }
                elements += chapter.sorted {
                    $0.accessibilityFrameInContainerSpace.minY < $1.accessibilityFrameInContainerSpace.minY
                }
            }
            accessibilityCache = elements
            return elements
        }
        set {}
    }

    private final class VerseElement: UIAccessibilityElement {
        weak var reader: ReaderView?
        var chapter = 0
        var verse = 0

        override func accessibilityActivate() -> Bool {
            guard let reader else { return false }
            reader.readerDelegate?.reader(reader, didTapVerse: verse, inChapter: chapter)
            return true
        }
    }
}

/// Decides whether the page's tap may see a touch. Only the tap: it is never the delegate of the
/// scroll view's own gesture recognisers.
@MainActor
/// Lets the press-and-hold share touches with everything else. A long press fails by itself as soon
/// as the finger moves, so scrolling is never held up — this only makes sure of it.
private final class PressGate: NSObject, UIGestureRecognizerDelegate {
    weak var reader: UIScrollView?

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        // A hold shares touches with scrolling, and with nothing else. Sharing with the tap let it
        // fire when the held finger lifted, selecting the verse behind the card.
        other === reader?.panGestureRecognizer
    }
}

private final class TapGate: NSObject, UIGestureRecognizerDelegate {
    weak var reader: UIScrollView?

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // A tap that stops a fling only stops it.
        !(reader?.isDecelerating ?? false)
    }
}

#if DEBUG
extension ReaderView {
    /// The live state of the reader as one line, for the debugger and the breadcrumb trail.
    ///
    /// Debug builds only: a release build does not compile this. Everything here is read-only — it
    /// exists to answer "where does the reader think it is?" while the page refuses to move.
    func debugState() -> String {
        func n(_ v: CGFloat) -> String { String(format: "%.1f", v) }
        let pan: String
        switch panGestureRecognizer.state {
        case .possible: pan = "possible"
        case .began: pan = "began"
        case .changed: pan = "changed"
        case .ended: pan = "ended"
        case .cancelled: pan = "cancelled"
        case .failed: pan = "failed"
        @unknown default: pan = "unknown"
        }
        let chapters = placed.map { "\($0.layout.index)@\(n($0.y))..\(n($0.maxY))" }
            .joined(separator: ",")
        let tileText = tiles.keys.sorted().map { key in
            let frame = tiles[key]?.frame ?? .zero
            return "\(key)@\(n(frame.origin.y))+\(n(frame.height))"
        }.joined(separator: ",")
        let jump = pendingJump.map { "\($0.chapter):\($0.verse)" } ?? "none"
        return """
        reader bounds=\(n(bounds.width))x\(n(bounds.height)) offset=\(n(contentOffset.y)) \
        size=\(n(contentSize.height)) insetTop=\(n(contentInset.top)) tracking=\(isTracking) \
        dragging=\(isDragging) decelerating=\(isDecelerating) enabled=\(isScrollEnabled) \
        pan=\(pan) tileOrigin=\(n(tileOrigin)) placed=[\(chapters)] tiles=[\(tileText)] jump=\(jump) \
        fillPasses=\(fillPasses) refusedShifts=\(shiftRefusals) ahead=\(ahead.keys.sorted()) \
        writes=offset\(offsetWrites)/inset\(insetWrites)/size\(sizeWrites)/enable\(enableWrites) \
        windowMoves=\(windowMoves)
        """
    }
}
#endif
