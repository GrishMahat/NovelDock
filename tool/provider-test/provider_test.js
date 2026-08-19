#!/usr/bin/env node
// NovelDock provider test bench.
//
// Mirrors how the app drives providers (engine.dart + search_providers.dart)
// so results are representative of the real app:
//   - same Firefox 130 user agent / Accept headers, no Referer
//   - same POST search flow (getSearchConfig -> redirect -> parse)
//   - same module.exports JS wrapper + injected provider helpers
//   - HTTP/2 only, persistent cookie jar, retries, Cloudflare detection
//
// Output is the raw parsed JSON exactly as the app receives it
// (SearchResults / NovelInfo / ChapterContent), plus the full request and
// response saved under output/<timestamp>-<provider>/ per step.
//
// Usage:
//   node provider_test.js --list
//   node provider_test.js --provider wuxiabox --sweep [--query "martial god"]
//   node provider_test.js --provider wuxiabox --search --query "martial god"
//   node provider_test.js --provider allnovel --browse --page 2
//   node provider_test.js --provider wuxiabox --novel --novel-url <url>
//   node provider_test.js --provider wuxiabox --chapters --novel-url <url>
//   node provider_test.js --provider wuxiabox --content --chapter-url <url>
//   node provider_test.js                 (interactive menu)
//
// Non-interactive steps never apply filters (mirrors the app's default
// FilterValues). Interactive mode only prompts for filters when you
// explicitly enable them in the menu.

'use strict';

const fs = require('fs');
const path = require('path');
const readline = require('readline/promises');

const { listProviders, loadProvider, call, hasFunction } = require('./lib/engine');
const { Client } = require('./lib/client');
const { Session } = require('./lib/session');

const COOKIE_FILE = path.join(__dirname, 'output', 'cookies.json');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

const client = new Client(COOKIE_FILE);
let session = null;

function dump(value) {
  console.log(JSON.stringify(value, null, 2));
}

// ═════════════════════════════════════════════════════════════
// Steps (each mirrors the app's flow for that provider function)
// ═════════════════════════════════════════════════════════════

async function stepBrowse(provider, page, filters) {
  console.log(`\n── Browse (main page) page=${page} filters=${JSON.stringify(filters)} ──`);
  // POST browse (getBrowseConfig) — mirrors provider_screen.dart
  if (hasFunction(provider, 'getBrowseConfig')) {
    const config = call(provider, 'getBrowseConfig', ['main', filters]);
    if (config && typeof config === 'object' && config.url) {
      await stepPostConfig(provider, 'browse', config, `POST ${config.url}`);
      return;
    }
    console.log('getBrowseConfig returned nothing, falling through…');
  }
  const url = call(provider, 'getMainPageUrl', [page, filters]);
  if (!url) {
    console.log('Provider has no getMainPageUrl — nothing to do.');
    return;
  }
  console.log(`GET ${url}`);
  const res = await client.request({ url });
  const parsed = res.status === 200
    ? call(provider, 'parseSearchResults', [res.html])
    : null;
  session.addStep({ step: 'browse', request: { method: 'GET', url, headers: {} }, response: res, parsed });
  logResult(res, parsed);
}

async function stepLatest(provider, page, filters) {
  console.log(`\n── Latest updates page=${page} filters=${JSON.stringify(filters)} ──`);
  // POST browse (getBrowseConfig, latest mode) — mirrors provider_screen.dart
  if (hasFunction(provider, 'getBrowseConfig')) {
    const config = call(provider, 'getBrowseConfig', ['latest', filters]);
    if (config && typeof config === 'object' && config.url) {
      await stepPostConfig(provider, 'latest', config, `POST ${config.url}`);
      return;
    }
    console.log('getBrowseConfig returned nothing, falling through…');
  }
  const url = call(provider, 'getLatestUrl', [page, filters]);
  if (!url) {
    console.log('Provider has no getLatestUrl — nothing to do.');
    return;
  }
  console.log(`GET ${url}`);
  const res = await client.request({ url });
  const parsed = res.status === 200
    ? call(provider, 'parseSearchResults', [res.html])
    : null;
  session.addStep({ step: 'latest', request: { method: 'GET', url, headers: {} }, response: res, parsed });
  logResult(res, parsed);
}

