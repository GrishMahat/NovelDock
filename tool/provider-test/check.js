// Offline provider checker: load a provider JS + run provider functions on
// saved HTML/JSON, or emit request URLs. No network access.
//
//   node check.js <providerFile> '[{"call":"getSearchUrl","args":["q",1,{}]},
//                                 {"parseFile":"parseSearchResults","file":"/tmp/x.html"}]'
//
// Each step prints a one-line summary so a fix can be validated without
// re-running the whole live sweep.
'use strict';
const fs = require('fs');
const HELPERS = '/home/grish/dev/projects/fork/QuickNovel/NovelFlow/assets/providers/provider_helpers.js';

function loadProvider(file) {
  const src = fs.readFileSync(HELPERS, 'utf8') + '\n' + fs.readFileSync(file, 'utf8');
  const m = { exports: {} };
  new Function('module', src)(m);
  return m.exports;
}

function call(P, name, args) {
  const j = JSON.stringify(args || []);
  const w = new Function('module', 'return JSON.stringify(module.exports.' + name + '.apply(null, ' + j + '));');
  const s = w({ exports: P });
  return s === undefined ? null : JSON.parse(s);
}

function summarize(fn, v) {
  if (v === null || v === undefined) return `${fn} -> null`;
  if (typeof v !== 'object') return `${fn} -> ${JSON.stringify(v)}`;
  if (Array.isArray(v)) {
    return `${fn} -> array[${v.length}]` + (v.length ? ' first=' + JSON.stringify(v[0]) : '');
  }
  if (v.results) {
    return `${fn} -> results=${v.results.length} hasNext=${v.hasNextPage}` +
      (v.results.length ? ' first=' + JSON.stringify(v.results[0]) : '');
  }
  if (v.chapters) {
    return `${fn} -> title=${JSON.stringify(v.title)} author=${JSON.stringify(v.author)} ` +
      `status=${JSON.stringify(v.status)} genres=${v.genres.length} desc=${(v.description || '').length} ` +
      `chapters=${v.chapters.length}` + (v.chapters.length ? ' first=' + JSON.stringify(v.chapters[0]) : '');
  }
  if (v.html !== undefined) {
    return `${fn} -> htmlLen=${(v.html || '').length} images=${(v.images || []).length}`;
  }
  return `${fn} -> ${JSON.stringify(v).slice(0, 400)}`;
}

const file = process.argv[2];
const steps = JSON.parse(process.argv[3] || '[]');
const P = loadProvider(file);
console.log('exported:', Object.keys(P).filter((k) => typeof P[k] === 'function').join(','));
for (const s of steps) {
  const fn = s.call || s.parseFile || s.parse || s.parseJson;
  try {
    let v;
    if (s.call) {
      v = call(P, s.call, s.args);
    } else if (s.parseFile) {
      let text = fs.readFileSync(s.file, 'utf8');
      if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
      v = call(P, s.parseFile, [text]);
    } else if (s.parse) {
      v = call(P, s.parse, [s.value]);
    } else if (s.parseJson) {
      v = call(P, s.parseJson, [JSON.parse(fs.readFileSync(s.file, 'utf8'))]);
    }
    console.log(summarize(fn, v));
  } catch (e) {
    console.log(`${fn} -> ERROR ${e.message}`);
  }
}