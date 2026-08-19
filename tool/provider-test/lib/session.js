// Session recorder — writes every request/response/parse result to disk.
//
// Output layout (per run):
//
//   output/<timestamp>-<provider-id>/
//     session.json          summary of every step (updated per step)
//     <step>-<n>.json       full request + response + parsed result
//     <step>-<n>.html       raw response body
//     cookies.json          (parent dir) persisted cookie jar

'use strict';

const fs = require('fs');
const path = require('path');

const OUT_DIR = path.join(__dirname, '..', 'output');

function pad(n) {
  return String(n).padStart(2, '0');
}

function timestamp() {
  const d = new Date();
  return (
    `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-` +
    `${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`
  );
}

class Session {
  constructor(providerId, providerName) {
    this.providerId = providerId;
    this.providerName = providerName;
    this.dir = path.join(OUT_DIR, `${timestamp()}-${providerId}`);
    this.steps = [];
    fs.mkdirSync(this.dir, { recursive: true });
  }

  // Add a step and write its files. `parsed` is the provider's parse
  // result (JSON-safe object or null). `html` is the raw response body.
  addStep({ step, request, response, parsed, note }) {
    const index = this.steps.length;
    const base = `${step}-${index + 1}`;
    const htmlFile = `${base}.html`;

    const stepRecord = {
      step,
      index: index + 1,
      time: new Date().toISOString(),
      request: {
        method: request.method,
        url: request.url,
        headers: request.headers,
        body: request.body || undefined,
      },
      response: {
        status: response.status,
        url: response.url,
        durationMs: response.durationMs,
        bytes: response.bytes,
        headers: response.headers,
        error: response.error || undefined,
        note: note || response.note || undefined,
        htmlFile,
      },
      parsed,
    };

    // Raw body
    if (response.html) {
      fs.writeFileSync(path.join(this.dir, htmlFile), response.html);
    }

    // Per-step JSON (request + response + parsed)
    fs.writeFileSync(
      path.join(this.dir, `${base}.json`),
      JSON.stringify(stepRecord, null, 2),
    );

    this.steps.push(stepRecord);
    this._writeSession();
  }

  _writeSession() {
    const session = {
      appRequestConfig: {
        userAgent: require('./client').USER_AGENT,
        accept: require('./client').ACCEPT,
        acceptLanguage: require('./client').ACCEPT_LANGUAGE,
        referer: '(none, mirrors app)',
        httpProtocol: 'HTTP/1.1 (app uses HTTP/2 with fallback)',
        retries: 3,
      },
      provider: this.meta || null,
      steps: this.steps,
    };
    fs.writeFileSync(
      path.join(this.dir, 'session.json'),
      JSON.stringify(session, null, 2),
    );
  }

  setMeta(meta) {
    this.meta = meta;
    this._writeSession();
  }

  summary() {
    return this.steps.map((s) => ({
      step: s.step,
      status: s.response.status,
      url: s.request.url,
      bytes: s.response.bytes,
      note: s.response.note || null,
      parsedKeys: s.parsed ? Object.keys(s.parsed) : null,
    }));
  }
}

module.exports = { Session, OUT_DIR };