// POST a {url, headers, body|fields} config and parse the response.
// Mirrors postNovelList() in search_providers.dart (binary + form bodies,
// redirect handling).
async function stepPostConfig(provider, stepName, config, label) {
  const headers = Object.fromEntries(
    Object.entries(config.headers || {}).map(([k, v]) => [k, String(v)]),
  );
  const isBinary = Array.isArray(config.body);
  console.log(label);
  const res = await client.request({
    url: config.url,
    method: 'POST',
    body: isBinary
      ? Buffer.from(config.body)
      : Object.entries({ ...(config.fields || {}), keyboard: config._query || '' })
          .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
          .join('&'),
    extraHeaders: isBinary
      ? headers
      : { ...headers, 'Content-Type': 'application/x-www-form-urlencoded' },
    followRedirects: false,
  });

  if (res.status === 200) {
    const data = isBinary ? Array.from(res.body) : res.html;
    const parsed = call(provider, 'parseSearchResults', [data]);
    session.addStep({ step: stepName, request: { method: 'POST', url: config.url, headers: res.headers, body: isBinary ? `binary(${res.bytes}B)` : 'form' }, response: res, parsed });
    logResult(res, parsed);
    return;
  }
  if ([301, 302, 303, 307, 308].includes(res.status) && res.headers.location) {
    const resultUrl = new URL(res.headers.location, config.url).toString();
    console.log(`Redirect → GET ${resultUrl}`);
    const res2 = await client.request({ url: resultUrl });
    const parsed = call(provider, 'parseSearchResults', [res2.html]);
    session.addStep({ step: `${stepName}Redirect`, request: { method: 'GET', url: resultUrl, headers: {} }, response: res2, parsed });
    logResult(res2, parsed);
    return;
  }
  logResult(res, null);
}

