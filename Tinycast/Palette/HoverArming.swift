import CoreGraphics

/// When pointer movement is choosing a row rather than drift; arming lives on `PaletteState`.
enum HoverArming {
    /// A wheel click nudges the mouse a point or two, and a gesture ends with no displacement.
    private static let slop: CGFloat = 3

    static func isDeliberate(_ pointer: CGPoint, from anchor: CGPoint) -> Bool {
        hypot(pointer.x - anchor.x, pointer.y - anchor.y) > slop
    }
}

/// Samples points along a fast pointer sweep so intermediate rows still leave a hover trail.
enum HoverTrailPath {
    static let step: CGFloat = 18
    static let maxSteps = 48

    static func samplePoints(from start: CGPoint?, to end: CGPoint) -> [CGPoint] {
        guard let start else { return [end] }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        guard distance > step else { return [end] }
        let steps = min(Int(ceil(distance / step)), maxSteps)
        return (1...steps).map { index in
            let fraction = CGFloat(index) / CGFloat(steps)
            return CGPoint(x: start.x + dx * fraction, y: start.y + dy * fraction)
        }
    }
}
