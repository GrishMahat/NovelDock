// HTTP client — mirrors lib/core/network/client.dart.
//
// Same headers as the app (Firefox UA, no Referer), persistent cookie jar
// (like PersistCookieJar), retries with backoff on connection errors, and
// Cloudflare challenge detection.
//
// Transport mirrors the app's Http2Adapter: all HTTPS requests go over
// HTTP/2 with a persistent session per origin. Cloudflare-protected sites
// flag plain HTTP/1.1 with a 403 challenge, so there is deliberately NO
// HTTP/1.1 fallback here — a server without ALPN h2 surfaces as an error,
// which the app would also hit.

'use strict';

const fs = require('fs');
const path = require('path');
const http2 = require('http2');
const zlib = require('zlib');

const USER_AGENT =
  'Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0';
const ACCEPT =
  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';
const ACCEPT_LANGUAGE = 'en-US,en;q=0.5';

const REQUEST_TIMEOUT_MS = 30_000;
const MAX_RETRIES = 3;
const RETRY_BACKOFF_MS = [2_000, 4_000, 6_000];
const MAX_REDIRECTS = 5;

// Persistent HTTP/2 sessions per origin (mirrors ConnectionManager()).
const h2Sessions = new Map();

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Mirror of CloudflareHandler.isCloudflareChallenge().
function isCloudflareChallenge(status, html) {
  if (status !== 403 && status !== 503) return false;
  return /just a moment|attention required|cf-chl|cloudflare/i.test(html.slice(0, 10_000));
}

function decompress(encoding, buffer) {
  switch ((encoding || '').toLowerCase()) {
    case 'gzip':
      return zlib.gunzipSync(buffer);
    case 'deflate':
      return zlib.inflateSync(buffer);
    case 'br':
      return zlib.brotliDecompressSync(buffer);
    default:
      return buffer;
  }
}

function headersToRecord(h) {
  const out = {};
  for (const [k, v] of Object.entries(h)) {
    if (Array.isArray(v)) out[k] = v.join(', ');
    else out[k] = v;
  }
  return out;
}

// ─────────────────────────────────────────────────────────────
// HTTP/2 (primary, mirrors Http2Adapter)
// ─────────────────────────────────────────────────────────────

function getH2Session(origin) {
  let session = h2Sessions.get(origin);
  if (session && !session.closed && !session.destroyed) return session;
  session = http2.connect(origin, { ALPNProtocols: ['h2'] });
  session.on('error', () => {});
  h2Sessions.set(origin, session);
  return session;
}

function requestH2(session, headers, body, timeoutMs) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const done = (err, value) => {
      if (settled) return;
      settled = true;
      if (err) reject(err);
      else resolve(value);
    };

    let stream;
    try {
      stream = session.request(headers);
    } catch (e) {
      return done(e);
    }

    const timer = setTimeout(() => {
      stream.destroy();
      done(new Error('h2 timeout'));
    }, timeoutMs);

    const chunks = [];
    let response = null;
    stream.on('response', (h) => {
      response = {
        status: parseInt(h[':status'], 10) || 0,
        headers: headersToRecord(h),
      };
    });
    stream.on('data', (chunk) => chunks.push(chunk));
    stream.on('error', (e) => {
      clearTimeout(timer);
      done(e);
    });
    stream.on('end', () => {
      clearTimeout(timer);
      if (!response) return done(new Error('h2 no response'));
      done(null, { ...response, body: Buffer.concat(chunks) });
    });

    if (body) stream.end(body);
    else stream.end();
  });
}

// ─────────────────────────────────────────────────────────────
// Client
// ─────────────────────────────────────────────────────────────

class Client {
  // cookieFile: path to the JSON cookie jar (persisted between runs,
  // mirroring PersistCookieJar under the app's cookies dir).
  constructor(cookieFile) {
    this.cookieFile = cookieFile;
    this.cookies = this._loadCookies();
  }

  _loadCookies() {
    try {
      return JSON.parse(fs.readFileSync(this.cookieFile, 'utf8'));
    } catch {
      return [];
    }
  }

  _saveCookies() {
    fs.mkdirSync(path.dirname(this.cookieFile), { recursive: true });
    fs.writeFileSync(this.cookieFile, JSON.stringify(this.cookies, null, 2));
  }

  _cookieHeader(hostname) {
    const now = Math.floor(Date.now() / 1000);
    const parts = this.cookies
      .filter((c) => {
        const domain = String(c.domain || '').replace(/^\./, '');
        return (
          (c.expires === undefined ||
            c.expires === null ||
            c.expires > now) &&
          (hostname === domain || hostname.endsWith(`.${domain}`))
        );
      })
      .map((c) => `${c.name}=${c.value}`);
    return parts.length > 0 ? parts.join('; ') : null;
  }

  _storeCookies(hostname, setCookieHeaders) {
    if (!setCookieHeaders || setCookieHeaders.length === 0) return;
    for (const raw of setCookieHeaders) {
      const parsed = this._parseSetCookie(raw, hostname);
      if (!parsed) continue;
      const idx = this.cookies.findIndex(
        (c) =>
          c.name === parsed.name &&
          (c.domain === parsed.domain || c.domain === `.${parsed.domain}`),
      );
      if (idx >= 0) {
        this.cookies[idx] = parsed;
      } else {
        this.cookies.push(parsed);
      }
    }
    this._saveCookies();
  }

