// Drome JS Bridge — injected at document start
// Intercepts console, network, errors and forwards to Swift

(function() {
    'use strict';

    const _send = (handler, data) => {
        try {
            window.webkit?.messageHandlers?.[handler]?.postMessage(data);
        } catch(e) {}
    };

    // ── Console interception ──────────────────────────────────────────────────

    // Cap serialized size — pages log huge objects in tight loops, and every
    // char crosses the JS→native bridge and lands in a SwiftUI-observed array
    const MAX_ARG_LEN = 2000;
    const _fmt = (args) => args.map(a => {
        if (a === null) return 'null';
        if (a === undefined) return 'undefined';
        let s;
        if (typeof a === 'object') {
            try { s = JSON.stringify(a); } catch { s = String(a); }
        } else {
            s = String(a);
        }
        return s.length > MAX_ARG_LEN ? s.slice(0, MAX_ARG_LEN) + '…' : s;
    }).join(' ');

    ['log', 'info', 'warn', 'error', 'debug', 'trace'].forEach(level => {
        const orig = console[level].bind(console);
        console[level] = function(...args) {
            _send('dromeConsole', {
                level,
                message: _fmt(args),
                source: document.currentScript?.src || window.location.href,
                timestamp: Date.now()
            });
            orig(...args);
        };
    });

    window.addEventListener('error', e => {
        _send('dromeConsole', {
            level: 'error',
            message: `${e.message} (${e.filename}:${e.lineno}:${e.colno})`,
            source: e.filename || window.location.href,
            line: e.lineno,
            column: e.colno,
            timestamp: Date.now()
        });
    });

    window.addEventListener('unhandledrejection', e => {
        _send('dromeConsole', {
            level: 'error',
            message: `Unhandled Promise Rejection: ${e.reason}`,
            source: window.location.href,
            timestamp: Date.now()
        });
    });

    // ── Network interception ──────────────────────────────────────────────────

    const _uid = () => Math.random().toString(36).slice(2, 11);

    // fetch
    const _origFetch = window.fetch;
    window.fetch = function(input, init = {}) {
        const url = input instanceof Request ? input.url : String(input);
        const method = ((init.method) || (input instanceof Request ? input.method : null) || 'GET').toUpperCase();
        const id = _uid();
        const t0 = Date.now();

        _send('dromeNetwork', { type: 'request', id, url, method, timestamp: t0 });

        return _origFetch.call(this, input, init).then(res => {
            // Size from the header only — clone().text() would buffer every
            // response body a second time just to measure it
            let size = 0;
            try { size = parseInt(res.headers.get('content-length') || '0', 10) || 0; } catch {}
            _send('dromeNetwork', {
                type: 'response', id, url, method,
                status: res.status,
                duration: Date.now() - t0,
                size,
                timestamp: Date.now()
            });
            return res;
        }).catch(err => {
            _send('dromeNetwork', { type: 'error', id, url, error: err.message, timestamp: Date.now() });
            throw err;
        });
    };

    // XHR
    const _origOpen = XMLHttpRequest.prototype.open;
    const _origSend = XMLHttpRequest.prototype.send;

    XMLHttpRequest.prototype.open = function(method, url, ...rest) {
        this.__dromeId = _uid();
        this.__dromeUrl = String(url);
        this.__dromeMethod = method.toUpperCase();
        _origOpen.call(this, method, url, ...rest);
    };

    XMLHttpRequest.prototype.send = function(body) {
        const { __dromeId: id, __dromeUrl: url, __dromeMethod: method } = this;
        const t0 = Date.now();

        if (id) {
            _send('dromeNetwork', { type: 'request', id, url, method, timestamp: t0 });

            this.addEventListener('load', () => {
                // responseText throws for non-text responseTypes (blob/arraybuffer)
                let size = 0;
                try { size = parseInt(this.getResponseHeader('content-length') || '0', 10) || 0; } catch {}
                if (!size) {
                    try {
                        if (!this.responseType || this.responseType === 'text') {
                            size = this.responseText?.length || 0;
                        }
                    } catch {}
                }
                _send('dromeNetwork', {
                    type: 'response', id, url, method,
                    status: this.status,
                    duration: Date.now() - t0,
                    size,
                    timestamp: Date.now()
                });
            });

            this.addEventListener('error', () => {
                _send('dromeNetwork', { type: 'error', id, url, error: 'XHR network error', timestamp: Date.now() });
            });

            this.addEventListener('abort', () => {
                _send('dromeNetwork', { type: 'error', id, url, error: 'XHR aborted', timestamp: Date.now() });
            });
        }

        _origSend.call(this, body);
    };

    // ── Performance / timing helper ───────────────────────────────────────────

    window.__dromePerf = () => {
        const nav = performance.getEntriesByType('navigation')[0];
        const resources = performance.getEntriesByType('resource');
        return {
            pageLoad: nav ? Math.round(nav.loadEventEnd - nav.startTime) : null,
            domContentLoaded: nav ? Math.round(nav.domContentLoadedEventEnd - nav.startTime) : null,
            resourceCount: resources.length,
            totalTransferSize: resources.reduce((s, r) => s + (r.transferSize || 0), 0)
        };
    };
})();
