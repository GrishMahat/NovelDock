// ═══════════════════════════════════════════════════════════════
// NovelDock Provider Helpers, bundled with the app.
//
// Injected into every provider's JS runtime before the provider source
// loads. Providers can (and should) use these instead of reimplementing
// the same plumbing. Do NOT copy these helpers into providers.
//
// Contract for writing a provider:
//
//   register({
//     id: "mysite",            // required, unique
//     name: "MySite",          // required, display name
//     baseUrl: "https://...",  // required
//     lang: "en",              // optional, default "en"
//     flags: { ... },          // optional, extra feature flags
//     filters: [ ... ],        // optional, filter defs (getFilters)
//     mainPageUrl: fn,         // optional → getMainPageUrl(page, filters)
//     latestUrl: fn,           // optional → getLatestUrl(page, filters)
//     searchConfig: fn,        // optional → getSearchConfig() (POST search)
//     searchUrl: fn,           // required → getSearchUrl(query, page, filters)
//     searchResults: fn,       // required → parseSearchResults(html)
//     novelInfoUrl: fn,        // optional, default identity
//     novelInfo: fn,           // required → parseNovelInfo(html)
//     chaptersApiUrl: fn,      // optional → getChaptersApiUrl(bookId, page)
//     chapterList: fn,         // optional → parseChapterList(html)
//     chapterContentUrl: fn,   // optional, default identity
//     chapterContent: fn,      // required → parseChapterContent(html)
//   });
//
// Standard empty results a provider must return when it cannot parse:
//   searchResults → { results: [], hasNextPage: false }
//   novelInfo     → { title:"", author:null, cover:null, status:null,
//                     genres:[], description:"", chapters:[] }
//   chapterContent → { html: "", images: [] }
// ═══════════════════════════════════════════════════════════════

/// Resolve a possibly-relative URL against the site base URL.
/// Returns null when [url] is falsy.
function absUrl(base, url) {
  if (!url) return url;
  if (url.indexOf("http://") === 0 || url.indexOf("https://") === 0) return url;
  if (url.indexOf("//") === 0) return "https:" + url;
  if (url.indexOf("/") === 0) return base + url;
  return base + "/" + url;
}

/// Strip HTML tags, decode entities, collapse whitespace, trim.
function textOf(html) {
  if (!html) return "";
  return unescapeHtml(html.replace(/<[^>]*>/g, " "))
    .replace(/\s+/g, " ")
    .trim();
}

