const fs = require('fs');
const { Client } = require('./lib/client');
const c = new Client(require('path').join(__dirname, 'output', 'cookies.json'));
(async () => {
  for (const url of process.argv.slice(2)) {
    const t0 = Date.now();
    const r = await c.request({ url });
    console.log(`${url}\n   status=${r.status} bytes=${r.bytes} ms=${Date.now() - t0} err=${r.error || ''} note=${r.note || ''}`);
    if (process.env.SAVE) {
      const name = '/tmp/probe-' + url.replace(/[^a-z0-9]+/gi, '_').slice(0, 60) + '.html';
      fs.writeFileSync(name, r.html || '');
      console.log('   saved', name);
    }
  }
})();
