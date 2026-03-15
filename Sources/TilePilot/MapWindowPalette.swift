import SwiftUI

struct MapWindowPaletteColors {
    let border: Color
    let fill: Color
}

enum MapWindowPalette {
    private struct WarmFamily {
        let floatingBorder: Color
        let floatingFill: Color
        let limitedBorder: Color
        let limitedFill: Color
    }

    private static let tiledBorder = Color(red: 0.20, green: 0.50, blue: 0.95)
    private static let tiledFocusedBorder = Color(red: 0.32, green: 0.66, blue: 1.0)

    private static let warmFamilies: [WarmFamily] = [
        WarmFamily(
            floatingBorder: Color(red: 0.98, green: 0.74, blue: 0.22),
            floatingFill: Color(red: 0.98, green: 0.74, blue: 0.22, opacity: 0.14),
            limitedBorder: Color(red: 0.82, green: 0.72, blue: 0.49),
            limitedFill: Color(red: 0.82, green: 0.72, blue: 0.49, opacity: 0.11)
        ),
        WarmFamily(
            floatingBorder: Color(red: 0.99, green: 0.63, blue: 0.20),
            floatingFill: Color(red: 0.99, green: 0.63, blue: 0.20, opacity: 0.14),
            limitedBorder: Color(red: 0.83, green: 0.66, blue: 0.44),
            limitedFill: Color(red: 0.83, green: 0.66, blue: 0.44, opacity: 0.11)
        ),
        WarmFamily(
            floatingBorder: Color(red: 0.96, green: 0.52, blue: 0.18),
            floatingFill: Color(red: 0.96, green: 0.52, blue: 0.18, opacity: 0.14),
            limitedBorder: Color(red: 0.79, green: 0.58, blue: 0.41),
            limitedFill: Color(red: 0.79, green: 0.58, blue: 0.41, opacity: 0.11)
        ),
        WarmFamily(
            floatingBorder: Color(red: 0.94, green: 0.42, blue: 0.20),
            floatingFill: Color(red: 0.94, green: 0.42, blue: 0.20, opacity: 0.14),
            limitedBorder: Color(red: 0.77, green: 0.53, blue: 0.40),
            limitedFill: Color(red: 0.77, green: 0.53, blue: 0.40, opacity: 0.11)
        ),
        WarmFamily(
            floatingBorder: Color(red: 0.88, green: 0.31, blue: 0.22),
            floatingFill: Color(red: 0.88, green: 0.31, blue: 0.22, opacity: 0.14),
            limitedBorder: Color(red: 0.73, green: 0.47, blue: 0.40),
            limitedFill: Color(red: 0.73, green: 0.47, blue: 0.40, opacity: 0.11)
        )
    ]

    static func colors(
        windowID: Int,
        isFloating: Bool,
        isRuntimeManageable: Bool,
        isFocused: Bool,
        isSelected: Bool = false
    ) -> MapWindowPaletteColors {
        if !isRuntimeManageable {
            let family = warmFamilies[paletteIndex(for: windowID)]
            return MapWindowPaletteColors(
                border: family.limitedBorder,
                fill: isSelected ? family.limitedFill.opacity(0.18) : family.limitedFill
            )
        }

        if isFloating {
            let family = warmFamilies[paletteIndex(for: windowID)]
            return MapWindowPaletteColors(
                border: family.floatingBorder,
                fill: isSelected ? family.floatingFill.opacity(0.22) : family.floatingFill
            )
        }

        let border = isFocused ? tiledFocusedBorder : tiledBorder
        let fillOpacity: Double
        if isSelected {
            fillOpacity = 0.22
        } else if isFocused {
            fillOpacity = 0.14
        } else {
            fillOpacity = 0.09
        }
        return MapWindowPaletteColors(
            border: border,
            fill: border.opacity(fillOpacity)
        )
    }

    private static func paletteIndex(for windowID: Int) -> Int {
        abs(windowID) % warmFamilies.count
    }
}
