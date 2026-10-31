// lexia-render.js
// Turns an explanation (Markdown with LaTeX maths) into HTML, using marked for the
// Markdown and KaTeX for the maths. Loaded by lexia.html, which MathMarkdownView
// shows in a web view.
//
// lexiaRender() touches no page (no `document`), so the unit tests can run it in
// JavaScriptCore without a web view.

// Markdown can contain raw HTML. Explanations come from Claude or the clipboard,
// so raw HTML is shown as text instead of being run, and images are shown as their
// description instead of being loaded from the internet.
marked.use({
    renderer: {
        html: function (html) {
            var text = typeof html === "string" ? html : html.text;
            return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        },
        image: function (href, title, text) {
            return typeof href === "object" ? href.text : text;
        }
    }
});

function lexiaRender(markdown) {
    // Maths must be taken out before Markdown runs: marked would read the
    // underscores and asterisks in "x_1 * y_2" as emphasis. Each formula is swapped
    // for a placeholder made of private-use characters (which nothing else
    // produces), and put back as KaTeX's HTML at the end. Code is set aside
    // first, so a "$" inside code isn't taken for maths.
    var math = [];
    var code = [];
    function hold(list, value, open, close) {
        list.push(value);
        return open + (list.length - 1) + close;
    }
    var src = markdown.replace(/```[\s\S]*?(?:```|$)|`[^`\n]*`/g, function (m) {
        return hold(code, m, "", "");
    });
    src = src
        .replace(/\$\$([\s\S]+?)\$\$/g, function (_, tex) { return hold(math, { tex: tex, display: true }, "", ""); })
        .replace(/\\\[([\s\S]+?)\\\]/g, function (_, tex) { return hold(math, { tex: tex, display: true }, "", ""); })
        .replace(/\\\(([\s\S]+?)\\\)/g, function (_, tex) { return hold(math, { tex: tex, display: false }, "", ""); })
        // $…$ inline: no space just inside the dollars, so "costs $5 and $6" stays text.
        .replace(/\$(?=\S)([^$\n]+?)(?<=\S)\$/g, function (_, tex) { return hold(math, { tex: tex, display: false }, "", ""); });
    src = src.replace(/(\d+)/g, function (_, i) { return code[+i]; });

    var html = marked.parse(src, { gfm: true });

    return html.replace(/(\d+)/g, function (_, i) {
        var m = math[+i];
        // throwOnError false: a formula KaTeX can't read is shown in red as written,
        // instead of breaking the whole explanation.
        return katex.renderToString(m.tex, { displayMode: m.display, throwOnError: false });
    });
}

// Called from Swift with the Markdown to show. Reports the new height, which the
// app needs when the web view sits inside a list instead of scrolling by itself.
function lexiaShow(markdown) {
    document.getElementById("content").innerHTML = lexiaRender(markdown);
    lexiaReportHeight();
}

function lexiaReportHeight() {
    var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.height;
    if (handler) handler.postMessage(document.getElementById("content").scrollHeight);
}

if (typeof document !== "undefined") {
    // Images of formulas finish laying out after the fonts load; report again then.
    document.addEventListener("DOMContentLoaded", function () {
        new ResizeObserver(lexiaReportHeight).observe(document.getElementById("content"));
    });
}
