// Drome content block extraction.
// Shared by the initial page scan and the mutation observer so both use the
// same visibility, de-duplication, and boilerplate rules.

(function(global) {
    'use strict';

    const MIN_LENGTH = 25;
    const MAX_CANDIDATES = 80;
    const MAX_TEXT = 500;

    const SKIP_TAGS = new Set([
        'SCRIPT', 'STYLE', 'NOSCRIPT', 'CODE', 'PRE', 'SVG', 'MATH',
        'NAV', 'FOOTER', 'ASIDE', 'BUTTON', 'FORM', 'SELECT', 'TEXTAREA',
        'LABEL', 'IFRAME', 'CANVAS', 'VIDEO', 'AUDIO', 'IMG', 'PICTURE',
        'INPUT', 'OPTION', 'OPTGROUP'
    ]);

    const SKIP_ROLES = new Set([
        'button', 'navigation', 'menu', 'menubar', 'toolbar', 'tablist',
        'search', 'dialog', 'alertdialog'
    ]);

    const INLINE_DISPLAYS = new Set([
        'inline', 'inline-block', 'inline-flex', 'inline-grid', 'contents'
    ]);

    function normalize(text) {
        return text.replace(/\s+/g, ' ').trim();
    }

    function fingerprint(text) {
        let hash = 5381;
        for (let i = 0; i < text.length; i++) {
            hash = ((hash << 5) + hash) ^ text.charCodeAt(i);
        }
        return (hash >>> 0).toString(36) + '-' + text.length;
    }

    function stableID(el) {
        let id = el.getAttribute('data-drome-block-id');
        if (!id) {
            global.__dromeBlockSequence = (global.__dromeBlockSequence || 0) + 1;
            id = 'block-' + global.__dromeBlockSequence;
            el.setAttribute('data-drome-block-id', id);
        }
        return id;
    }

    function linkCharacterCount(el) {
        let count = 0;
        const links = el.querySelectorAll('a');
        for (let i = 0; i < links.length; i++) {
            count += (links[i].innerText || links[i].textContent || '').length;
        }
        return count;
    }

    function collect(root) {
        const start = root && root.nodeType === Node.ELEMENT_NODE ? root : document.body;
        if (!start) return [];

        const visibility = new WeakMap();
        const displays = new WeakMap();

        function isVisible(el) {
            if (visibility.has(el)) return visibility.get(el);
            let visible = false;
            if (el.isConnected && !el.hidden && el.getAttribute('aria-hidden') !== 'true') {
                if (typeof el.checkVisibility === 'function') {
                    visible = el.checkVisibility({
                        checkOpacity: true,
                        checkVisibilityCSS: true
                    });
                } else {
                    const style = global.getComputedStyle(el);
                    visible = style.display !== 'none'
                        && style.visibility !== 'hidden'
                        && style.opacity !== '0'
                        && el.getClientRects().length > 0;
                }
            }
            visibility.set(el, visible);
            return visible;
        }

        function displayOf(el) {
            let display = displays.get(el);
            if (display === undefined) {
                display = global.getComputedStyle(el).display;
                displays.set(el, display);
            }
            return display;
        }

        const blocks = [];
        const walker = document.createTreeWalker(start, NodeFilter.SHOW_ELEMENT, {
            acceptNode(node) {
                if (SKIP_TAGS.has(node.tagName)) return NodeFilter.FILTER_REJECT;
                if (!isVisible(node)) return NodeFilter.FILTER_REJECT;
                return NodeFilter.FILTER_ACCEPT;
            }
        });

        let node = walker.currentNode;
        while (node) {
            if (node !== document.body && !INLINE_DISPLAYS.has(displayOf(node))) {
                blocks.push(node);
            }
            node = walker.nextNode();
        }

        const blockSet = new Set(blocks);
        const wrappers = new Set();
        for (let i = 0; i < blocks.length; i++) {
            let parent = blocks[i].parentElement;
            while (parent && parent !== document.body) {
                if (blockSet.has(parent)) {
                    wrappers.add(parent);
                    break;
                }
                parent = parent.parentElement;
            }
        }

        const seenText = new Set();
        const candidates = [];
        for (let i = 0; i < blocks.length; i++) {
            const el = blocks[i];
            if (wrappers.has(el) || el.isContentEditable) continue;

            const role = el.getAttribute('role');
            if (role && SKIP_ROLES.has(role)) continue;

            const text = normalize(el.innerText || el.textContent || '');
            if (text.length < MIN_LENGTH) continue;
            if (!/\p{L}/u.test(text)) continue;
            if (seenText.has(text)) continue;

            const linkChars = linkCharacterCount(el);
            if (linkChars > text.length * 0.6 && text.length < 300) continue;

            seenText.add(text);
            const id = stableID(el);
            candidates.push({
                id: id,
                text: text.slice(0, MAX_TEXT),
                xpath: "//*[@data-drome-block-id='" + id + "']",
                fingerprint: fingerprint(text)
            });
            if (candidates.length >= MAX_CANDIDATES) break;
        }

        return candidates;
    }

    global.__dromeExtract = {
        collect: collect,
        normalize: normalize,
        fingerprint: fingerprint
    };
})(window);
