import Foundation
import SwiftUI

/// Number formatting used in the window. "—" means "no value yet".
enum DisplayFormat {
    static func degrees(_ value: Double?) -> String {
        guard let value = value else { return "—" }
        return String(format: "%+.1f°", value)
    }

    static func milliseconds(_ value: Double?) -> String {
        guard let value = value else { return "—" }
        return String(format: "%.1f ms", value)
    }

    /// A gesture value with its unit, e.g. "+12.3°" or "+34%".
    static func gestureValue(_ value: Double?, unit: String) -> String {
        guard let value = value else { return "—" }
        return unit == "°" ? String(format: "%+.1f°", value) : String(format: "%+.0f%%", value)
    }

    /// A threshold number with its unit, e.g. "10°" or "30%".
    static func threshold(_ value: Double, unit: String) -> String {
        unit == "°" ? String(format: "%.0f°", value) : String(format: "%.0f%%", value)
    }

    static func percent(_ value: Double?) -> String {
        guard let value = value else { return "—" }
        return String(format: "%.0f%%", value)
    }
}

/// A colored box with instructions and an optional button.
struct Banner: View {
    let title: String
    let lines: [String]
    var buttonTitle: String?
    var action: (() -> Void)?
    var color: Color = .red

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let buttonTitle = buttonTitle, let action = action {
                Button(buttonTitle, action: action)
                    .padding(.top, 4)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.15))
        .cornerRadius(8)
    }
}

/// Horizontal bar showing a gesture's value, with the release (orange) and
/// press (red) thresholds marked.
struct ThresholdBar: View {
    let value: Double?
    let pressThreshold: Double
    let releaseThreshold: Double
    let isFiring: Bool

    /// The bar's right edge is 1.5× the press threshold, so you can see overshoot.
    private var scaleMax: Double { max(pressThreshold * 1.5, 1) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.2))
                RoundedRectangle(cornerRadius: 3)
                    .fill(fillColor)
                    .frame(width: geometry.size.width * fraction(value ?? 0))
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 2)
                    .offset(x: geometry.size.width * fraction(releaseThreshold) - 1)
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2)
                    .offset(x: geometry.size.width * fraction(pressThreshold) - 1)
            }
        }
    }

    private func fraction(_ x: Double) -> CGFloat {
        CGFloat(min(1, max(0, x / scaleMax)))
    }

    private var fillColor: Color {
        if isFiring { return .green }
        guard let value = value else { return .gray }
        if value >= pressThreshold { return .yellow }
        if value >= releaseThreshold { return .orange.opacity(0.7) }
        return .blue
    }
}

/// A small colored label, e.g. "HELD" in green.
struct Pill: View {
    let text: String
    let color: Color
    var textColor: Color = .black

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .foregroundColor(textColor)
            .cornerRadius(4)
    }
}
