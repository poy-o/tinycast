import AppKit
import QuartzCore

/// Renders fading hover-trail pills behind palette list rows using Core Animation.
@MainActor
final class HoverTrailController {
    private weak var panel: PalettePanel?
    private let rows = NSHashTable<HoverTrailRowView>.weakObjects()
    private let observedClipViews = NSHashTable<NSClipView>.weakObjects()
    private var clipObservers: [NotificationToken] = []
    private weak var activeDocView: NSView?
    private weak var previousRow: HoverTrailRowView?
    private var previousDocPoint: CGPoint?
    private var trackingArea: NSTrackingArea?
    private weak var trackedContentView: NSView?
    private var trackingProxy: TrackingProxy?

    func attach(to panel: PalettePanel) {
        self.panel = panel
    }

    func register(_ row: HoverTrailRowView) {
        rows.add(row)
    }

    func unregister(_ row: HoverTrailRowView) {
        rows.remove(row)
        if previousRow === row { previousRow = nil }
    }

    func cancelTrail(for row: HoverTrailRowView) {
        if previousRow === row { previousRow = nil }
        guard let docView = row.enclosingScrollView?.documentView,
            let canvas = canvasView(for: docView, create: false)
        else { return }
        canvas.cancelPill(for: row.convert(row.bounds, to: canvas))
    }

    func handleMouseMoved(_ event: NSEvent, armed: Bool) {
        guard let panel, panel.isVisible, panel.frame.height >= 120 else {
            clearImmediate()
            return
        }
        guard armed else { return }
        ensureTrackingArea(in: panel)

        let windowPoint = event.locationInWindow
        guard let scrollView = scrollView(at: windowPoint, in: panel),
            let docView = scrollView.documentView
        else {
            handlePointerLeave(animated: true)
            return
        }

        observeClipViewIfNeeded(scrollView.contentView)
        if let activeDocView, activeDocView !== docView {
            handlePointerLeave(animated: true)
        }
        activeDocView = docView

        guard visibleViewport(of: scrollView, in: panel).contains(windowPoint) else {
            handlePointerLeave(animated: true)
            return
        }

        let currentPoint = docView.convert(windowPoint, from: nil)
        let mounted = mountedRows(in: docView, panel: panel)
        let samples = HoverTrailPath.samplePoints(from: previousDocPoint, to: currentPoint)
        previousDocPoint = currentPoint

        var hitRows: [HoverTrailRowView] = []
        for sample in samples {
            guard let hit = row(at: sample, in: mounted, docView: docView), !hit.isSelected else {
                continue
            }
            if !hitRows.contains(where: { $0 === hit }) {
                hitRows.append(hit)
            }
        }

        let current = hitRows.last
        let color = resolvedHoverColor(for: panel)

        if let prev = previousRow, prev !== current, !prev.isSelected,
            prev.window === panel, prev.isDescendant(of: docView),
            let canvas = canvasView(for: docView, create: true)
        {
            canvas.fadeOut(
                rect: prev.convert(prev.bounds, to: canvas),
                cornerRadius: prev.cornerRadius,
                color: color)
        }

        if let canvas = canvasView(for: docView, create: !hitRows.isEmpty) {
            for row in hitRows where row !== current && row !== previousRow && !row.isSelected {
                canvas.fadeOut(
                    rect: row.convert(row.bounds, to: canvas),
                    cornerRadius: row.cornerRadius,
                    color: color)
            }
            if let current {
                canvas.cancelPill(for: current.convert(current.bounds, to: canvas))
            }
        }

        previousRow = current
    }

    func handlePointerLeave(animated: Bool) {
        if animated, let panel, let prev = previousRow, !prev.isSelected,
            let docView = activeDocView, prev.window === panel, prev.isDescendant(of: docView),
            let canvas = canvasView(for: docView, create: true)
        {
            canvas.fadeOut(
                rect: prev.convert(prev.bounds, to: canvas),
                cornerRadius: prev.cornerRadius,
                color: resolvedHoverColor(for: panel))
        } else if !animated {
            clearCanvases()
        }
        previousRow = nil
        previousDocPoint = nil
    }

