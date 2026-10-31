//
//  SplashView.swift
//  Lexia
//

import SwiftUI

/// The loading screen: Lexia's logo and name, shown for a moment at launch while
/// the app starts up, then faded out (see ContentView).
///
/// iOS first shows the system launch screen, which can't be animated: a plain
/// background in the system colour. This view starts on the same background, so the
/// hand-over is invisible and the logo appears to grow out of it.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 18) {
                LexiaLogo()
                    .frame(width: 104, height: 104)
                    // Grows in from slightly smaller, unless the user turned on Reduce Motion.
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.8)
                Text("Lexia")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                Text("Lectures, explained")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                ProgressView()
                    .padding(.top, 8)
            }
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.3)) { appeared = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lexia is loading")
    }
}

/// Lexia's mark: an open book with a spark, on a blue-violet tile shaped like an app icon.
/// Drawn in code, so it is sharp at any size and needs no image files.
struct LexiaLogo: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size.width
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.98),
                                              Color(red: 0.55, green: 0.30, blue: 0.92)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    Image(systemName: "book.pages.fill")
                        .font(.system(size: size * 0.46, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(y: size * 0.03)
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "sparkle")
                        .font(.system(size: size * 0.2, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(size * 0.12)
                }
                .shadow(color: .black.opacity(0.15), radius: size * 0.06, y: size * 0.03)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview {
    SplashView()
}
