// Usage: node capture.mjs <outDir> stills t1,t2,...   |   node capture.mjs <outDir> all <fps> <seconds>
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const [outDir, mode, a, b] = process.argv.slice(2);
mkdirSync(outDir, { recursive: true });
const here = dirname(fileURLToPath(import.meta.url));
const page = pathToFileURL(join(here, 'video.html')).href;
const port = 9333;
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [
  '--headless=new', `--remote-debugging-port=${port}`, '--hide-scrollbars', '--mute-audio',
  '--force-device-scale-factor=1', '--window-size=1920,1080', '--allow-file-access-from-files',
  `--user-data-dir=${mkdtempSync(join(tmpdir(), 'bragchrome-'))}`, 'about:blank'], { stdio: 'ignore' });

const sleep = ms => new Promise(r => setTimeout(r, ms));
let targets;
for (let i = 0; i < 50; i++) {
  try { targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); if (targets.length) break; } catch {}
  await sleep(200);
}
const ws = new WebSocket(targets.find(t => t.type === 'page').webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener('open', r, { once: true }));
let id = 0; const pending = new Map();
ws.addEventListener('message', e => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } });
const send = (method, params = {}) => new Promise(r => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const evalJS = async expr => { const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true }); if (r.result?.exceptionDetails) throw new Error(JSON.stringify(r.result.exceptionDetails)); return r.result?.result?.value; };

await send('Page.enable'); await send('Runtime.enable');
ws.addEventListener('message', e => { const m = JSON.parse(e.data); if (m.method === 'Runtime.exceptionThrown') console.log('PAGE ERROR', m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text); });
await send('Emulation.setDeviceMetricsOverride', { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false });
await send('Page.navigate', { url: page });
for (let i = 0; i < 100; i++) { if ((await evalJS('typeof renderAt')) === 'function') break; await sleep(100); }
await evalJS('document.fonts.ready.then(()=>Promise.all([...document.fonts].filter(f=>f.status!=="loaded").map(f=>f.load().catch(()=>0))))');
console.log('fonts:', await evalJS('[...document.fonts].filter(f=>f.status==="loaded").map(f=>f.family+" "+f.weight).join(", ")'));

async function shot(t, file) {
  await evalJS(`renderAt(${t}); new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)))`);
  const r = await send('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width: 1920, height: 1080, scale: 1 } });
  writeFileSync(file, Buffer.from(r.result.data, 'base64'));
}
if (mode === 'stills') {
  for (const t of a.split(',')) await shot(parseFloat(t), join(outDir, `still-${t}.png`));
} else {
  const fps = parseInt(a), n = Math.round(parseFloat(b) * fps);
  for (let f = 0; f < n; f++) {
    await shot(f / fps, join(outDir, `f${String(f).padStart(4, '0')}.png`));
    if (f % 60 === 0) console.log(`frame ${f}/${n}`);
  }
}
ws.close(); chrome.kill();
process.exit(0);
