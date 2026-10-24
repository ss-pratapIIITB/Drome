import Foundation
import WebKit

enum JavaScriptInjector {

    static func makeBridgeScript() -> WKUserScript {
        WKUserScript(
            source: dromeBridgeJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    static func darkModeCSS() -> WKUserScript {
        let css = """
        html { filter: invert(1) hue-rotate(180deg) !important; }
        img, video, canvas, picture, svg { filter: invert(1) hue-rotate(180deg) !important; }
        """
        let js = """
        (function() {
            if (document.getElementById('__drome_dark')) return;
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

    static func applyFilterJS(xpaths: [String]) -> String {
        let pathsJSON = (try? String(data: JSONSerialization.data(withJSONObject: xpaths), encoding: .utf8)) ?? "[]"
        return """
        (function() {
            const styleID = '__drome_unsafe_style';
            if (!document.getElementById(styleID)) {
                const style = document.createElement('style');
                style.id = styleID;
                style.textContent = '.__drome_unsafe_hidden { display: none !important; }';
                document.head.appendChild(style);
            }
            const paths = \(pathsJSON);
            paths.forEach(xpath => {
                try {
                    const result = document.evaluate(xpath, document, null,
                        XPathResult.FIRST_ORDERED_NODE_TYPE, null);
                    const el = result.singleNodeValue;
                    if (!el) return;
                    el.classList.add('__drome_unsafe_hidden');
                    if (window.__dromeExtract && window.__dromeExtract.resolveSection) {
                        const section = window.__dromeExtract.resolveSection(el);
                        if (section && section !== document.body) {
                            section.classList.add('__drome_unsafe_hidden');
                        }
                    }
                } catch(e) {}
            });
        })();
        """
    }

    static func setUnsafeHiddenJS(_ hidden: Bool) -> String {
        """
        (function() {
            const className = '__drome_unsafe_hidden';
            const styleID = '__drome_unsafe_style';
            if (!document.getElementById(styleID)) {
                const style = document.createElement('style');
                style.id = styleID;
                style.textContent = '.' + className + ' { display: none !important; }';
                document.head.appendChild(style);
            }
            if (!\(hidden)) {
                // Restore removes the class everywhere: flagged leaves and the
                // sections they resolved to are both tagged with the class.
                document.querySelectorAll('.' + className).forEach(el => {
                    el.classList.remove(className);
                });
                return;
            }
            document.querySelectorAll('[data-drome-safe="0"]').forEach(el => {
                el.classList.add(className);
                if (el.parentElement && el.parentElement.closest('.' + className)) return;
                if (window.__dromeExtract && window.__dromeExtract.resolveSection) {
                    const section = window.__dromeExtract.resolveSection(el);
                    if (section && section !== document.body) {
                        section.classList.add(className);
                    }
                }
            });
        })();
        """
    }

    static func extractContentBlocksJS() -> String {
        """
        (function() {
            try {
                if (!window.__dromeExtract) return '[]';
                return JSON.stringify(window.__dromeExtract.collect(document.body));
            } catch (e) {
                return '[]';
            }
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

    /// Phase 1 — mark ALL candidate xpaths as pending (blue) in one JS call.
    /// When `showMarkers` is off the shared chip/outline CSS is not injected
    /// and pending decoration is skipped: flagged blocks later go straight to
    /// silent hiding (`__drome_unsafe_hidden`) with no visible boxes.
    static func markAllPendingJS(candidates: [PageScanCandidate], showMarkers: Bool) -> String {
        let payload = candidates.map { ["xpath": $0.xpath, "fingerprint": $0.fingerprint] }
        let json = (try? String(data: JSONSerialization.data(withJSONObject: payload), encoding: .utf8)) ?? "[]"
        let css = aiLabelCSS.replacingOccurrences(of: "`", with: "\\`")
        return """
        (function() {
            if (\(showMarkers) && !document.getElementById('__drome_ai_style')) {
                const s = document.createElement('style');
                s.id = '__drome_ai_style';
                s.textContent = `\(css)`;
                document.head.appendChild(s);
            }
            const candidates = \(json);
            candidates.forEach(function(candidate) {
                try {
                    const res = document.evaluate(candidate.xpath, document, null,
                        XPathResult.FIRST_ORDERED_NODE_TYPE, null);
                    const el = res.singleNodeValue;
                    if (!el) return;
                    const known = el.hasAttribute('data-drome-safe')
                        && el.getAttribute('data-drome-fingerprint') === candidate.fingerprint;
                    if (known) return;
                    // New or changed content: un-hide until it is classified again.
                    el.classList.remove('__drome_unsafe_hidden');
                    if (!\(showMarkers)) return;
                    el.setAttribute('data-drome-safe', 'pending');
                    el.setAttribute('data-drome-label', '⏳');
                } catch(e) {}
            });
        })();
        """
    }

    /// Toggles the visible scan-marker CSS (outlines + label chips). The
    /// `data-drome-safe` attributes stay on elements either way — hiding and
    /// re-hiding logic never depends on the markers being visible.
    static func setMarkersJS(_ show: Bool) -> String {
        let css = aiLabelCSS.replacingOccurrences(of: "`", with: "\\`")
        return """
        (function() {
            const style = document.getElementById('__drome_ai_style');
            if (\(show)) {
                if (style) return;
                const s = document.createElement('style');
                s.id = '__drome_ai_style';
                s.textContent = `\(css)`;
                document.head.appendChild(s);
            } else if (style) {
                style.remove();
            }
        })();
        """
    }

    /// Phase 2 — update a single element from pending → safe/unsafe
    static func updateLabelJS(
        candidate: PageScanCandidate,
        isSafe: Bool,
        reason: String,
        hideUnsafe: Bool
    ) -> String {
        let safeVal = isSafe ? "1" : "0"
        let labelText = isSafe ? "✓ Safe" : "⚠ Unsafe"
        let esc = { (s: String) in s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") }
        return """
        (function() {
            try {
                const res = document.evaluate('\(esc(candidate.xpath))', document, null,
                    XPathResult.FIRST_ORDERED_NODE_TYPE, null);
                const el = res.singleNodeValue;
                if (!el) return;
                el.setAttribute('data-drome-safe', '\(safeVal)');
                el.setAttribute('data-drome-label', '\(labelText)');
                el.setAttribute('data-drome-reason', '\(esc(reason))');
                el.setAttribute('data-drome-fingerprint', '\(esc(candidate.fingerprint))');
                el.classList.\(!isSafe && hideUnsafe ? "add" : "remove")('__drome_unsafe_hidden');
                if (!isSafe && hideUnsafe && window.__dromeExtract && window.__dromeExtract.resolveSection) {
                    const section = window.__dromeExtract.resolveSection(el);
                    if (section && section !== document.body) {
                        section.classList.add('__drome_unsafe_hidden');
                    }
                }
            } catch(e) {}
        })();
        """
    }

    struct LabelUpdate {
        let xpath: String
        let fingerprint: String
        let isSafe: Bool
        let reason: String
        let hideUnsafe: Bool
    }

    /// Phase 2 (batched) — apply one model batch's labels in a single JS call.
    static func updateLabelsJS(_ updates: [LabelUpdate]) -> String {
        let payload = updates.map { update in
            [
                "xpath": update.xpath,
                "fingerprint": update.fingerprint,
                "safe": update.isSafe,
                "reason": update.reason,
                "hideUnsafe": update.hideUnsafe,
            ] as [String: Any]
        }
        let json = (try? String(data: JSONSerialization.data(withJSONObject: payload), encoding: .utf8)) ?? "[]"
        return """
        (function() {
            const updates = \(json);
            updates.forEach(function(update) {
                try {
                    const res = document.evaluate(update.xpath, document, null,
                        XPathResult.FIRST_ORDERED_NODE_TYPE, null);
                    const el = res.singleNodeValue;
                    if (!el) return;
                    el.setAttribute('data-drome-safe', update.safe ? '1' : '0');
                    el.setAttribute('data-drome-label', update.safe ? '✓ Safe' : '⚠ Unsafe');
                    el.setAttribute('data-drome-reason', update.reason);
                    el.setAttribute('data-drome-fingerprint', update.fingerprint);
                    if (update.hideUnsafe && !update.safe) {
                        el.classList.add('__drome_unsafe_hidden');
                        // Skip resolution when an ancestor unit is already hidden:
                        // the parent covers this leaf, resolving again is wasted work.
                        const covered = el.parentElement && el.parentElement.closest('.__drome_unsafe_hidden');
                        if (!covered && window.__dromeExtract && window.__dromeExtract.resolveSection) {
                            const section = window.__dromeExtract.resolveSection(el);
                            if (section && section !== document.body) {
                                section.classList.add('__drome_unsafe_hidden');
                            }
                        }
                    } else {
                        el.classList.remove('__drome_unsafe_hidden');
                    }
                } catch(e) {}
            });
        })();
        """
    }

    static func labelElementJS(xpath: String, isSafe: Bool, reason: String) -> String {
        let safeVal = isSafe ? "1" : "0"
        let labelText = isSafe ? "✓ Safe" : "⚠ Unsafe"
        let escapedXPath = xpath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "'", with: "\\'")
        let escapedReason = reason
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return """
        (function() {
            try {
                // Inject shared CSS once
                if (!document.getElementById('__drome_ai_style')) {
                    const s = document.createElement('style');
                    s.id = '__drome_ai_style';
                    s.textContent = `
                        [data-drome-safe] {
                            outline: 2px solid rgba(34,197,94,0.45) !important;
                            outline-offset: 1px;
                        }
                        [data-drome-safe="0"] {
                            outline: 2px solid rgba(239,68,68,0.45) !important;
                        }
                        [data-drome-safe]::before {
                            content: attr(data-drome-label) !important;
                            display: inline-block !important;
                            padding: 0px 5px !important;
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
                        [data-drome-safe="1"]::before { background: rgba(22,163,74,0.88) !important; }
                        [data-drome-safe="0"]::before { background: rgba(220,38,38,0.88) !important; }
                    `;
                    document.head.appendChild(s);
                }
                const res = document.evaluate('\(escapedXPath)', document, null,
                    XPathResult.FIRST_ORDERED_NODE_TYPE, null);
                const el = res.singleNodeValue;
                if (!el || el.hasAttribute('data-drome-safe')) return;
                el.setAttribute('data-drome-safe', '\(safeVal)');
                el.setAttribute('data-drome-label', '\(labelText)');
                el.setAttribute('data-drome-reason', '\(escapedReason)');
            } catch(e) { console.error('[Drome AI] label error', e); }
        })();
        """
    }

    /// Inject a MutationObserver that fires dromeMutation messages for newly added text nodes
    /// not yet labeled. Debouncing happens on the Swift side.
    static func injectMutationObserverJS() -> String {
        """
        (function() {
            if (window.__dromeMutationObserver) return; // already running
            if (!window.__dromeExtract) return;

            const pending = new Map();
            let flushTimer = null;

            function queue(root) {
                if (!root) return;
                const candidates = window.__dromeExtract.collect(root);
                for (const candidate of candidates) pending.set(candidate.id, candidate);
            }

            function scheduleFlush() {
                clearTimeout(flushTimer);
                flushTimer = setTimeout(function() {
                    const candidates = Array.from(pending.values());
                    pending.clear();
                    candidates.forEach(candidate => {
                        try { window.webkit.messageHandlers.dromeMutation.postMessage(candidate); } catch(e) {}
                    });
                }, 150);
            }

            function isOnlyDromeClassChange(mut) {
                if (mut.type !== 'attributes' || mut.attributeName !== 'class') return false;
                const clean = value => (value || '').split(/\\s+/).filter(Boolean)
                    .filter(name => name !== '__drome_unsafe_hidden').sort().join(' ');
                return clean(mut.oldValue) === clean(mut.target.getAttribute('class'));
            }

            const observer = new MutationObserver(function(mutations) {
                for (const mut of mutations) {
                    if (isOnlyDromeClassChange(mut)) continue;
                    if (mut.type === 'characterData') {
                        queue(mut.target.parentElement);
                    } else if (mut.type === 'attributes') {
                        queue(mut.target);
                    } else {
                        for (const node of mut.addedNodes) {
                            if (node.nodeType === Node.TEXT_NODE) queue(node.parentElement);
                            else if (node.nodeType === Node.ELEMENT_NODE) queue(node);
                        }
                    }
                }
                if (pending.size) scheduleFlush();
            });

            observer.observe(document.body, {
                childList: true,
                characterData: true,
                attributes: true,
                attributeOldValue: true,
                attributeFilter: ['hidden', 'open', 'aria-expanded', 'class', 'style'],
                subtree: true
            });
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
                el.removeAttribute('data-drome-fingerprint');
                el.classList.remove('__drome_unsafe_hidden');
            });
            document.querySelectorAll('.__drome_unsafe_hidden').forEach(el => {
                el.classList.remove('__drome_unsafe_hidden');
            });
            document.getElementById('__drome_ai_style')?.remove();
            document.getElementById('__drome_unsafe_style')?.remove();
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
