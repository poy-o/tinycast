import SwiftUI

private struct ArmedHover: ViewModifier {
    @Environment(PaletteState.self) private var palette
    @Environment(\.metrics) private var metrics
    @Binding var hovered: Bool
    let selected: Bool
    let trailEnabled: Bool
    let cornerRadius: CGFloat?

    func body(content: Content) -> some View {
        content
            .background {
                if trailEnabled {
                    HoverTrailAnchor(
                        selected: selected,
                        cornerRadius: cornerRadius ?? metrics.radius.row)
                }
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active: hovered = palette.hoverHighlightArmed
                case .ended: hovered = false
                }
            }
            // Disarming under a still pointer fires no hover phase, so the drop clears the row.
            .onChange(of: palette.hoverDisarmToken) { hovered = false }
    }
}

private struct HoverTrailAnchor: NSViewRepresentable {
    let selected: Bool
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> HoverTrailRowView {
        let view = HoverTrailRowView()
        view.isSelected = selected
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ view: HoverTrailRowView, context: Context) {
        view.isSelected = selected
        view.cornerRadius = cornerRadius
    }
}

extension View {
    /// Row hover, lit only while the pointer moves; independent of the keyboard selection.
    func armedHover(_ hovered: Binding<Bool>) -> some View {
        modifier(ArmedHover(hovered: hovered, selected: false, trailEnabled: false, cornerRadius: nil))
    }

    /// Row hover with a Raycast-style fading trail behind fast pointer sweeps.
    func armedHover(
        _ hovered: Binding<Bool>, selected: Bool, cornerRadius: CGFloat? = nil
    ) -> some View {
        modifier(
            ArmedHover(
                hovered: hovered, selected: selected, trailEnabled: true, cornerRadius: cornerRadius))
    }
}
