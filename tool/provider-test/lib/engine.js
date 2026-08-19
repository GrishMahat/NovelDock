// Provider loader — mirrors lib/core/providers/engine.dart.
//
// The app evaluates providers inside flutter_js with this exact wrapper:
//
//   var module = { exports: {} };
//   <helpers source>
//   <provider source>
//   JSON.stringify(Object.keys(module.exports).filter(function(k) {
//     return typeof module.exports[k] === 'function';
//   }));
//
// Each provider gets its own runtime. `call()` mirrors engine's
// JSON.stringify(module.exports.name.apply(null, argsJson)) invocation so
// return values decode identically to the Dart side.

'use strict';

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '../../..');
const HELPERS_PATH = path.join(REPO_ROOT, 'assets/providers/provider_helpers.js');
const REGISTRY_PATH = path.join(
  REPO_ROOT,
  'noveldock-providers/registry.json',
);
const PROVIDERS_ROOT = path.join(REPO_ROOT, 'noveldock-providers');

function loadRegistry() {
  return JSON.parse(fs.readFileSync(REGISTRY_PATH, 'utf8'));
}

function listProviders() {
  return loadRegistry().providers;
}

function findProviderEntry(id) {
  const entry = loadRegistry()
    .providers.find((p) => p.id === id);
  if (!entry) throw new Error(`Unknown provider id: ${id}`);
  return entry;
}

// Load a provider exactly like engine.loadProvider() does: helpers are
// injected before the source, `module.exports` is built by register(),
// and the exported function names are extracted.
function loadProvider(id) {
  const entry = findProviderEntry(id);
  const helpers = fs.readFileSync(HELPERS_PATH, 'utf8');
  const source = fs.readFileSync(
    path.join(PROVIDERS_ROOT, entry.file),
    'utf8',
  );

  const module = { exports: {} };
  const factory = new Function('module', `${helpers}\n${source}`);
  factory(module);

  const exported = Object.keys(module.exports).filter(
    (k) => typeof module.exports[k] === 'function',
  );

  return {
    id,
    entry,
    module: module.exports,
    exported,
    helpersLength: helpers.length,
    sourceLength: source.length,
  };
}

// Mirror of ProviderInstance.call() (engine.dart).
function call(provider, name, args) {
  const fn = provider.module[name];
  if (typeof fn !== 'function') return null;
  const argsJson = JSON.stringify(args);
  const wrapper = new Function(
    'module',
    `return JSON.stringify(module.exports.${name}.apply(null, ${argsJson}));`,
  );
  let str;
  try {
    str = wrapper({ exports: provider.module });
  } catch (e) {
    throw new Error(`Provider function "${name}" error: ${e.message}`);
  }
  if (!str || str === 'undefined' || str === 'null') return null;
  try {
    return JSON.parse(str);
  } catch {
    return str;
  }
}

function hasFunction(provider, name) {
  return typeof provider.module[name] === 'function';
}

// Mirror of ProviderInstance.search() (engine.dart): calls the provider's
// direct search() if exported, else null.
function directSearch(provider, query, page) {
  if (!hasFunction(provider, 'search')) return null;
  const result = call(provider, 'search', [query, page]);
  if (result && typeof result === 'object') return result;
  return null;
}

module.exports = {
  REPO_ROOT,
  loadRegistry,
  listProviders,
  findProviderEntry,
  loadProvider,
  call,
  hasFunction,
  directSearch,
};