  _parseSetCookie(raw, hostname) {
    const parts = raw.split(';').map((p) => p.trim());
    const first = parts.shift();
    const eq = first.indexOf('=');
    if (eq <= 0) return null;
    const cookie = {
      name: first.slice(0, eq),
      value: first.slice(eq + 1),
      domain: hostname,
      path: '/',
    };
    for (const part of parts) {
      const [key, ...val] = part.split('=');
      const value = val.join('=');
      switch (key.toLowerCase()) {
        case 'domain':
          cookie.domain = value || hostname;
          break;
        case 'path':
          cookie.path = value || '/';
          break;
        case 'expires': {
          const t = Date.parse(value);
          cookie.expires = isNaN(t) ? undefined : Math.floor(t / 1000);
          break;
        }
        case 'max-age':
          cookie.expires =
            Math.floor(Date.now() / 1000) + (parseInt(value, 10) || 0);
          break;
      }
    }
    return cookie;
  }

  // Mirrors the app's GET flow (dio with cookie manager + retries).
  //   followRedirects=false mirrors dio.post(..., followRedirects: false)
  //   used by postSearch() so the 3xx Location can be read manually.
  async request({ url, method = 'GET', body, extraHeaders = {}, followRedirects = true }) {
    const started = Date.now();

    for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
      let res;
      try {
        res = await this._requestOnce(url, method, body, extraHeaders, followRedirects, REQUEST_TIMEOUT_MS);

        // Manual redirect following for h2 (node http2 has none).
        if (res.status >= 300 && res.status < 400 && res.headers.location && followRedirects) {
          for (let i = 0; i < MAX_REDIRECTS; i++) {
            const next = new URL(res.headers.location, res.url).toString();
            res = await this._requestOnce(next, 'GET', null, extraHeaders, true, REQUEST_TIMEOUT_MS);
          }
        }

        return {
          url: res.url,
          status: res.status,
          headers: res.headers,
          html: res.body.toString('utf8'),
          body: res.body,
          bytes: res.body.length,
          durationMs: Date.now() - started,
          note: isCloudflareChallenge(res.status, res.body.toString('utf8', 0, 10_000))
            ? 'cloudflare challenge detected'
            : null,
        };
      } catch (e) {
        if (attempt === MAX_RETRIES) {
          return {
            url,
            status: 0,
            headers: {},
            html: '',
            bytes: 0,
            durationMs: Date.now() - started,
            error: String((e && e.message) || e),
          };
        }
        await sleep(RETRY_BACKOFF_MS[attempt]);
      }
    }
  }

  async _requestOnce(url, method, body, extraHeaders, followRedirects, timeoutMs) {
    const u = new URL(url);
    const headers = {
      'user-agent': USER_AGENT,
      accept: ACCEPT,
      'accept-language': ACCEPT_LANGUAGE,
      'accept-encoding': 'gzip, deflate',
    };
    for (const [k, v] of Object.entries(extraHeaders)) {
      headers[k.toLowerCase()] = String(v);
    }
    const cookie = this._cookieHeader(u.hostname);
    if (cookie) headers.cookie = cookie;

    let result;
    let session = null;

    // HTTP/2 only (mirrors Http2Adapter; the app has no HTTP/1.1 path).
    if (u.protocol !== 'https:') {
      throw new Error(`Unsupported protocol: ${u.protocol}`);
    }
    const origin = u.origin;
    try {
      session = getH2Session(origin);
      const h2headers = {
        ':method': method,
        ':path': u.pathname + u.search,
        ':scheme': 'https',
        ':authority': u.host,
        ...headers,
      };
      if (body) h2headers['content-length'] = Buffer.byteLength(body);
      result = await requestH2(session, h2headers, body || undefined, timeoutMs);
    } catch (e) {
      // Session died (GOAWAY etc.) — retry once with a fresh session.
      h2Sessions.delete(origin);
      if (session && !session.destroyed) session.destroy();
      throw e;
    }
    result.url = u.toString();

    const rawBody = decompress(result.headers['content-encoding'], result.body);
    const encoding = (result.headers['content-encoding'] || '').toLowerCase();
    const isCompressed = ['gzip', 'deflate', 'br'].includes(encoding);

    // Store cookies (h2 returns an array; h1 may return a string).
    const setCookieHeaders = result.headers['set-cookie'];
    const cookies =
      typeof setCookieHeaders === 'string'
        ? [setCookieHeaders]
        : Array.isArray(setCookieHeaders)
          ? setCookieHeaders
          : [];
    this._storeCookies(u.hostname, cookies);

    return {
      status: result.status,
      headers: result.headers,
      body: isCompressed ? rawBody : result.body,
      url: result.url || u.toString(),
    };
  }
}

module.exports = {
  Client,
  USER_AGENT,
  ACCEPT,
  ACCEPT_LANGUAGE,
  isCloudflareChallenge,
};