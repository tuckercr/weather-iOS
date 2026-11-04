import SwiftUI

/// The Rain outlook card under the hourly strip (`RainOutlook`): the headline, when it dries out and
/// how much falls, and a bar for each hour's chance of rain. Tapping a bar shows its hour, chance and
/// amount above the chart; tapping it again, or anywhere else on the card, clears it.
struct RainOutlookCard: View {
    let outlook: RainOutlook
    @Environment(\.seasonalTheme) private var seasonalTheme
    @State private var selected: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(outlook.headline)
                .font(.brand(.headline))
            Text(outlook.detail)
                .font(.subheadline)
                .foregroundStyle(Color.secondaryText)
            RainOutlookChart(bars: outlook.bars, selected: $selected)
                .padding(.top, 6)
            Text("Chance of rain each hour")
                .font(.caption)
                .foregroundStyle(Color.secondaryText)
                .padding(.top, 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card(seasonalTheme), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { selected = nil }
        // A refresh or the clock moving on changes the hours, so a selection would point elsewhere.
        .onChange(of: outlook.bars) { _, _ in selected = nil }
    }
}

private struct RainOutlookChart: View {
    let bars: [RainOutlook.Bar]
    @Binding var selected: Int?
    @State private var barsWidth: CGFloat = 0

    private static let height: CGFloat = 110
    private static let gap: CGFloat = 4
    private static let cornerRadius: CGFloat = 4
    /// So a 0% hour still shows as a sliver on the baseline.
    private static let minBarHeight: CGFloat = 2
    private static let guideLabel = "50%"

    private var barWidth: CGFloat {
        guard !bars.isEmpty else { return 0 }
        return max((barsWidth - Self.gap * CGFloat(bars.count - 1)) / CGFloat(bars.count), 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            selectedLabel
            HStack(alignment: .top, spacing: 6) {
                HStack(alignment: .top, spacing: Self.gap) {
                    ForEach(bars.indices, id: \.self) { column($0) }
                }
                .overlay(alignment: .top) { guides }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    barsWidth = width
                }
                // Centred on the chart's height, so level with the 50% line.
                Text(verbatim: Self.guideLabel)
                    .font(.caption2)
                    .foregroundStyle(Color.secondaryText)
                    .frame(height: Self.height)
                    .accessibilityHidden(true)
            }
        }
    }

    /// "3 PM · 70% · 2.5 mm" over the selected bar, kept inside the card at either end. The row keeps
    /// its height with nothing selected, so the chart doesn't jump.
    private var selectedLabel: some View {
        Text(verbatim: " ")
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                if let selected, bars.indices.contains(selected) {
                    CentredInRow(centre: (barWidth + Self.gap) * CGFloat(selected) + barWidth / 2) {
                        Text(bars[selected].label)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            .accessibilityHidden(true)
    }

    private func column(_ index: Int) -> some View {
        let bar = bars[index]
        let height = max(Self.height * CGFloat(bar.chance) / 100, Self.minBarHeight)
        let radius = min(Self.cornerRadius, height / 2)
        return VStack(spacing: 4) {
            UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .continuous)
                // With a bar selected, the others fade back.
                .fill(Color.accent.opacity(selected == nil || selected == index ? 1 : 0.35))
                .frame(height: height)
                .frame(height: Self.height, alignment: .bottom)
            // A line's height in every column; the label itself only under every other bar, with
            // room to spill over the unlabelled one beside it.
            Text(verbatim: " ")
                .font(.caption)
                .frame(maxWidth: .infinity)
                .overlay {
                    if index.isMultiple(of: 2) {
                        Text(bar.compactHour)
                            .font(.caption)
                            .foregroundStyle(Color.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(width: barWidth * 2 + Self.gap)
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            selected = selected == index ? nil : index
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bar.accessibilityLabel)
    }

    /// The baseline and a dashed line at 50%, over the bars.
    private var guides: some View {
        ZStack {
            HorizontalLine(fromTop: 0.5)
                .stroke(Color.secondaryText.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            HorizontalLine(fromTop: 1)
                .stroke(Color.secondaryText.opacity(0.6), lineWidth: 1)
        }
        .frame(height: Self.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Places its one subview centred on `centre`, moved in to stay inside the row at either end, like
/// Android's `BarPositioned`. (An alignment guide in the overlay left the label at the leading edge.)
private struct CentredInRow: Layout {
    let centre: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let height = subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)).height ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let label = subviews.first else { return }
        let size = label.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        let x = min(max(centre - size.width / 2, 0), max(bounds.width - size.width, 0))
        label.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY), proposal: ProposedViewSize(size))
    }
}

/// A line across the rect, `fromTop` of the way down.
private struct HorizontalLine: Shape {
    let fromTop: CGFloat

    func path(in rect: CGRect) -> Path {
        let y = rect.minY + rect.height * fromTop
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
        return path
    }
}

#Preview {
    let hours = ["3 PM", "4 PM", "5 PM", "6 PM", "7 PM", "8 PM", "9 PM", "10 PM", "11 PM", "12 AM"]
    let chances = [20, 45, 70, 85, 60, 35, 20, 10, 5, 0]
    let bars = zip(hours, chances).map { hour, chance in
        RainOutlook.Bar(hour: hour, chance: chance, amountMm: Double(chance) / 40, units: .metric)
    }
    RainOutlookCard(outlook: RainOutlook(
        headline: "Rain likely around 6 PM",
        detail: "Drying out after 9 PM. About 8.1 mm in all.",
        bars: bars
    ))
    .padding()
}