// Mirror of searchProviderOnce() in search_providers.dart:
// 1. POST search (getSearchConfig) when it exists
// 2. direct search()
// 3. GET via getSearchUrl
async function stepSearch(provider, query, page) {
  console.log(`\n── Search "${query}" (page ${page}) ──`);

  // 1. POST search
  if (hasFunction(provider, 'getSearchConfig')) {
    const config = call(provider, 'getSearchConfig', [query, page]);
    if (config && typeof config === 'object' && config.url) {
      const isBinary = Array.isArray(config.body);
      const headers = Object.fromEntries(
        Object.entries(config.headers || {}).map(([k, v]) => [k, String(v)]),
      );
      const formBody = isBinary
        ? null
        : Object.entries({ ...(config.fields || {}), keyboard: query })
            .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
            .join('&');
      console.log(`POST ${config.url}`);
      const res = await client.request({
        url: config.url,
        method: 'POST',
        body: isBinary ? Buffer.from(config.body) : formBody,
        extraHeaders: isBinary
          ? headers
          : {
              ...headers,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
        followRedirects: false,
      });

      if (res.status === 200) {
        const data = isBinary ? Array.from(res.body) : res.html;
        const parsed = call(provider, 'parseSearchResults', [data]);
        session.addStep({ step: 'searchPost', request: { method: 'POST', url: config.url, headers: res.headers, body: isBinary ? `binary(${res.bytes}B)` : formBody }, response: res, parsed });
        if (parsed && parsed.results && parsed.results.length > 0) {
          logResult(res, parsed);
          return;
        }
      } else if ([301, 302, 303, 307, 308].includes(res.status) && res.headers.location) {
        const resultUrl = new URL(res.headers.location, config.url).toString();
        console.log(`Redirect → GET ${resultUrl}`);
        const res2 = await client.request({ url: resultUrl });
        const parsed = call(provider, 'parseSearchResults', [res2.html]);
        session.addStep({ step: 'searchPostRedirect', request: { method: 'GET', url: resultUrl, headers: {} }, response: res2, parsed });
        if (parsed && parsed.results && parsed.results.length > 0) {
          logResult(res2, parsed);
          return;
        }
      }
      console.log('POST search yielded nothing, falling through…');
    }
  }

  // 2. Direct search()
  const direct = call(provider, 'search', [query, page]);
  if (direct && direct.results && direct.results.length > 0) {
    console.log('Direct search() results:');
    dump(direct);
    return;
  }

  // 3. GET search
  const url = call(provider, 'getSearchUrl', [query, page, {}]);
  if (!url) {
    console.log('No search URL either — provider cannot search.');
    return;
  }
  console.log(`GET ${url}`);
  const res = await client.request({ url });
  const parsed = res.status === 200
    ? call(provider, 'parseSearchResults', [res.html])
    : null;
  session.addStep({ step: 'searchGet', request: { method: 'GET', url, headers: {} }, response: res, parsed });
  logResult(res, parsed);
}

async function stepNovel(provider, novelUrl) {
  console.log(`\n── Novel info: ${novelUrl} ──`);
  const url = call(provider, 'getNovelInfoUrl', [novelUrl]);
  console.log(`GET ${url}`);
  const res = await client.request({ url });
  const parsed = res.status === 200
    ? call(provider, 'parseNovelInfo', [res.html])
    : null;
  session.addStep({ step: 'novelInfo', request: { method: 'GET', url, headers: {} }, response: res, parsed });
  logResult(res, parsed);
  return parsed;
}

async function stepChapters(provider, bookId, page = 0) {
  console.log(`\n── Chapter list bookId=${bookId} page=${page} ──`);
  // POST chapters (getChaptersApiConfig) — mirrors novel_opener.dart
  if (hasFunction(provider, 'getChaptersApiConfig')) {
    const config = call(provider, 'getChaptersApiConfig', [bookId, page]);
    if (config && typeof config === 'object' && config.url) {
      const headers = Object.fromEntries(
        Object.entries(config.headers || {}).map(([k, v]) => [k, String(v)]),
      );
      console.log(`POST ${config.url}`);
      const res = await client.request({
        url: config.url,
        method: 'POST',
        body: Array.isArray(config.body) ? Buffer.from(config.body) : null,
        extraHeaders: headers,
        followRedirects: false,
      });
      const data = res.status === 200 && Array.isArray(config.body)
        ? Array.from(res.body)
        : res.html;
      const parsed = res.status === 200
        ? call(provider, 'parseChapterList', [data])
        : null;
      session.addStep({ step: 'chapters', request: { method: 'POST', url: config.url, headers: res.headers, body: `binary(${res.bytes}B)` }, response: res, parsed });
      logResult(res, parsed);
      return parsed;
    }
    console.log('getChaptersApiConfig returned nothing, falling through…');
  }
  const url = call(provider, 'getChaptersApiUrl', [bookId, page]);
  if (!url) {
    console.log('Provider has no getChaptersApiUrl — chapters are in parseNovelInfo.');
    return null;
  }
  console.log(`GET ${url}`);
  const res = await client.request({ url });
  const parsed = res.status === 200
    ? call(provider, 'parseChapterList', [res.html])
    : null;
  session.addStep({ step: 'chapters', request: { method: 'GET', url, headers: {} }, response: res, parsed });
  logResult(res, parsed);
  return parsed;
}

async function stepContent(provider, chapterUrl) {
  console.log(`\n── Chapter content: ${chapterUrl} ──`);
  const url = call(provider, 'getChapterContentUrl', [chapterUrl]);
  console.log(`GET ${url}`);
  const res = await client.request({ url });
  const parsed = res.status === 200
    ? call(provider, 'parseChapterContent', [res.html])
    : null;
  session.addStep({ step: 'chapterContent', request: { method: 'GET', url, headers: {} }, response: res, parsed });
  logResult(res, parsed);
}

// Logs the HTTP result header line, then the parsed JSON exactly as the
// app receives it.
function logResult(res, parsed) {
  console.log(`status=${res.status} bytes=${res.bytes} duration=${res.durationMs}ms`);
  if (res.note) console.log(`NOTE: ${res.note}`);
  if (res.error) console.log(`ERROR: ${res.error}`);
  if (parsed !== null && parsed !== undefined) {
    dump(parsed);
  } else if (res.status === 200) {
    console.log('(parse returned null)');
  }
}

// ═════════════════════════════════════════════════════════════
// Interactive menu
// ═════════════════════════════════════════════════════════════

// Filter values to apply on browse/latest. Empty object = none, and the
// prompt only appears when the user explicitly enables filters (option 8).
let activeFilters = {};

async function askFilters(provider) {
  const filters = call(provider, 'getFilters', []);
  if (!Array.isArray(filters) || filters.length === 0) {
    console.log('Provider declares no filters.');
    return {};
  }
  console.log('\nFilter values (Enter = keep current / skip):');
  const out = {};
  for (const f of filters) {
    if (!f || !f.id) continue;
    const opts = Array.isArray(f.options) ? f.options : [];
    console.log(`  ${f.name || f.id} (${f.type}):`);
    opts.forEach((o, i) => console.log(`    [${i}] ${o}`));
    const answer = await rl.question(`  index for "${f.id}" > `);
    if (answer.trim() === '') continue;
    const idx = parseInt(answer, 10);
    if (isNaN(idx) || idx < 0 || idx >= opts.length) continue;
    if (f.type === 'sort') {
      const asc = await rl.question('  ascending? (y/N) > ');
      out[f.id] = [idx, asc.trim().toLowerCase() === 'y'];
    } else {
      out[f.id] = idx;
    }
  }
  return out;
}

async function interactive(provider) {
  while (true) {
    console.log(`\nProvider: ${provider.id} (${provider.entry.version})`);
    console.log('  1) Metadata + exported functions');
    console.log('  2) Browse main page');
    console.log('  3) Latest updates');
    console.log('  4) Search');
    console.log('  5) Novel info (paste URL)');
    console.log('  6) Chapters (AJAX, from novel info bookId)');
    console.log('  7) Chapter content (paste URL)');
    console.log(`  8) Apply filters (currently: ${Object.keys(activeFilters).length ? JSON.stringify(activeFilters) : 'none'})`);
    console.log('  9) Full sweep');
    console.log('  0) Exit');
    const choice = await rl.question('> ');

    switch (choice.trim()) {
      case '1': {
        const meta = call(provider, 'getProviderMetadata', []);
        console.log('\nMetadata:');
        dump(meta);
        console.log('Exported:', provider.exported.join(', '));
        console.log('Filters:');
        dump(call(provider, 'getFilters', []));
        break;
      }
      case '2': {
        const page = parseInt(await rl.question('page > '), 10) || 1;
        await stepBrowse(provider, page, activeFilters);
        break;
      }
      case '3': {
        const page = parseInt(await rl.question('page > '), 10) || 1;
        await stepLatest(provider, page, activeFilters);
        break;
      }
      case '4': {
        const query = await rl.question('query > ');
        const page = parseInt(await rl.question('page > '), 10) || 1;
        await stepSearch(provider, query, page);
        break;
      }
      case '5': {
        const url = await rl.question('novel URL > ');
        await stepNovel(provider, url.trim());
        break;
      }
      case '6': {
        const bookId = (await rl.question('bookId (from novel info) > ')).trim();
        await stepChapters(provider, bookId);
        break;
      }
      case '7': {
        const url = await rl.question('chapter URL > ');
        await stepContent(provider, url.trim());
        break;
      }
      case '8':
        activeFilters = await askFilters(provider);
        break;
      case '9':
        await sweep(provider, null);
        break;
      case '0':
        rl.close();
        return;
      default:
        console.log('Unknown choice.');
    }
  }
}

// ═════════════════════════════════════════════════════════════
// Full sweep (no filters — mirrors the app's default FilterValues)
// ═════════════════════════════════════════════════════════════

async function sweep(provider, query) {
  const meta = call(provider, 'getProviderMetadata', []);
  console.log('Metadata:');
  dump(meta);

  if (meta.hasMainPage !== false) {
    await stepBrowse(provider, 1, {});
  }
  if (meta.hasLatest !== false) {
    await stepLatest(provider, 1, {});
  }
  if (meta.hasSearch !== false) {
    const q = query || (await rl.question('search query > ')).trim();
    await stepSearch(provider, q || 'martial god', 1);
  }

  // Novel from the most recent search/browse result set
  let novelUrl = null;
  for (let i = session.steps.length - 1; i >= 0; i--) {
    const s = session.steps[i];
    if (s.parsed && Array.isArray(s.parsed.results) && s.parsed.results.length > 0) {
      novelUrl = s.parsed.results[0].url;
      break;
    }
  }
  if (!novelUrl) {
    const url = (await rl.question('no results found — novel URL > ')).trim();
    if (url) novelUrl = url;
  }
  if (!novelUrl) {
    console.log('Sweep stopped: no novel URL available.');
    return;
  }

  console.log(`\nTesting novel: ${novelUrl}`);
  const novel = await stepNovel(provider, novelUrl);
  if (!novel) return;

  if (meta.hasChapterApi !== false) {
    // Mirrors novel_opener.dart: bookId = slug from the novel URL when the
    // provider does not return one in parseNovelInfo.
    const bookId =
      novel.bookId ??
      novel.novelId ??
      (novelUrl.split('/').filter(Boolean).pop() || '').split('.')[0];
    if (bookId) {
      const chapters = await stepChapters(provider, bookId);
      if (chapters && chapters.length > 0) {
        await stepContent(provider, chapters[0].url);
      }
    } else {
      console.log('No bookId in novel info — skipping chapters/content.');
    }
  } else if (Array.isArray(novel.chapters) && novel.chapters.length > 0) {
    await stepContent(provider, novel.chapters[0].url);
  } else {
    console.log('Chapters come from parseNovelInfo but the list is empty — skipping content.');
  }
}

// ═════════════════════════════════════════════════════════════
// CLI entry
// ═════════════════════════════════════════════════════════════

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--provider') args.provider = argv[++i];
    else if (a === '--query') args.query = argv[++i];
    else if (a === '--page') args.page = parseInt(argv[++i], 10) || 1;
    else if (a === '--novel-url') args.novelUrl = argv[++i];
    else if (a === '--chapter-url') args.chapterUrl = argv[++i];
    else if (a === '--book-id') args.bookId = argv[++i];
    else if (a.startsWith('--')) args[a.slice(2)] = true;
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.help) {
    const top = fs.readFileSync(__filename, 'utf8');
    console.log(top.slice(top.indexOf('//'), top.indexOf("'use strict'")));
    return;
  }

  if (args.list) {
    for (const p of listProviders()) {
      console.log(`${p.id.padEnd(14)} ${p.name.padEnd(20)} v${p.version}`);
    }
    return;
  }

  let provider;
  if (args.provider) {
    provider = loadProvider(args.provider);
  } else {
    const providers = listProviders();
    console.log('Providers:');
    providers.forEach((p, i) => console.log(`  [${i}] ${p.id} — ${p.name} (v${p.version})`));
    const pick = parseInt(await rl.question('> '), 10);
    if (isNaN(pick) || pick < 0 || pick >= providers.length) {
      console.log('Bad pick.');
      rl.close();
      return;
    }
    provider = loadProvider(providers[pick].id);
  }

  const registry = require('./lib/engine').loadRegistry();
  session = new Session(provider.id, provider.entry.name);
  session.setMeta({
    id: provider.id,
    name: provider.entry.name,
    version: provider.entry.version,
    baseUrl: provider.entry.baseUrl,
    registryUpdated: registry.updated,
    exportedFunctions: provider.exported,
    filters: call(provider, 'getFilters', []),
    metadata: call(provider, 'getProviderMetadata', []),
    helpersBytes: provider.helpersLength,
    sourceBytes: provider.sourceLength,
  });
  console.log(`\nSession: ${session.dir}`);

  if (args.novelUrl) args.novel = true;
  if (args.bookId || args.chapterUrl) args.content = true;

  const hasAction =
    args.sweep || args.browse || args.latest || args.search ||
    args.novel || args.chapters || args.content;

  if (!hasAction) {
    await interactive(provider);
    rl.close();
  } else {
    if (args.sweep) {
      await sweep(provider, args.query);
    } else {
      if (args.browse) await stepBrowse(provider, args.page || 1, {});
      if (args.latest) await stepLatest(provider, args.page || 1, {});
      if (args.search) await stepSearch(provider, args.query || 'martial god', args.page || 1);
      if (args.novel) await stepNovel(provider, args.novelUrl);
      if (args.chapters) await stepChapters(provider, args.bookId);
      if (args.content) await stepContent(provider, args.chapterUrl);
    }
    rl.close();
  }

  console.log(`\nSession saved: ${session.dir}`);
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});