/// Decode common HTML entities (named + numeric).
function unescapeHtml(str) {
  if (!str) return "";
  return str
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&#(\d+);/g, function(_, n) { return String.fromCharCode(parseInt(n, 10)); })
    .replace(/&#x([0-9a-fA-F]+);/g, function(_, n) { return String.fromCharCode(parseInt(n, 16)); });
}

/// First match of [re] against [html]; returns the first capture group,
/// or null when there is no match. Use for "extract one value" patterns:
///   var title = first(html, /<h1>([^<]*)<\/h1>/);
function first(html, re) {
  if (!html) return null;
  var m = re.exec(html);
  return m ? m[1] : null;
}

/// All matches of [re] against [html] as an array of match arrays
/// (like String.prototype.match with the /g flag, but zero-length matches
/// cannot loop forever). Use for "extract a list of elements" patterns:
///   var items = matchAll(html, /<li[^>]*>([\s\S]*?)<\/li>/g);
function matchAll(html, re) {
  var matches = [];
  if (!html) return matches;
  var regex = re.global ? re : new RegExp(re.source, re.flags + "g");
  var m;
  while ((m = regex.exec(html)) !== null) {
    matches.push(m);
    if (m[0].length === 0) regex.lastIndex++;
  }
  return matches;
}

/// Value of the first `name="..."` attribute inside [html], or null.
/// Use for lazy-loaded images:
///   var cover = attr(coverEl, "data-src") || attr(coverEl, "src");
function attr(html, name) {
  if (!html) return null;
  var m = new RegExp(name + '="([^"]*)"').exec(html);
  return m ? m[1] : null;
}

/// Build the standard provider export from a flat descriptor.
/// Missing optional functions get safe defaults; required ones must be
/// provided or the provider will fail validation.
function register(p) {
  var m = {
    id: p.id,
    name: p.name,
    baseUrl: p.baseUrl,
    lang: p.lang || "en",
  };
  if (p.version !== undefined) m.version = p.version;
  if (p.author !== undefined) m.author = p.author;
  if (p.nsfw !== undefined) m.nsfw = p.nsfw;

  var flags = p.flags || {};
  var hasBrowseConfig = typeof p.browseConfig === "function";
  var hasChaptersApiConfig = typeof p.chaptersApiConfig === "function";
  m.getProviderMetadata = function() {
    return {
      hasMainPage: !!p.mainPageUrl || hasBrowseConfig,
      hasSearch: true,
      hasLatest: !!p.latestUrl || hasBrowseConfig,
      hasFilters: !!(p.filters && p.filters.length),
      hasChapterApi: !!(p.chaptersApiUrl || hasChaptersApiConfig),
      searchFilters: flags.searchFilters === undefined ? true : !!flags.searchFilters,
    };
  };

  if (p.mainPageUrl) m.getMainPageUrl = p.mainPageUrl;
  if (p.latestUrl) m.getLatestUrl = p.latestUrl;
  if (p.filters) {
    m.getFilters = typeof p.filters === "function" ? p.filters : function() { return p.filters; };
  }
  if (p.searchConfig) m.getSearchConfig = p.searchConfig;
  m.getSearchUrl = p.searchUrl;
  m.parseSearchResults = p.searchResults;
  if (hasBrowseConfig) m.getBrowseConfig = p.browseConfig;
  m.getNovelInfoUrl = p.novelInfoUrl || function(novelUrl) { return novelUrl; };
  m.parseNovelInfo = p.novelInfo;
  if (p.chaptersApiUrl) m.getChaptersApiUrl = p.chaptersApiUrl;
  if (hasChaptersApiConfig) m.getChaptersApiConfig = p.chaptersApiConfig;
  if (p.chapterList) m.parseChapterList = p.chapterList;
  m.getChapterContentUrl = p.chapterContentUrl || function(chapterUrl) { return chapterUrl; };
  m.parseChapterContent = p.chapterContent;

  module.exports = m;
}

// ─────────────────────────────────────────────────────────────────────────────
// Protobuf + gRPC-Web helpers (for API-based providers like WuxiaWorld).
//
// Wire-format notes (mirrors the Kotlin provider's protobuf code):
//  - protoEncode(pairs): pairs are [field, value] with value being a number
//    (varint, wire type 0), a string (wire type 2), or a nested array of
//    pairs (embedded message). Pairs are sorted by field id.
//  - gRPC-Web framing: [flag(1B) + big-endian length(4B) + payload].
//    flag 0 = data frame, flag 0x80 = trailer frame.
//  - Response bodies arrive as byte arrays (Dart List<int> → JS array),
//    because the app requests them with a binary response type.
// ─────────────────────────────────────────────────────────────────────────────

function _utf8Bytes(str) {
  var bytes = [];
  for (var i = 0; i < str.length; i++) {
    var c = str.charCodeAt(i);
    if (c < 0x80) {
      bytes.push(c);
    } else if (c < 0x800) {
      bytes.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    } else if (c >= 0xd800 && c < 0xdc00 && i + 1 < str.length) {
      var c2 = str.charCodeAt(i + 1);
      if (c2 >= 0xdc00 && c2 < 0xe000) {
        var cp = 0x10000 + ((c - 0xd800) << 10) + (c2 - 0xdc00);
        bytes.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3f),
          0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
        i++;
      } else {
        bytes.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
      }
    } else if (c < 0x10000) {
      bytes.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    } else {
      bytes.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 0x3f),
        0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    }
  }
  return bytes;
}

