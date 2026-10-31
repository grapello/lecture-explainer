//
//  LexiaLogo.swift
//  Lexia
//

import SwiftUI

/// Lexia's mark: an open book with a spark on a blue-violet background. Drawn in
/// code, so it is sharp at any size and needs no image files.
///
/// The same view draws the loading screen's logo and the app icon:
/// scripts/render-app-icon.sh renders it into Assets.xcassets/AppIcon.appiconset.
/// This file uses SwiftUI only (no UIKit) so that script can compile it on the Mac.
struct LexiaLogo: View {
    enum Style {
        /// A rounded tile with a shadow, for inside the app (the loading screen).
        case tile
        /// A full square, for the app icon: iOS rounds the corners itself.
        /// The three looks are the home screen's Default, Dark and Tinted icons.
        case icon(IconLook)
    }

    enum IconLook: CaseIterable {
        case light, dark, tinted
    }

    var style: Style = .tile

    // Lexia's two colours, top left to bottom right.
    static let blue = Color(red: 0.36, green: 0.42, blue: 0.98)
    static let violet = Color(red: 0.55, green: 0.30, blue: 0.92)
    private static let gradient = LinearGradient(colors: [blue, violet],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size.width
            switch style {
            case .tile:
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .fill(Self.gradient)
                    .overlay { mark(size: size, glyph: AnyShapeStyle(.white)) }
                    .shadow(color: .black.opacity(0.15), radius: size * 0.06, y: size * 0.03)
            case .icon(.light):
                Rectangle()
                    .fill(Self.gradient)
                    .overlay { mark(size: size, glyph: AnyShapeStyle(.white)) }
            case .icon(.dark):
                // Apple's dark icons keep the colour in the glyph, on a near-black background.
                Rectangle()
                    .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.06)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay { mark(size: size, glyph: AnyShapeStyle(Self.gradient)) }
            case .icon(.tinted):
                // A grey image the system colours with the user's tint: white is drawn
                // in the tint, black stays dark.
                Rectangle()
                    .fill(.black)
                    .overlay { mark(size: size, glyph: AnyShapeStyle(.white)) }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// The book and the spark, scaled to the logo's width.
    private func mark(size: CGFloat, glyph: AnyShapeStyle) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "book.pages.fill")
                .font(.system(size: size * 0.46, weight: .semibold))
                .offset(y: size * 0.03)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.2, weight: .bold))
                .padding(size * 0.12)
        }
        .foregroundStyle(glyph)
    }
}

#Preview("Tile") {
    LexiaLogo().frame(width: 104, height: 104).padding()
}

#Preview("App icons") {
    HStack {
        ForEach(LexiaLogo.IconLook.allCases, id: \.self) { look in
            LexiaLogo(style: .icon(look))
                .frame(width: 90, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
    .padding()
}
