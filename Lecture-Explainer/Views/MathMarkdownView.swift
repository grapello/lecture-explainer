//
//  MathMarkdownView.swift
//  Lexia
//

import SwiftUI
import UIKit
import WebKit

/// Shows Markdown with typeset formulas ($…$ and $$…$$ in LaTeX).
///
/// iOS has no built-in way to typeset maths, so the text is rendered in a small web
/// page (Resources/KaTeX/lexia.html) with KaTeX, the library many websites use for
/// formulas, and marked for the Markdown. Both are bundled with the app, so this
/// works offline.
///
/// - `scrolls: true`: the page scrolls by itself (a full-screen explanation).
/// - `scrolls: false`: the view takes the page's full height, for use inside a
///   List or Form (the answer streaming in on the lecture screen).
struct MathMarkdownView: View {
    let markdown: String
    var scrolls = true
    @State private var height: CGFloat = 40

    var body: some View {
        if scrolls {
            WebMarkdown(markdown: markdown, scrolls: true, height: $height)
        } else {
            WebMarkdown(markdown: markdown, scrolls: false, height: $height)
                .frame(height: height)
        }
    }
}

/// The WKWebView itself, wrapped for SwiftUI (UIViewRepresentable).
private struct WebMarkdown: UIViewRepresentable {
    let markdown: String
    let scrolls: Bool
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // The page reports its height through this channel (see lexiaReportHeight).
        // A weak proxy, because the controller would otherwise keep the coordinator alive.
        configuration.userContentController.add(WeakMessageHandler(context.coordinator), name: "height")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = scrolls
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        if let page = Bundle.main.url(forResource: "lexia", withExtension: "html") {
            // Read access to the folder lets the page load the scripts, styles and fonts next to it.
            webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.show(markdown)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        private let height: Binding<CGFloat>
        private var isLoaded = false
        private var pending: String?
        private var shown: String?
        private var lastRender = Date.distantPast
        private var scheduled = false

        init(height: Binding<CGFloat>) { self.height = height }

        /// Renders `markdown`. While an answer streams in, this is called for every
        /// few words; re-rendering the whole page each time would make typing stutter,
        /// so it renders at most every 0.3 s, and always the latest text.
        func show(_ markdown: String) {
            pending = markdown
            guard isLoaded, !scheduled else { return }
            let wait = 0.3 - Date.now.timeIntervalSince(lastRender)
            if wait <= 0 {
                renderPending()
            } else {
                scheduled = true
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                    self?.scheduled = false
                    self?.renderPending()
                }
            }
        }

        private func renderPending() {
            guard let markdown = pending, markdown != shown, let webView else { return }
            shown = markdown
            lastRender = .now
            // JSON-encoding the string makes it a safe JavaScript string literal
            // (quotes, backslashes and newlines escaped).
            let literal = (try? String(decoding: JSONEncoder().encode(markdown), as: UTF8.self)) ?? "\"\""
            webView.evaluateJavaScript("lexiaShow(\(literal))")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            renderPending()
        }

        /// Links in an explanation open in Safari instead of replacing the page.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                if url.scheme == "http" || url.scheme == "https" { UIApplication.shared.open(url) }
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let value = message.body as? Double, value > 0, abs(value - height.wrappedValue) > 1 {
                height.wrappedValue = value
            }
        }
    }
}

/// Forwards script messages without keeping the receiver alive.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

#Preview {
    MathMarkdownView(markdown: """
    ## Page 2: The Schrödinger equation

    The state $\\psi(x, t)$ evolves according to

    $$i\\hbar \\frac{\\partial \\psi}{\\partial t} = \\hat{H}\\psi$$

    | Symbol | Meaning |
    |---|---|
    | $\\hbar$ | reduced Planck constant |
    """)
}