function _utf8Decode(bytes, start, end) {
  var s = '';
  for (var i = start; i < end; i++) {
    var b = bytes[i];
    if (b < 0x80) {
      s += String.fromCharCode(b);
    } else if (b < 0xe0 && i + 1 < end) {
      s += String.fromCharCode(((b & 0x1f) << 6) | (bytes[++i] & 0x3f));
    } else if (b < 0xf0 && i + 2 < end) {
      s += String.fromCharCode(((b & 0x0f) << 12) | ((bytes[++i] & 0x3f) << 6) | (bytes[++i] & 0x3f));
    } else if (i + 3 < end) {
      var cp = ((b & 0x07) << 18) | ((bytes[++i] & 0x3f) << 12) |
        ((bytes[++i] & 0x3f) << 6) | (bytes[++i] & 0x3f);
      s += String.fromCharCode(0xd800 + ((cp - 0x10000) >> 10),
        0xdc00 + ((cp - 0x10000) & 0x3ff));
    }
  }
  return s;
}

function _protoVarint(value) {
  var out = [];
  var v = value;
  if (v < 0) {
    // 64-bit two's complement (e.g. status = -1). After the low 7 bits
    // carry the sign, 9 continuation bytes of 0xFF remain, then 0x01.
    for (var i = 0; i < 9; i++) {
      out.push((v & 0x7f) | 0x80);
      v = Math.floor(v / 128);
    }
    out.push(1);
    return out;
  }
  while (true) {
    var b = v & 0x7f;
    v = Math.floor(v / 128);
    if (v === 0) {
      out.push(b);
      break;
    }
    out.push(b | 0x80);
  }
  return out;
}

/// Encode a protobuf message. `pairs` is a list of [field, value] entries;
/// values are numbers (varint), strings (UTF-8), or nested pair arrays.
/// Returns an array of bytes (JSON-serializable, mirrors Dart List<int>).
function protoEncode(pairs) {
  var out = [];
  var sorted = pairs.slice().sort(function(a, b) { return a[0] - b[0]; });
  for (var i = 0; i < sorted.length; i++) {
    var field = sorted[i][0];
    var value = sorted[i][1];
    var wire = typeof value === 'number' ? 0 : 2;
    var tag = _protoVarint((field << 3) | wire);
    if (typeof value === 'number') {
      out = out.concat(tag, _protoVarint(value));
    } else {
      var inner = typeof value === 'string' ? _utf8Bytes(value) : protoEncode(value);
      out = out.concat(tag, _protoVarint(inner.length), inner);
    }
  }
  return out;
}

/// Reader over a byte array (proto message). Methods mirror the Kotlin
/// ProtoReader: exhausted(), readVarint(), readString(), readBytes(n),
/// enter() (embedded message as a bounded sub-reader).
function protoReader(bytes, start, end) {
  var pos = start === undefined ? 0 : start;
  var limit = end === undefined ? bytes.length : end;
  var r = {
    exhausted: function() { return pos >= limit; },
    readVarint: function() {
      var result = 0;
      var shift = 0;
      while (true) {
        var b = bytes[pos++];
        result |= (b & 0x7f) << shift;
        if ((b & 0x80) === 0) break;
        shift += 7;
      }
      return result;
    },
    readString: function() {
      var len = r.readVarint();
      var s = _utf8Decode(bytes, pos, pos + len);
      pos += len;
      return s;
    },
    readBytes: function(len) {
      var out = bytes.slice(pos, pos + len);
      pos += len;
      return out;
    },
    enter: function() {
      var len = r.readVarint();
      var sub = protoReader(bytes, pos, pos + len);
      pos += len;
      return sub;
    },
  };
  return r;
}

/// Iterate gRPC-Web data frames, invoking `fn(payloadBytes)` for each
/// flag-0 frame. Trailer frames are skipped.
function grpcWebFrames(bytes, fn) {
  var pos = 0;
  while (pos + 5 <= bytes.length) {
    var flag = bytes[pos];
    var len = ((bytes[pos + 1] << 24) | (bytes[pos + 2] << 16) |
      (bytes[pos + 3] << 8) | bytes[pos + 4]) >>> 0;
    pos += 5;
    if (pos + len > bytes.length) break;
    if (flag === 0) fn(bytes.slice(pos, pos + len));
    pos += len;
  }
}

/// Wrap a proto message byte array in a single gRPC-Web data frame.
/// Returns a byte array ready to use as a POST body.
function grpcWebFrame(bytes) {
  var len = bytes.length;
  return [0, (len >>> 24) & 0xff, (len >>> 16) & 0xff, (len >>> 8) & 0xff, len & 0xff]
    .concat(bytes);
}