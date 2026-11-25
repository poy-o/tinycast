import SwiftUI

private typealias BarMotion = Theme.CompactBarMotion

/// Where the capsule ends and the shortcut glass group rests in the compact window.
struct CompactBarGeometry {
    let width: CGFloat
    let height: CGFloat
    let diameter: CGFloat
    let gap: CGFloat
    let buttonGap: CGFloat
    let count: Int

    init(metrics: InterfaceMetrics, count: Int) {
        width = metrics.size.panelWidth
        height = metrics.size.compactHeight
        // A point inside the bar's height, so the trailing edge clears the window's rounded end.
        diameter = height - metrics.scaled(1) * 2
        gap = metrics.spacing.lg
        buttonGap = metrics.spacing.xs
        self.count = count
    }

    var groupWidth: CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * diameter + CGFloat(max(count - 1, 0)) * buttonGap
    }

    var groupCenter: CGPoint {
        CGPoint(x: capsuleWidth(revealed: true) + gap + groupWidth / 2, y: height / 2)
    }

    func capsuleWidth(revealed: Bool) -> CGFloat {
        guard revealed, count > 0 else { return width }
        return width - gap - groupWidth
    }

    func center(of index: Int) -> CGPoint {
        CGPoint(
            x: capsuleWidth(revealed: true) + gap + diameter / 2
                + CGFloat(index) * (diameter + buttonGap),
            y: height / 2)
    }

    /// Just inside the shortened capsule's end, so the capsule pulling back uncovers each button.
    var parked: CGPoint {
        CGPoint(x: capsuleWidth(revealed: true) - diameter / 2, y: height / 2)
    }
}

/// The compact bar's glass: a search capsule and a unified glass group of shortcut bubbles.
struct CompactBar: View {
    let commands: [CommandID]
    let selection: CommandID?
    let onRun: (CommandID) -> Void
    /// The window caches its shadow from the shapes it first drew, before the buttons beaded out.
    let onSettled: () -> Void
    @Environment(PaletteState.self) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace
    @State private var isRevealed = false

    var body: some View {
        let geometry = CompactBarGeometry(metrics: metrics, count: commands.count)
        let revealed = isRevealed
        Group {
            // Glass casting its own shadow would give the window's shadow that soft halo to trace.
            if Theme.glassCastsShadow {
                glass(geometry: geometry, revealed: revealed)
                    .mask { silhouette(geometry: geometry, revealed: revealed) }
            } else {
                glass(geometry: geometry, revealed: revealed)
            }
        }
        .overlay { scrim(geometry: geometry, revealed: revealed) }
        // Above the glass rather than inside it, where a morph would smear them.
        .overlay(alignment: .topLeading) {
            ForEach(Array(commands.enumerated()), id: \.element) { index, command in
                glyph(command, at: index, geometry: geometry, revealed: revealed)
            }
        }
        .task(id: palette.isVisible) { await followVisibility() }
    }

