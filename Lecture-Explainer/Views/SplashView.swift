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
    // @ScaledMetric grows these sizes with the user's text size (Dynamic Type).
    @ScaledMetric(relativeTo: .largeTitle) private var logoSize = 104
    @ScaledMetric(relativeTo: .largeTitle) private var nameSize = 44

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 18) {
                LexiaLogo()
                    .frame(width: logoSize, height: logoSize)
                    // Grows in from slightly smaller, unless the user turned on Reduce Motion.
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.8)
                Text("Lexia")
                    .font(.system(size: nameSize, weight: .bold, design: .rounded))
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

#Preview {
    SplashView()
}
