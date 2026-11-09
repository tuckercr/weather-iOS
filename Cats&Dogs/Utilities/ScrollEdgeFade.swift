import CoreGraphics

/// Which edges of a sideways scroller fade, as a hint that there is more past them: the leading edge
/// once the content has been scrolled away from its start, the trailing edge while there is more past
/// it. At either end that side's fade goes away, and when everything fits neither fades. Same rules
/// as the Android hourly strip's fade. Not main-actor isolated: it's worked out in
/// `onGeometryChange`'s transform, off the main actor.
nonisolated struct ScrollEdgeFade: Equatable, Sendable {
    var leading: Bool
    var trailing: Bool

    static let none = ScrollEdgeFade(leading: false, trailing: false)

    /// The fade's width in points.
    static let width: CGFloat = 24

    /// Less than this from an end counts as at it, so rounding never leaves a sliver of fade.
    static let tolerance: CGFloat = 1

    /// `offset` is how far the content has scrolled from its start (0 at the start; negative while
    /// bouncing past it). `contentWidth` and `viewportWidth` are the scrolled content's width and
    /// the visible width.
    static func forScroll(offset: CGFloat, contentWidth: CGFloat, viewportWidth: CGFloat) -> ScrollEdgeFade {
        let maxOffset = contentWidth - viewportWidth
        guard viewportWidth > 0, maxOffset > tolerance else { return .none }
        return ScrollEdgeFade(
            leading: offset > tolerance,
            trailing: offset < maxOffset - tolerance
        )
    }
}
