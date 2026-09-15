'use strict';
// Full-registry live sweep: browse/latest/search/filtered/novel/chapters/
// content for every provider in registry.json. Mirrors the app's request
// flow (same client as provider_test). Non-interactive.
//
//   node sweep.js [--only id1,id2] [--query "martial god"] [--out /tmp/x.json]
const fs = require('fs');
const path = require('path');
const { listProviders, loadProvider, call, hasFunction } = require('./lib/engine');
const { Client } = require('./lib/client');

const argv = process.argv.slice(2);
let ONLY = null, QUERY = 'martial god', OUT = null;
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--only' && argv[i + 1]) ONLY = argv[++i].split(',');
  else if (argv[i] === '--query' && argv[i + 1]) QUERY = argv[++i];
  else if (argv[i] === '--out' && argv[i + 1]) OUT = argv[++i];
}
const client = new Client(path.join(__dirname, 'output', 'cookies.json'));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
if (!OUT) {
  const d = new Date(), p = (n) => String(n).padStart(2, '0');
  OUT = `/tmp/sweep-${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}.json`;
}
function jcall(provider, name, args) {
  try { return { ok: true, value: call(provider, name, args || []) }; }
  catch (e) { return { ok: false, error: String((e && e.message) || e) }; }
}
async function postConfig(config, query) {
  const headers = Object.fromEntries(
    Object.entries(config.headers || {}).map(([k, v]) => [k.toLowerCase(), String(v)])
  );
  const isBinary = Array.isArray(config.body);
  let body;
  if (isBinary) {
    body = Buffer.from(config.body);
  } else {
    const fields = { ...(config.fields || {}) };
    if (query !== undefined && query !== null) fields.keyboard = query;
    body = Object.entries(fields)
      .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`)
      .join('&');
    headers['content-type'] = 'application/x-www-form-urlencoded';
  }
  let res = await client.request({ url: config.url, method: 'POST', body, extraHeaders: headers, followRedirects: false });
  if ([301, 302, 303, 307, 308].includes(res.status) && res.headers.location) {
    const url2 = new URL(res.headers.location, config.url).toString();
    res = await client.request({ url: url2 });
  }
  const data = isBinary ? Array.from(res.body) : res.html;
  return { res, data };
}
async function getList(provider, url, label) {
  if (!url) return { label, error: 'url null' };
  const res = await client.request({ url: String(url) });
  if (res.status !== 200) return { label, url: String(url), status: res.status, bytes: res.bytes, error: res.error || res.note || ('http ' + res.status) };
  let parsed;
  try { parsed = call(provider, 'parseSearchResults', [res.html]); }
  catch (e) { return { label, url: String(url), status: res.status, bytes: res.bytes, error: 'parse: ' + String((e && e.message) || e) }; }
  const results = (parsed && parsed.results) || [];
  return { label, url: String(url), status: res.status, bytes: res.bytes, count: results.length, hasNext: !!(parsed && parsed.hasNextPage), sample: results.slice(0, 2).map((r) => ({ title: r.title, url: r.url })) };
}
function nonDefaultFilters(filters) {
  const fv = {};
  for (const f of filters) {
    if (f.type === 'select' && f.options && f.options.length > 1) fv[f.id] = (f.defaultIndex || 0) === 1 ? 0 : 1;
    else if (f.type === 'multiselect' && f.options && f.options.length) fv[f.id] = [0];
    else if (f.type === 'sort' && f.options && f.options.length) fv[f.id] = [1, !(f.defaultAscending !== false)];
    else if (f.type === 'text') fv[f.id] = 'martial';
  }
  return fv;
}
async function auditOne(id) {
  const rec = { id, steps: {} };
  let provider;
  try {
    provider = loadProvider(id);
    rec.meta = call(provider, 'getProviderMetadata', []);
    rec.filters = call(provider, 'getFilters', []);
  } catch (e) { rec.loadError = String((e && e.message) || e); return rec; }
  const meta = rec.meta || {};
  const filters = Array.isArray(rec.filters) ? rec.filters : [];

  // Browse
  if (meta.hasMainPage !== false) {
    if (hasFunction(provider, 'getBrowseConfig')) {
      const c = jcall(provider, 'getBrowseConfig', ['main', {}]);
      if (c.ok && c.value && c.value.url) {
        try { const r = await postConfig(c.value); const p = r.data == null ? null : call(provider, 'parseSearchResults', [r.data]); rec.steps.browse = { label: 'browse-post', url: c.value.url, status: r.res.status, count: ((p && p.results) || []).length }; }
        catch (e) { rec.steps.browse = { label: 'browse-post', error: String((e && e.message) || e) }; }
      } else rec.steps.browse = { label: 'browse-post', error: 'config: ' + (c.ok ? JSON.stringify(c.value) : c.error) };
    } else rec.steps.browse = await getList(provider, jcall(provider, 'getMainPageUrl', [1, {}]).value, 'browse');
  }
  // Latest
  if (meta.hasLatest !== false) {
    if (hasFunction(provider, 'getBrowseConfig')) {
      const c = jcall(provider, 'getBrowseConfig', ['latest', {}]);
      if (c.ok && c.value && c.value.url) {
        try { const r = await postConfig(c.value); const p = r.data == null ? null : call(provider, 'parseSearchResults', [r.data]); rec.steps.latest = { label: 'latest-post', url: c.value.url, status: r.res.status, count: ((p && p.results) || []).length }; }
        catch (e) { rec.steps.latest = { label: 'latest-post', error: String((e && e.message) || e) }; }
      } else rec.steps.latest = { label: 'latest-post', error: 'config: ' + (c.ok ? JSON.stringify(c.value) : c.error) };
    } else if (hasFunction(provider, 'getLatestUrl')) rec.steps.latest = await getList(provider, jcall(provider, 'getLatestUrl', [1]).value, 'latest');
    else rec.steps.latest = { label: 'latest', error: 'no getLatestUrl/getBrowseConfig' };
  }
  // Search
  if (meta.hasSearch !== false) {
    if (hasFunction(provider, 'getSearchConfig')) {
      const c = jcall(provider, 'getSearchConfig', [QUERY, 1]);
      if (c.ok && c.value && c.value.url) {
        try { const r = await postConfig(c.value, QUERY); const p = r.data == null ? null : call(provider, 'parseSearchResults', [r.data]); rec.steps.search = { label: 'search-post', url: c.value.url, status: r.res.status, count: ((p && p.results) || []).length, hasNext: !!(p && p.hasNextPage), sample: ((p && p.results) || []).slice(0, 2).map((x) => ({ title: x.title, url: x.url })) }; }
        catch (e) { rec.steps.search = { label: 'search-post', error: String((e && e.message) || e) }; }
      } else rec.steps.search = { label: 'search-post', error: 'config: ' + (c.ok ? JSON.stringify(c.value) : c.error) };
    } else rec.steps.search = await getList(provider, jcall(provider, 'getSearchUrl', [QUERY, 1, {}]).value, 'search');
  }
  // Filters (search-attached when the provider declares searchFilters)
  if (filters.length) {
    const fv = nonDefaultFilters(filters);
    if (Object.keys(fv).length) {
      if (meta.searchFilters && hasFunction(provider, 'getSearchUrl') && !hasFunction(provider, 'getSearchConfig')) {
        const r = await getList(provider, jcall(provider, 'getSearchUrl', [QUERY, 1, fv]).value, 'search-filtered');
        r.filterValues = fv;
        if (rec.steps.search && rec.steps.search.url && r.url) r.sameUrlAsUnfiltered = r.url === rec.steps.search.url;
        rec.steps.filtered = r;
      } else if (hasFunction(provider, 'getMainPageUrl')) {
        const r = await getList(provider, jcall(provider, 'getMainPageUrl', [1, fv]).value, 'browse-filtered');
        r.filterValues = fv;
        if (rec.steps.browse && rec.steps.browse.url && r.url) r.sameUrlAsUnfiltered = r.url === rec.steps.browse.url;
        rec.steps.filtered = r;
      } else rec.steps.filtered = { note: 'no filterable entry point' };
    } else rec.steps.filtered = { note: 'no non-default values derivable' };
  } else rec.steps.filtered = { note: meta.hasFilters ? 'hasFilters=true but getFilters() empty' : 'no filters declared' };

  // Novel info
  let novelUrl = null;
  for (const k of ['search', 'browse', 'latest']) {
    const s = rec.steps[k];
    if (s && s.sample && s.sample.length && s.sample[0].url) { novelUrl = s.sample[0].url; break; }
  }
  if (!novelUrl) { rec.steps.novel = { error: 'no novel URL from earlier steps' }; return rec; }
  try {
    let infoUrl = novelUrl;
    if (hasFunction(provider, 'getNovelInfoUrl')) { const u = call(provider, 'getNovelInfoUrl', [novelUrl]); if (u) infoUrl = String(u); }
    const res = await client.request({ url: infoUrl });
    if (res.status !== 200) { rec.steps.novel = { novelUrl, infoUrl, status: res.status, error: res.error || res.note || ('http ' + res.status) }; return rec; }
    let novel;
    try { novel = call(provider, 'parseNovelInfo', [res.html]); }
    catch (e) { rec.steps.novel = { novelUrl, infoUrl, status: res.status, bytes: res.bytes, error: 'parse: ' + String((e && e.message) || e) }; return rec; }
    if (!novel) { rec.steps.novel = { novelUrl, infoUrl, status: res.status, bytes: res.bytes, error: 'parse returned null' }; return rec; }
    const chapters0 = Array.isArray(novel.chapters) ? novel.chapters : [];
    rec.steps.novel = { novelUrl, infoUrl, status: res.status, bytes: res.bytes, title: novel.title || null, author: novel.author || null, bookId: novel.bookId || novel.novelId || null, infoChapters: chapters0.length, hasDesc: !!((novel.description || '').length) };
    // Chapters
    let chList = chapters0;
    if (meta.hasChapterApi !== false && (hasFunction(provider, 'getChaptersApiUrl') || hasFunction(provider, 'getChaptersApiConfig'))) {
      const bookId = novel.bookId || novel.novelId || (novelUrl.split('/').filter(Boolean).pop() || '').split('.')[0];
      try {
        if (hasFunction(provider, 'getChaptersApiConfig')) {
          const cfg = call(provider, 'getChaptersApiConfig', [bookId, 0]);
          if (cfg && cfg.url) { const r = await postConfig(cfg); const list = r.data == null ? [] : (call(provider, 'parseChapterList', [r.data]) || []); rec.steps.chapters = { via: 'api-config', bookId, status: r.res.status, count: list.length }; chList = list; }
          else rec.steps.chapters = { via: 'api-config', bookId, error: 'config null' };
        } else {
          const curl = call(provider, 'getChaptersApiUrl', [bookId, 0]);
          const cres = await client.request({ url: String(curl) });
          if (cres.status !== 200) rec.steps.chapters = { via: 'api-url', bookId, url: String(curl), status: cres.status, error: cres.error || ('http ' + cres.status) };
          else { const list = call(provider, 'parseChapterList', [cres.html]) || []; rec.steps.chapters = { via: 'api-url', bookId, url: String(curl), status: cres.status, count: list.length }; chList = list; }
        }
      } catch (e) { rec.steps.chapters = { bookId, error: String((e && e.message) || e) }; }
    } else rec.steps.chapters = { via: 'info', count: chList.length };
    // Content
    if (chList.length) {
      const chUrl = chList[0].url;
      try {
        let cUrl = chUrl;
        if (hasFunction(provider, 'getChapterContentUrl')) { const u = call(provider, 'getChapterContentUrl', [chUrl]); if (u) cUrl = String(u); }
        const cres = await client.request({ url: cUrl });
        if (cres.status !== 200) rec.steps.content = { chUrl, contentUrl: cUrl, status: cres.status, error: cres.error || ('http ' + cres.status) };
        else {
          let c;
          try { c = call(provider, 'parseChapterContent', [cres.html]); }
          catch (e) { rec.steps.content = { chUrl, contentUrl: cUrl, status: cres.status, error: 'parse: ' + String((e && e.message) || e) }; return rec; }
          if (!c) rec.steps.content = { chUrl, contentUrl: cUrl, status: cres.status, error: 'parse returned null' };
          else rec.steps.content = { chUrl, contentUrl: cUrl, status: cres.status, htmlLen: (c.html || '').length, images: (c.images || []).length };
        }
      } catch (e) { rec.steps.content = { chUrl, error: String((e && e.message) || e) }; }
    } else rec.steps.content = { error: 'no chapters to test' };
  } catch (e) { rec.steps.novel = { novelUrl, error: String((e && e.message) || e) }; }
  return rec;
}
async function main() {
  const all = listProviders().map((p) => p.id);
  const ids = ONLY || all;
  console.log(`Sweeping ${ids.length} providers, query=${JSON.stringify(QUERY)} -> ${OUT}`);
  const out = { started: new Date().toISOString(), query: QUERY, providers: [] };
  for (const id of ids) {
    process.stdout.write(`... ${id} `);
    const t0 = Date.now();
    try {
      const rec = await auditOne(id);
      rec.ms = Date.now() - t0;
      out.providers.push(rec);
      const s = rec.steps || {};
      const f = (k) => {
        const v = s[k];
        if (!v) return `${k}:-`;
        if (v.error) return `${k}:ERR`;
        if (v.note) return `${k}:note`;
        if (v.count !== undefined) return `${k}:${v.count}${v.sameUrlAsUnfiltered ? '(sameUrl)' : ''}`;
        if (v.htmlLen !== undefined) return `${k}:${v.htmlLen}ch`;
        if (v.title) return `${k}:ok`;
        return `${k}:?`;
      };
      console.log(`[${rec.ms}ms] ${['browse', 'latest', 'search', 'filtered', 'novel', 'chapters', 'content'].map(f).join(' ')}${rec.loadError ? ' LOAD-FAIL' : ''}`);
    } catch (e) { console.log(`FATAL ${String((e && e.message) || e)}`); out.providers.push({ id, fatal: String((e && e.message) || e) }); }
    fs.writeFileSync(OUT, JSON.stringify(out, null, 2));
    await sleep(1000);
  }
  out.finished = new Date().toISOString();
  fs.writeFileSync(OUT, JSON.stringify(out, null, 2));
  console.log(`Done -> ${OUT}`);
}
main().catch((e) => { console.error(e); process.exit(1); });