    /// Left unmasked where it can be: any mask also clips the rim glass draws past its shape.
    private func glass(geometry: CompactBarGeometry, revealed: Bool) -> some View {
        let capsule = Capsule(style: .continuous)
        // One container, or the button group could never bead off the capsule it comes out of.
        return GlassEffectContainer(spacing: metrics.scaled(BarMotion.blend)) {
            ZStack(alignment: .topLeading) {
                capsule.fill(.clear)
                    .frame(width: geometry.capsuleWidth(revealed: revealed))
                    .frame(maxHeight: .infinity)
                    .glassEffect(.regular, in: capsule)
                    .animation(
                        reduceMotion ? nil : BarMotion.capsule.delay(BarMotion.revealDelay),
                        value: revealed)
                ForEach(Array(commands.enumerated()), id: \.element) { index, command in
                    button(command, at: index, geometry: geometry, revealed: revealed)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func button(
        _ command: CommandID, at index: Int, geometry: CompactBarGeometry, revealed: Bool
    ) -> some View {
        Button {
            onRun(command)
        } label: {
            Color.clear
                .frame(width: geometry.diameter, height: geometry.diameter)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(command.name)
        .accessibilityLabel(command.name)
        .accessibilityAddTraits(selection == command ? [.isSelected] : [])
        .accessibilityHidden(!revealed)
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectUnion(id: "compactShortcuts", namespace: glassNamespace)
        .scaleEffect(revealed ? 1 : BarMotion.parkedScale)
        .position(revealed ? geometry.center(of: index) : geometry.parked)
        .allowsHitTesting(revealed)
        .animation(travel(index), value: revealed)
    }

    private func scrim(geometry: CompactBarGeometry, revealed: Bool) -> some View {
        Theme.Colors.panelScrim
            .mask { silhouette(geometry: geometry, revealed: revealed) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The capsule and its unified shortcut group as they move.
    private func silhouette(
        geometry: CompactBarGeometry, revealed: Bool
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Capsule(style: .continuous).fill(.white)
                .frame(width: geometry.capsuleWidth(revealed: revealed))
                .frame(maxHeight: .infinity)
                .animation(
                    reduceMotion ? nil : BarMotion.capsule.delay(BarMotion.revealDelay),
                    value: revealed)
            if geometry.count > 0 {
                Capsule(style: .continuous).fill(.white)
                    .frame(
                        width: revealed ? geometry.groupWidth : geometry.diameter,
                        height: geometry.diameter)
                    .opacity(revealed ? 1 : 0)
                    .scaleEffect(revealed ? 1 : BarMotion.parkedScale)
                    .position(revealed ? geometry.groupCenter : geometry.parked)
                    .animation(travel(0), value: revealed)
            }
            ForEach(Array(commands.enumerated()), id: \.element) { index, _ in
                Circle().fill(.white)
                    .frame(width: geometry.diameter, height: geometry.diameter)
                    .opacity(revealed ? 1 : 0)
                    .scaleEffect(revealed ? 1 : BarMotion.parkedScale)
                    .position(revealed ? geometry.center(of: index) : geometry.parked)
                    .animation(travel(index), value: revealed)
            }
        }
    }

    private func glyph(
        _ command: CommandID, at index: Int, geometry: CompactBarGeometry, revealed: Bool
    ) -> some View {
        let isSelected = selection == command
        let highlightInset = metrics.scaled(4)
        return ZStack {
            if isSelected {
                Circle()
                    .fill(Theme.Colors.compactShortcutSelectionTint)
                    .frame(
                        width: geometry.diameter - highlightInset * 2,
                        height: geometry.diameter - highlightInset * 2)
            }
            SymbolImage(
                name: command.sfSymbol, size: metrics.scaled(Theme.Typography.headerIconSize),
                monochrome: isSelected
            )
            .environment(\.symbolVariants, .none)
            .foregroundStyle(
                isSelected ? Theme.Colors.compactShortcutSelectedInk : Theme.Colors.textSecondary
            )
        }
        .animation(fade(index)) {
            $0.opacity(revealed ? 1 : 0).blur(radius: revealed ? 0 : BarMotion.glyphBlur)
        }
        // Shrinks with its circle but never travels: glyphs sent home would pile into one blot.
        .animation(travel(index)) {
            $0.scaleEffect(revealed ? 1 : BarMotion.parkedScale)
        }
        .position(geometry.center(of: index))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func travel(_ index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return BarMotion.button.delay(BarMotion.revealDelay + BarMotion.stagger * Double(index))
    }

    private func fade(_ index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeOut(duration: BarMotion.glyphFade)
            .delay(BarMotion.revealDelay + BarMotion.glyphDelay + BarMotion.stagger * Double(index))
    }

    /// Out on every summon, and parked only once the window has faded, so leaving fades it whole.
    private func followVisibility() async {
        guard !palette.isVisible else {
            isRevealed = true
            guard Theme.glassCastsShadow else { return }
            let reveal = BarMotion.revealDelay + BarMotion.stagger * Double(commands.count) + BarMotion.settle
            try? await Task.sleep(for: .seconds(Motion.duration(reveal)))
            guard !Task.isCancelled else { return }
            onSettled()
            return
        }
        try? await Task.sleep(for: .seconds(Motion.duration(BarMotion.parkAfterHide)))
        guard !Task.isCancelled else { return }
        withTransaction(\.disablesAnimations, true) { isRevealed = false }
    }
}
