import WebKit

enum JavaScriptInjector {

    static func makeBridgeScript() -> WKUserScript {
        WKUserScript(
            source: dromeBridgeJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    static func makeReadabilityScript() -> WKUserScript {
        WKUserScript(
            source: dromeReadabilityJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }

    static func darkModeCSS() -> WKUserScript {
        let css = """
        html { filter: invert(1) hue-rotate(180deg) !important; }
        img, video, canvas, picture, svg { filter: invert(1) hue-rotate(180deg) !important; }
        """
        let js = """
        (function() {
            const style = document.createElement('style');
            style.id = '__drome_dark';
            style.textContent = `\(css)`;
            document.head.appendChild(style);
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    static func removeDarkModeJS() -> String {
        "document.getElementById('__drome_dark')?.remove();"
    }

    /// Idempotent — safe to call on every SwiftUI update cycle
    static func applyDarkModeJS() -> String {
        """
        (function() {
            if (document.getElementById('__drome_dark')) return;
            const s = document.createElement('style');
            s.id = '__drome_dark';
            s.textContent = 'html{filter:invert(1) hue-rotate(180deg)!important}img,video,canvas,picture,svg{filter:invert(1) hue-rotate(180deg)!important}';
            document.head.appendChild(s);
        })();
        """
    }

    static func applyFilterJS(xpaths: [String]) -> String {
        let pathsJSON = (try? String(data: JSONSerialization.data(withJSONObject: xpaths), encoding: .utf8)) ?? "[]"
        return """
        (function() {
            const paths = \(pathsJSON);
            paths.forEach(xpath => {
                try {
                    const result = document.evaluate(xpath, document, null,
                        XPathResult.FIRST_ORDERED_NODE_TYPE, null);
                    const el = result.singleNodeValue;
                    if (el) {
                        el.style.transition = 'opacity 0.4s ease';
                        el.style.opacity = '0';
                        setTimeout(() => {
                            el.style.display = 'none';
                        }, 400);
                    }
                } catch(e) {}
            });
        })();
        """
    }

    static func extractContentBlocksJS() -> String {
        """
        (function() {
            const blocks = [];
            const minLength = 30;
            const skipTags = new Set(['SCRIPT','STYLE','NOSCRIPT','CODE','PRE','SVG','MATH']);

            function getXPath(el) {
                if (!el || el === document.body) return '/html/body';
                const parts = [];
                let node = el;
                // Stop at body — prefix result with /html/body/
                while (node && node.nodeType === Node.ELEMENT_NODE && node !== document.body) {
                    let idx = 1;
                    let sib = node.previousSibling;
                    while (sib) {
                        if (sib.nodeType === Node.ELEMENT_NODE && sib.tagName === node.tagName) idx++;
                        sib = sib.previousSibling;
                    }
                    parts.unshift(node.tagName.toLowerCase() + (idx > 1 ? '[' + idx + ']' : ''));
                    node = node.parentElement;
                }
                return parts.length ? '/html/body/' + parts.join('/') : '/html/body';
            }

            // checkVisibility avoids the forced style recalc of getComputedStyle
            function isHidden(el) {
                if (el.checkVisibility) return !el.checkVisibility();
                const style = window.getComputedStyle(el);
                return style.display === 'none' || style.visibility === 'hidden';
            }

            function walk(node) {
                if (!node) return;
                if (node.nodeType === Node.ELEMENT_NODE) {
                    if (skipTags.has(node.tagName)) return;
                    if (isHidden(node)) return;
                }
                if (node.nodeType === Node.TEXT_NODE) {
                    const text = node.textContent.trim();
                    if (text.length >= minLength && node.parentElement) {
                        const el = node.parentElement;
                        blocks.push({
                            text: text.slice(0, 500),
                            xpath: getXPath(el),
                            tag: el.tagName.toLowerCase()
                        });
                    }
                    return;
                }
                for (const child of node.childNodes) walk(child);
            }

            walk(document.body);
            return JSON.stringify(blocks.slice(0, 200));
        })()
        """
    }

    // MARK: - AI Label CSS (shared style, injected once)

    private static let aiLabelCSS = """
        [data-drome-safe] { outline-offset: 1px; }
        [data-drome-safe="pending"] { outline: 2px solid rgba(59,130,246,0.55) !important; background-color: rgba(59,130,246,0.04) !important; }
        [data-drome-safe="1"]      { outline: 2px solid rgba(34,197,94,0.5) !important; background-color: rgba(34,197,94,0.04) !important; }
        [data-drome-safe="0"]      { outline: 2px solid rgba(239,68,68,0.5) !important; background-color: rgba(239,68,68,0.04) !important; }
        [data-drome-safe]::before {
            content: attr(data-drome-label) !important;
            display: inline-block !important;
            padding: 0 5px !important;
            border-radius: 3px !important;
            font-size: 10px !important;
            font-weight: 700 !important;
            font-family: -apple-system, sans-serif !important;
            color: #fff !important;
            line-height: 16px !important;
            vertical-align: middle !important;
            margin-right: 4px !important;
            pointer-events: none !important;
        }
        [data-drome-safe="pending"]::before { background: rgba(59,130,246,0.85) !important; }
        [data-drome-safe="1"]::before       { background: rgba(22,163,74,0.88)  !important; }
        [data-drome-safe="0"]::before       { background: rgba(220,38,38,0.88)  !important; }
    """

    /// Phase 1 — mark ALL candidate xpaths as pending (blue) in one JS call
    static func markAllPendingJS(xpaths: [String]) -> String {
        let json = (try? String(data: JSONSerialization.data(withJSONObject: xpaths), encoding: .utf8)) ?? "[]"
        let css = aiLabelCSS.replacingOccurrences(of: "`", with: "\\`")
        return """
        (function() {
            if (!document.getElementById('__drome_ai_style')) {
                const s = document.createElement('style');
                s.id = '__drome_ai_style';
                s.textContent = `\(css)`;
                document.head.appendChild(s);
            }
            const paths = \(json);
            paths.forEach(function(xpath) {
                try {
                    const res = document.evaluate(xpath, document, null,
                        XPathResult.FIRST_ORDERED_NODE_TYPE, null);
                    const el = res.singleNodeValue;
                    if (!el || el.hasAttribute('data-drome-safe')) return;
                    el.setAttribute('data-drome-safe', 'pending');
                    el.setAttribute('data-drome-label', '⏳');
                } catch(e) {}
            });
        })();
        """
    }

    /// Phase 2 (batched) — update many elements from pending → safe/unsafe in one JS round-trip
    static func updateLabelsBatchJS(_ updates: [(xpath: String, isSafe: Bool, reason: String)]) -> String {
        let objects: [[String: Any]] = updates.map {
            ["x": $0.xpath,
             "s": $0.isSafe ? "1" : "0",
             "l": $0.isSafe ? "✓ Safe" : "⚠ Unsafe",
             "r": $0.reason]
        }
        let json = (try? String(data: JSONSerialization.data(withJSONObject: objects), encoding: .utf8)) ?? "[]"
        return """
        (function() {
            const updates = \(json);
            updates.forEach(function(u) {
                try {
                    const res = document.evaluate(u.x, document, null,
                        XPathResult.FIRST_ORDERED_NODE_TYPE, null);
                    const el = res.singleNodeValue;
                    if (!el) return;
                    el.setAttribute('data-drome-safe', u.s);
                    el.setAttribute('data-drome-label', u.l);
                    el.setAttribute('title', u.r);
                } catch(e) {}
            });
        })();
        """
    }

    /// Inject a MutationObserver that fires dromeMutation messages for newly added text nodes
    /// not yet labeled. Debouncing happens on the Swift side.
    static func injectMutationObserverJS(minLength: Int = 25) -> String {
        """
        (function() {
            if (window.__dromeMutationObserver) return; // already running

            const skipTags = new Set(['SCRIPT','STYLE','NOSCRIPT','CODE','PRE','SVG','MATH']);

            function getXPath(el) {
                if (!el || el === document.body) return '/html/body';
                const parts = [];
                let node = el;
                while (node && node.nodeType === 1 && node !== document.body) {
                    let idx = 1, sib = node.previousSibling;
                    while (sib) { if (sib.nodeType === 1 && sib.tagName === node.tagName) idx++; sib = sib.previousSibling; }
                    parts.unshift(node.tagName.toLowerCase() + (idx > 1 ? '[' + idx + ']' : ''));
                    node = node.parentElement;
                }
                return parts.length ? '/html/body/' + parts.join('/') : '/html/body';
            }

            const observer = new MutationObserver(function(mutations) {
                const seen = new Set();
                for (const mut of mutations) {
                    for (const node of mut.addedNodes) {
                        // Walk added subtree for text nodes
                        (function walk(n) {
                            if (!n) return;
                            if (n.nodeType === Node.ELEMENT_NODE) {
                                if (skipTags.has(n.tagName)) return;
                                if (n.checkVisibility ? !n.checkVisibility() : false) return;
                                for (const c of n.childNodes) walk(c);
                            } else if (n.nodeType === Node.TEXT_NODE) {
                                const text = n.textContent.trim();
                                if (text.length < \(minLength)) return;
                                const el = n.parentElement;
                                if (!el || el.hasAttribute('data-drome-safe')) return;
                                const xpath = getXPath(el);
                                if (seen.has(xpath)) return;
                                seen.add(xpath);
                                try {
                                    window.webkit.messageHandlers.dromeMutation.postMessage({
                                        text: text.slice(0, 500),
                                        xpath: xpath
                                    });
                                } catch(e) {}
                            }
                        })(node);
                    }
                }
            });

            observer.observe(document.body, { childList: true, subtree: true });
            window.__dromeMutationObserver = observer;
        })();
        """
    }

    static func stopMutationObserverJS() -> String {
        """
        (function() {
            if (window.__dromeMutationObserver) {
                window.__dromeMutationObserver.disconnect();
                delete window.__dromeMutationObserver;
            }
        })();
        """
    }

    static func clearAILabelsJS() -> String {
        """
        (function() {
            document.querySelectorAll('[data-drome-safe]').forEach(el => {
                el.removeAttribute('data-drome-safe');
                el.removeAttribute('data-drome-label');
                el.removeAttribute('data-drome-reason');
            });
            document.getElementById('__drome_ai_style')?.remove();
        })();
        """
    }

    static func toggleReadingModeJS() -> String {
        """
        (function() {
            const MARKER = '__drome_reader_active';
            const existing = document.getElementById(MARKER);
            if (existing) {
                existing.remove();
                document.querySelectorAll('.__drome_reader_hide').forEach(el => el.style.display = '');
                const style = document.getElementById('__drome_reader_style');
                if (style) style.remove();
                return 'off';
            }
            const style = document.createElement('style');
            style.id = '__drome_reader_style';
            style.textContent = `
                body { max-width: 680px !important; margin: 24px auto !important; padding: 0 20px 60px !important;
                    font-family: -apple-system, Georgia, serif !important; font-size: 18px !important;
                    line-height: 1.75 !important; color: #1a1a1a !important; background: #fdfaf5 !important; }
                h1,h2,h3 { line-height: 1.3 !important; }
                img { max-width: 100% !important; height: auto !important; border-radius: 6px !important; }
                nav, header, footer, aside, [class*="sidebar"], [class*="ad"], [class*="banner"],
                [class*="promo"], [class*="social"], [class*="share"], [class*="comment"],
                [class*="related"], [class*="recommend"] { display: none !important; }
            `;
            document.head.appendChild(style);
            const marker = document.createElement('div');
            marker.id = MARKER;
            marker.style.display = 'none';
            document.body.appendChild(marker);
            return 'on';
        })()
        """
    }

    static func findSmallestContainerJS(xpath: String, text: String) -> String {
        let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\")
                              .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedXPath = xpath.replacingOccurrences(of: "\\", with: "\\\\")
                                .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        (function() {
            try {
                const result = document.evaluate("\(escapedXPath)", document, null,
                    XPathResult.FIRST_ORDERED_NODE_TYPE, null);
                let el = result.singleNodeValue;
                if (!el) return null;

                const offensiveText = "\(escapedText)";
                let candidate = el;
                let parent = el.parentElement;

                while (parent && parent !== document.body) {
                    const parentTextLen = parent.textContent.trim().length;
                    const elTextLen = candidate.textContent.trim().length;
                    if (parentTextLen > elTextLen * 1.8) break;
                    candidate = parent;
                    parent = parent.parentElement;
                }

                function getXPath(n) {
                    if (!n || n === document.body) return '/html/body';
                    const parts = [];
                    let node = n;
                    while (node && node.nodeType === 1 && node !== document.body) {
                        let idx = 1;
                        let sib = node.previousSibling;
                        while (sib) {
                            if (sib.nodeType === 1 && sib.tagName === node.tagName) idx++;
                            sib = sib.previousSibling;
                        }
                        parts.unshift(node.tagName.toLowerCase() + (idx > 1 ? '[' + idx + ']' : ''));
                        node = node.parentElement;
                    }
                    return parts.length ? '/html/body/' + parts.join('/') : '/html/body';
                }

                return getXPath(candidate);
            } catch(e) { return null; }
        })()
        """
    }
}