    func clearImmediate() {
        clearCanvases()
        previousRow = nil
        previousDocPoint = nil
    }

    private func clearCanvases() {
        if let activeDocView {
            canvasView(for: activeDocView, create: false)?.clearAll()
        }
        guard let contentView = panel?.contentView else { return }
        for scrollView in scrollViews(in: contentView) {
            if let docView = scrollView.documentView, docView !== activeDocView {
                canvasView(for: docView, create: false)?.clearAll()
            }
        }
    }

    private func ensureTrackingArea(in panel: PalettePanel) {
        guard let contentView = panel.contentView else { return }
        if trackedContentView === contentView, trackingArea != nil { return }
        if let existing = trackingArea, let previous = trackedContentView {
            previous.removeTrackingArea(existing)
        }
        let proxy = TrackingProxy(
            onEnter: { [weak self] in self?.previousDocPoint = nil },
            onExit: { [weak self] in self?.handlePointerLeave(animated: true) })
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: proxy,
            userInfo: nil)
        contentView.addTrackingArea(area)
        trackingProxy = proxy
        trackingArea = area
        trackedContentView = contentView
    }

    private func observeClipViewIfNeeded(_ clipView: NSClipView) {
        guard !observedClipViews.contains(clipView) else { return }
        observedClipViews.add(clipView)
        clipView.postsBoundsChangedNotifications = true
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clearImmediate()
            }
        }
        clipObservers.append(NotificationToken(token, center: center))
    }

    private func scrollView(at windowPoint: CGPoint, in panel: PalettePanel) -> NSScrollView? {
        guard let contentView = panel.contentView else { return nil }
        var match: NSScrollView?
        for sv in scrollViews(in: contentView) where sv.documentView != nil {
            let clipRect = sv.contentView.convert(sv.contentView.bounds, to: nil)
            if clipRect.contains(windowPoint) { match = sv }
        }
        return match
    }

    private func scrollViews(in root: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        collectScrollViews(in: root, into: &result)
        return result
    }

    private func collectScrollViews(in view: NSView, into result: inout [NSScrollView]) {
        guard !view.isHidden else { return }
        if let sv = view as? NSScrollView { result.append(sv) }
        for child in view.subviews where !(child is HoverTrailCanvasView) {
            collectScrollViews(in: child, into: &result)
        }
    }

    private func visibleViewport(of scrollView: NSScrollView, in panel: PalettePanel) -> CGRect {
        var rect = scrollView.contentView.convert(scrollView.contentView.bounds, to: nil)
        // Intersect with the safe-area container so header and footer chrome never trigger rows.
        if let container = scrollView.superview?.superview, container !== panel.contentView {
            rect = rect.intersection(container.convert(container.bounds, to: nil))
        }
        return rect
    }

    private func mountedRows(in docView: NSView, panel: PalettePanel) -> [HoverTrailRowView] {
        rows.allObjects.filter {
            $0.window === panel && !$0.isHiddenOrHasHiddenAncestor && $0.isDescendant(of: docView)
        }
    }

    private func row(
        at docPoint: CGPoint, in mounted: [HoverTrailRowView], docView: NSView
    ) -> HoverTrailRowView? {
        for candidate in mounted {
            let frame = candidate.convert(candidate.bounds, to: docView)
            if frame.contains(docPoint) { return candidate }
        }
        return nil
    }

    private func canvasView(for docView: NSView, create: Bool) -> HoverTrailCanvasView? {
        if let existing = docView.subviews.first(where: { $0 is HoverTrailCanvasView })
            as? HoverTrailCanvasView
        {
            let target = docView.bounds
            if abs(existing.frame.origin.x - target.origin.x) > 0.5
                || abs(existing.frame.origin.y - target.origin.y) > 0.5
                || abs(existing.frame.size.width - target.size.width) > 0.5
                || abs(existing.frame.size.height - target.size.height) > 0.5
            {
                existing.frame = target
            }
            return existing
        }
        guard create else { return nil }
        let canvas = HoverTrailCanvasView(frame: docView.bounds)
        if let first = docView.subviews.first {
            docView.addSubview(canvas, positioned: .below, relativeTo: first)
        } else {
            docView.addSubview(canvas)
        }
        return canvas
    }

    private func resolvedHoverColor(for panel: PalettePanel) -> CGColor {
        var resolved = NSColor.white.withAlphaComponent(0.05).cgColor
        panel.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(Theme.Colors.rowHover).cgColor
        }
        return resolved
    }
}

