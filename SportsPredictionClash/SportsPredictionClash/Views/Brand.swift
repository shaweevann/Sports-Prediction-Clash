import SwiftUI

/// Sports Prediction Clash brand colors: burgundy and polished gold, matching the app icon.
/// Semantic colors stay out of the brand: YES/NO are green/red, the field is green, and the
/// multiplier keeps its cool-to-hot heat scale.
enum Brand {
    static let burgundy = Color(red: 0.48, green: 0.08, blue: 0.15)
    static let burgundyDeep = Color(red: 0.22, green: 0.03, blue: 0.07)
    /// Bright gold for fills, glows and lines.
    static let gold = Color(red: 0.96, green: 0.77, blue: 0.30)
    /// Gold for text: deeper in light mode so it stays readable on pale glass.
    static let goldInk = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.98, green: 0.81, blue: 0.38, alpha: 1)
            : UIColor(red: 0.60, green: 0.40, blue: 0.03, alpha: 1)
    })
}

/// The main call to action: a gold glass capsule with burgundy lettering.
struct BrandButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Brand.burgundyDeep)
                .padding(.horizontal, 6).padding(.vertical, 5)
        }
        .buttonStyle(.glassProminent)
        .tint(Brand.gold)
    }
}
