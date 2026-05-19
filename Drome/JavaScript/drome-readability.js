// Drome Readability — lightweight content extraction
// Adapted from Mozilla's Readability algorithm (MIT license)

(function(global) {
    'use strict';

    const UNLIKELY = /banner|breadcrumbs|combx|comment|community|cover-wrap|disqus|extra|footer|header|legends|menu|related|remark|replies|rss|shoutbox|sidebar|skyscraper|social|sponsor|supplemental|ad-break|agegate|pagination|pager|popup|yom-remote/i;
    const POSITIVE = /article|body|content|entry|hentry|h-entry|main|page|pagination|post|text|blog|story/i;
    const NEGATIVE = /hidden|^hid$|hid$|hid|^hid |banner|combx|comment|com-|contact|foot|footer|footnote|gdpr|masthead|media|meta|outbrain|promo|related|scroll|share|shoutbox|sidebar|skyscraper|sponsor|shopping|tags|tool|widget/i;
    const BLOCK_TAGS = new Set(['DIV','P','BLOCKQUOTE','TABLE','UL','OL','ARTICLE','SECTION','LI','TD','H1','H2','H3','H4','H5','H6']);
    const DIV_LIKE_TAGS = new Set(['DIV','ARTICLE','SECTION','MAIN']);

    function getXPath(el) {
        if (!el || el === document.body) return '/html/body';
        const parts = [];
        let node = el;
        while (node && node.nodeType === 1 && node !== document.documentElement) {
            let idx = 1, sib = node.previousSibling;
            while (sib) {
                if (sib.nodeType === 1 && sib.tagName === node.tagName) idx++;
                sib = sib.previousSibling;
            }
            parts.unshift(node.tagName.toLowerCase() + (idx > 1 ? '[' + idx + ']' : ''));
            node = node.parentElement;
        }
        return '/' + parts.join('/');
    }

    function getInnerText(el, normalise = true) {
        const text = el.textContent || '';
        return normalise ? text.replace(/\s+/g, ' ').trim() : text;
    }

    function getCharCount(el, delim = ',') {
        return getInnerText(el).split(delim).length - 1;
    }

    function getLinkDensity(el) {
        const textLen = getInnerText(el).length;
        if (textLen === 0) return 0;
        let linkLen = 0;
        for (const a of el.querySelectorAll('a')) {
            linkLen += getInnerText(a).length;
        }
        return linkLen / textLen;
    }

    function initScore(el) {
        let score = 0;
        switch (el.tagName) {
            case 'DIV': score = 5; break;
            case 'PRE': case 'TD': case 'BLOCKQUOTE': score = 3; break;
            case 'ADDRESS': case 'OL': case 'UL': case 'DL':
            case 'DD': case 'DT': case 'LI': case 'FORM': score = -3; break;
            case 'H1': case 'H2': case 'H3': case 'H4':
            case 'H5': case 'H6': case 'TH': score = -5; break;
        }
        const cls = (el.className + ' ' + el.id).toLowerCase();
        if (POSITIVE.test(cls)) score += 25;
        if (NEGATIVE.test(cls)) score -= 25;
        return score;
    }

    function parse() {
        const candidates = new Map();

        // Score paragraphs and similar
        const nodes = document.body.querySelectorAll('p, td, pre');
        for (const node of nodes) {
            const text = getInnerText(node);
            if (text.length < 25) continue;

            const ancestors = [];
            let anc = node.parentElement;
            for (let i = 0; i < 3 && anc; i++, anc = anc.parentElement) {
                if (!BLOCK_TAGS.has(anc.tagName)) continue;
                ancestors.push(anc);
            }
            if (!ancestors.length) continue;

            const score = 1 + getCharCount(node) + Math.min(Math.floor(text.length / 100), 3);

            ancestors.forEach((anc, i) => {
                if (!candidates.has(anc)) {
                    candidates.set(anc, { el: anc, score: initScore(anc) });
                }
                const div = i === 0 ? 1 : i === 1 ? 2 : i * 3;
                candidates.get(anc).score += score / div;
            });
        }

        if (candidates.size === 0) return null;

        // Apply link density penalty
        let topCandidate = null, topScore = -Infinity;
        for (const [el, { score }] of candidates) {
            const adjusted = score * (1 - getLinkDensity(el));
            if (adjusted > topScore) {
                topScore = adjusted;
                topCandidate = el;
            }
        }

        return topCandidate;
    }

    function extractTextBlocks(container) {
        const blocks = [];
        const walker = document.createTreeWalker(
            container,
            NodeFilter.SHOW_TEXT,
            null
        );
        while (walker.nextNode()) {
            const node = walker.currentNode;
            const text = node.textContent.trim();
            if (text.length < 30) continue;
            const el = node.parentElement;
            if (!el) continue;
            const tag = el.tagName;
            if (tag === 'SCRIPT' || tag === 'STYLE') continue;
            blocks.push({
                text: text.slice(0, 600),
                xpath: getXPath(el),
                tag: tag.toLowerCase()
            });
        }
        return blocks;
    }

    // Exposed API
    global.__dromeReadability = {
        parse,
        extractTextBlocks,
        getXPath
    };

})(window);