/// Bridges `NSTrackingArea` callbacks without forcing `HoverTrailController` to inherit `NSResponder`.
private final class TrackingProxy: NSResponder {
    private let onEnter: @MainActor () -> Void
    private let onExit: @MainActor () -> Void

    init(onEnter: @escaping @MainActor () -> Void, onExit: @escaping @MainActor () -> Void) {
        self.onEnter = onEnter
        self.onExit = onExit
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) {
        onEnter()
    }

    override func mouseExited(with event: NSEvent) {
        onExit()
    }
}

/// Passive Core Animation surface behind list content for fading hover-trail pills.
private final class HoverTrailCanvasView: NSView {
    private struct ActivePill {
        let layer: CALayer
        let token: UInt64
    }

    private var activePills: [String: ActivePill] = [:]
    private var nextToken: UInt64 = 1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { superview?.isFlipped ?? true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func fadeOut(rect: CGRect, cornerRadius: CGFloat, color: CGColor) {
        guard !rect.isEmpty, let rootLayer = layer else { return }
        let key = rectKey(rect)
        cancelPill(forKey: key)

        let pill = CALayer()
        pill.frame = rect
        pill.cornerRadius = cornerRadius
        pill.cornerCurve = .continuous
        pill.backgroundColor = color
        pill.opacity = 1

        let token = nextToken
        nextToken &+= 1
        activePills[key] = ActivePill(layer: pill, token: token)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rootLayer.addSublayer(pill)
        pill.opacity = 0
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let current = self.activePills[key], current.token == token else {
                    return
                }
                self.activePills.removeValue(forKey: key)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                pill.removeAllAnimations()
                pill.removeFromSuperlayer()
                CATransaction.commit()
            }
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.duration = Theme.Duration.hoverTrail
        fade.timingFunction = CAMediaTimingFunction(name: .linear)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        pill.add(fade, forKey: "hoverTrailFade")
        CATransaction.commit()
    }

    func cancelPill(for rect: CGRect) {
        cancelPill(forKey: rectKey(rect))
    }

    func clearAll() {
        guard !activePills.isEmpty else { return }
        let pills = activePills.values.map(\.layer)
        activePills.removeAll()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for pill in pills {
            pill.removeAllAnimations()
            pill.removeFromSuperlayer()
        }
        CATransaction.commit()
    }

    private func cancelPill(forKey key: String) {
        guard let existing = activePills.removeValue(forKey: key) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        existing.layer.removeAllAnimations()
        existing.layer.removeFromSuperlayer()
        CATransaction.commit()
    }

    private func rectKey(_ rect: CGRect) -> String {
        "\(Int(rect.origin.x.rounded()))_\(Int(rect.origin.y.rounded()))_"
            + "\(Int(rect.size.width.rounded()))_\(Int(rect.size.height.rounded()))"
    }
}

/// Passive row anchor that registers its bounds with `PalettePanel.hoverTrail`.
final class HoverTrailRowView: NSView {
    private weak var registeredController: HoverTrailController?
    var cornerRadius: CGFloat = Theme.Radius.row
    var isSelected = false {
        didSet {
            if isSelected, !oldValue {
                registeredController?.cancelTrail(for: self)
            }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            registeredController?.unregister(self)
            registeredController = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let panel = window as? PalettePanel else { return }
        registeredController = panel.hoverTrail
        panel.hoverTrail.register(self)
    }
}
