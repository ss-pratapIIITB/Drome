// Drome content block extraction.
// Shared by the initial page scan and the mutation observer so both use the
// same visibility, de-duplication, and boilerplate rules.

(function(global) {
    'use strict';

    const MIN_LENGTH = 25;
    const MAX_CANDIDATES = 80;
    const MAX_TEXT = 500;
    // A real content block is a paragraph-sized unit. Larger elements are
    // layout containers (overlays, shells) and must not be classified or hidden
    // as a single unit.
    const MAX_BLOCK_CHARS = 1200;

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

    // Media candidates: images and videos are classified by their alt /
    // aria-label / title text so an unsafe thumbnail or poster is hidden like
    // any text block. Media without descriptive text stays untouched.
    const MEDIA_TAGS = new Set(['IMG', 'VIDEO']);
    const HEADING_TAGS = new Set(['H1', 'H2', 'H3', 'H4']);

    // Explicit terms that make even a very short alt text worth classifying.
    // Most explicit images carry no descriptive alt at all, but when they do
    // it is often two or three words ("nude models").
    const ADULT_HINT = /\b(porn|nude|naked|nsfw|xxx|onlyfans|erotic|sex\s*tape)\b/i;

    function mediaTextOf(el) {
        let text = (el.getAttribute && el.getAttribute('alt')) || '';
        if (!text) text = (el.getAttribute && el.getAttribute('aria-label')) || '';
        if (!text) text = (el.getAttribute && el.getAttribute('title')) || '';
        return normalize(text);
    }

    function hasMediaText(el) {
        const text = mediaTextOf(el);
        if (!text || !/\p{L}/u.test(text)) return false;
        return text.length >= MIN_LENGTH || ADULT_HINT.test(text);
    }

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

    // A block that already carries a verdict with the same fingerprint needs no
    // second model call. Back/forward restores keep their labels; an edited
    // block gets a new fingerprint and is scanned again.
    function alreadyClassified(el, fp) {
        const label = el.getAttribute && el.getAttribute('data-drome-safe');
        if (label !== '1' && label !== '0') return false;
        return el.getAttribute('data-drome-fingerprint') === fp;
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
                if (MEDIA_TAGS.has(node.tagName)) {
                    if (!isVisible(node)) return NodeFilter.FILTER_REJECT;
                    return hasMediaText(node) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
                }
                if (node.tagName === 'PICTURE') {
                    // Walk into <picture> so a qualifying inner <img> is reached.
                    if (!isVisible(node)) return NodeFilter.FILTER_REJECT;
                    return node.querySelector('img') ? NodeFilter.FILTER_SKIP : NodeFilter.FILTER_REJECT;
                }
                if (node.tagName === 'FORM') {
                    // Descend into forms: search suggestions and other rows live
                    // there, and they must be candidates in their own right so
                    // the form shell itself is never the thing that gets hidden.
                    return isVisible(node) ? NodeFilter.FILTER_SKIP : NodeFilter.FILTER_REJECT;
                }
                if (SKIP_TAGS.has(node.tagName)) return NodeFilter.FILTER_REJECT;
                if (!isVisible(node)) return NodeFilter.FILTER_REJECT;
                return NodeFilter.FILTER_ACCEPT;
            }
        });

        let node = walker.currentNode;
        while (node) {
            const isMedia = MEDIA_TAGS.has(node.tagName);
            if (node !== document.body && (isMedia || !INLINE_DISPLAYS.has(displayOf(node)))) {
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

            if (MEDIA_TAGS.has(el.tagName)) {
                const mediaText = mediaTextOf(el);
                if (!hasMediaText(el)) continue;
                if (seenText.has(mediaText)) continue;
                const mediaFingerprint = fingerprint(mediaText);
                if (alreadyClassified(el, mediaFingerprint)) continue;
                seenText.add(mediaText);
                const mediaID = stableID(el);
                candidates.push({
                    id: mediaID,
                    text: mediaText.slice(0, MAX_TEXT),
                    xpath: "//*[@data-drome-block-id='" + mediaID + "']",
                    fingerprint: mediaFingerprint,
                    heading: false
                });
                if (candidates.length >= MAX_CANDIDATES) break;
                continue;
            }

            // innerText only: textContent leaks CSS from inline <style> and
            // hidden template nodes into container blocks.
            const text = normalize(el.innerText || '');
            if (text.length < MIN_LENGTH) continue;
            if (text.length > MAX_BLOCK_CHARS) continue;
            if (!/\p{L}/u.test(text)) continue;
            // A block that contains form controls is a UI shell (search bar,
            // sign-in card), never a content unit to hide.
            if (el.querySelector('input, textarea, select')) continue;
            if (seenText.has(text)) continue;

            const linkChars = linkCharacterCount(el);
            if (linkChars > text.length * 0.6 && text.length < 300) continue;

            const textFingerprint = fingerprint(text);
            if (alreadyClassified(el, textFingerprint)) continue;

            seenText.add(text);
            const id = stableID(el);
            candidates.push({
                id: id,
                text: text.slice(0, MAX_TEXT),
                xpath: "//*[@data-drome-block-id='" + id + "']",
                fingerprint: textFingerprint,
                heading: HEADING_TAGS.has(el.tagName)
            });
            if (candidates.length >= MAX_CANDIDATES) break;
        }

        return candidates;
    }

    global.__dromeExtract = {
        collect: collect,
        normalize: normalize,
        fingerprint: fingerprint,
        resolveSection: resolveSection
    };

    // ── Section resolution ──────────────────────────────────────────────────
    // Given a leaf block flagged as unsafe, find the smallest ancestor that
    // represents the whole section (card, comment, ad unit) so hiding removes
    // the complete unit instead of only one leaf inside it.
    //
    // A step from the current subtree to its parent is allowed when PARENT
    // wraps exactly ONE unit's worth of content:
    //   - at most 6 element children (deep banner wrappers are absorbed),
    //   - and no OTHER content child of its own (>=120 chars) besides the
    //     subtree being absorbed — captions and short labels may ride along.
    // This refuses feed lists (many cards), article flow (many paragraphs)
    // and dialog wrappers that host unrelated content, so hiding never
    // swallows unrelated sections.
    const SECTION_BROAD = new Set([
        'BODY', 'HTML', 'MAIN', 'ARTICLE', 'SECTION', 'FORM', 'UL', 'OL',
        'TABLE', 'TD', 'TR', 'THEAD', 'TBODY', 'HEADER'
    ]);
    // Widget/navigation shells are never units to hide: climbing into a search
    // bar, listbox or menu would take their controls with the flagged row.
    const SECTION_WIDGET_ROLES = new Set([
        'search', 'combobox', 'textbox', 'listbox', 'menu', 'menubar',
        'toolbar', 'tablist', 'dialog', 'alertdialog', 'grid', 'tree'
    ]);
    // One-step absorbable widget items: hide the row itself, not its container.
    const SECTION_ITEM_ROLES = new Set(['option', 'menuitem', 'treeitem']);
    const SECTION_MAX_CARD_CHARS = 900;  // a unit cannot wrap more text than this
    const SECTION_UNIT_CHILDREN = 6;     // max element children of a unit-wrapping parent
    const SECTION_RIDE_ALONG = 120;      // max length of a sibling caption absorbed with the unit
    const SECTION_TEXT_GROWTH = 1.6;     // fallback: climb while ancestor adds little text
    const SECTION_MIN_CARD_CHARS = 40;   // too small a subtree: don't look for bigger units
    const SECTION_MAX_DEPTH = 24;        // safety cap on climb depth
    const MEASURE_CAP = 1020;            // walker stops once a subtree is provably over any threshold
    const MEASURE_NODE_CAP = 6000;       // hard bound on nodes visited per measurement
    const MEASURE_SKIP_TAGS = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEXTAREA', 'TEMPLATE']);

    // Memoized, whitespace-collapsed subtree text length. Walks TEXT nodes only
    // (their .data already exists — no string materialization), stops at the cap:
    // everything >= the cap is over SECTION_MAX_CARD_CHARS anyway, so larger
    // values cannot change any climb decision. Memo entries live as long as the
    // node does (WeakMap), so repeated climbs over shared chains cost nothing.
    const textLenCache = new WeakMap();

    function textLength(el) {
        const hit = textLenCache.get(el);
        if (hit !== undefined) return hit;
        let len = 0;
        let visited = 0;
        try {
            const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT, {
                acceptNode(node) {
                    const owner = node.parentElement;
                    return owner && !MEASURE_SKIP_TAGS.has(owner.tagName)
                        ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
                }
            });
            let text;
            let inSpaceRun = true; // leading spaces collapse
            while ((text = walker.nextNode())) {
                if (++visited > MEASURE_NODE_CAP) { len = MEASURE_CAP; break; }
                const data = text.data;
                for (let i = 0; i < data.length; i++) {
                    const code = data.charCodeAt(i);
                    const isSpace = code === 32 || (code >= 9 && code <= 13) ||
                        (code >= 0x2000 && code <= 0x200A) || code === 0xA0 ||
                        code === 0x202F || code === 0x205F || code === 0x3000;
                    if (isSpace) {
                        if (!inSpaceRun) { len++; inSpaceRun = true; }
                    } else {
                        len++; inSpaceRun = false;
                    }
                    if (len >= MEASURE_CAP) { len = MEASURE_CAP; break; }
                }
                if (len >= MEASURE_CAP) break;
            }
        } catch (e) {
            len = MEASURE_CAP;
        }
        textLenCache.set(el, len);
        return len;
    }

    function repeatedUnit(el) {
        // True when a sibling shares the structural signature (a list of
        // near-identical cards): the flagged unit is `el` itself.
        if (!el || !el.parentElement) return false;
        const parent = el.parentElement;
        const sig = childSignature(el);
        for (let i = 0; i < parent.children.length; i++) {
            const sib = parent.children[i];
            if (sib !== el && childSignature(sib) === sig) return true;
        }
        return false;
    }

    function childSignature(child) {
        // Cheap structural signature: tag + class tokens + text-size bucket.
        const classes = (child.getAttribute && (child.getAttribute('class') || '')) || '';
        return child.tagName + '|' + classes.split(/\s+/).filter(Boolean).length + '|' +
            Math.round(textLength(child) / 50);
    }

    function largestOtherContentChild(parent, current) {
        let largest = 0;
        for (let i = 0; i < parent.children.length; i++) {
            const child = parent.children[i];
            if (child === current) continue;
            const len = textLength(child);
            if (len >= 40 && len > largest) largest = len;
        }
        return largest;
    }

    function resolveSection(leaf) {
        if (!leaf || leaf === document.body) return leaf;
        let current = leaf;
        let depth = 0;
        while (current.parentElement && current.parentElement !== document.body && depth < SECTION_MAX_DEPTH) {
            depth++;
            const parent = current.parentElement;
            // Broad containers are climb stoppers, but only while they wrap
            // more than one unit's worth of text: news feeds render
            // card-level components as <article>/<section> (a 115-char
            // playlist item), and those must stay absorbable.
            if (SECTION_BROAD.has(parent.tagName) &&
                textLength(parent) > SECTION_MAX_CARD_CHARS) break;
            const role = parent.getAttribute('role');
            if (role === 'main' || role === 'contentinfo' || role === 'list') break;
            if (parent.tagName === 'FORM') break;
            if (parent.querySelector('input, textarea, select')) break;
            if (role && SECTION_ITEM_ROLES.has(role)) {
                // The row is the unit: absorb it and stop before the shell.
                current = parent;
                break;
            }
            if (role && SECTION_WIDGET_ROLES.has(role)) break;
            if (repeatedUnit(current)) break;

            const parentLen = textLength(parent);
            const currentLen = textLength(current);
            // Text fragments too small to anchor a unit keep the guard; a
            // zero-text subtree (media elements, image wrappers) has nothing
            // to lose by climbing, so it may continue into its card/figure.
            if (currentLen > 0 && currentLen < SECTION_MIN_CARD_CHARS) break;

            // The parent must still be a UNIT's worth of content.
            const otherChildren = largestOtherContentChild(parent, current);
            const isUnitParent = parent.childElementCount <= SECTION_UNIT_CHILDREN &&
                otherChildren <= SECTION_RIDE_ALONG;
            const isLowGrowthParent = (parentLen - currentLen) <= SECTION_MAX_CARD_CHARS &&
                (parentLen / Math.max(currentLen, 1)) <= SECTION_TEXT_GROWTH;

            if (!isUnitParent && !isLowGrowthParent) break;
            if (textLength(parent) > SECTION_MAX_CARD_CHARS &&
                !isLowGrowthParent) break;
            current = parent;
        }
        return current;
    }
})(window);
