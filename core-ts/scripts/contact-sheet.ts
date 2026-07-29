import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { imageCoords } from '../src/analyze/coords.js';
import { toPoint, kmeans, type CoverageInput } from '../src/eval/coverage.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const PIC = '/Users/raymond7/Documents/再生图工具/pictext';
const OUT = process.argv[2];
const meta = JSON.parse(readFileSync(resolve(HERE, '../../evals/coverage/form-density.json'), 'utf8'));
const files = readdirSync(PIC).filter((f) => /\.jpe?g$/i.test(f));
const tmp = mkdtempSync(join(tmpdir(), 'sheet-'));

const rows: Array<CoverageInput & { path: string; desc: string }> = meta.images.map((m: any) => {
  const f = files.find((x) => x.startsWith(m.file));
  if (!f) throw new Error(`找不到：${m.file}`);
  const p = join(PIC, f);
  const c = imageCoords(p);
  return { short: m.short, desc: m.desc, path: p, geometry: m.geometry, density: m.density,
           brightness_key: c.brightness_key, saturation_level: c.saturation_level, temperature: c.temperature };
});

const thumb = (p: string, i: number): string => {
  const out = join(tmp, `${i}.jpg`);
  execFileSync('sips', ['-Z', '300', '-s', 'format', 'jpeg', '-s', 'formatOptions', '62', p, '--out', out], { stdio: 'ignore' });
  return `data:image/jpeg;base64,${readFileSync(out).toString('base64')}`;
};

const clusters = kmeans(rows.map(toPoint), 6);
const byShort = new Map(rows.map((r, i) => [r.short, { ...r, i }]));

const groups = clusters
  .map((c) => c.members.map((m) => byShort.get(m)!).filter(Boolean))
  .filter((g) => g.length > 0)
  .sort((a, b) => b.length - a.length);

const cards = (g: typeof rows extends Array<infer T> ? any[] : never) =>
  g.map((r: any) => `<figure><img src="${thumb(r.path, r.i)}" alt=""><figcaption>${r.short}</figcaption></figure>`).join('');

const html = `<title>28 张参考图：机器分的组</title>
<style>
:root{--bg:#fff;--fg:#111;--mut:#666;--line:#e3e3e3;--card:#fafafa}
@media(prefers-color-scheme:dark){:root{--bg:#111;--fg:#eee;--mut:#999;--line:#2c2c2c;--card:#1a1a1a}}
:root[data-theme=dark]{--bg:#111;--fg:#eee;--mut:#999;--line:#2c2c2c;--card:#1a1a1a}
:root[data-theme=light]{--bg:#fff;--fg:#111;--mut:#666;--line:#e3e3e3;--card:#fafafa}
body{background:var(--bg);color:var(--fg);font:15px/1.6 -apple-system,"PingFang SC",sans-serif;margin:0;padding:28px 20px 60px}
.wrap{max-width:1100px;margin:0 auto}
h1{font-size:21px;margin:0 0 6px}
.lede{color:var(--mut);margin:0 0 32px;max-width:60ch}
section{margin:0 0 40px;padding:20px;background:var(--card);border:1px solid var(--line);border-radius:12px}
h2{font-size:16px;margin:0 0 4px;display:flex;align-items:baseline;gap:10px}
h2 span{font-weight:400;color:var(--mut);font-size:13px}
.ask{color:var(--mut);font-size:13px;margin:0 0 16px;border-left:2px solid var(--line);padding-left:10px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:14px}
figure{margin:0}
img{width:100%;height:190px;object-fit:cover;border-radius:6px;display:block;background:var(--line)}
figcaption{font-size:12px;color:var(--mut);margin-top:6px;line-height:1.35}
</style>
<div class="wrap">
<h1>28 张参考图，机器分成了这几组</h1>
<p class="lede">不用管机器是按什么分的。只看图：每组给你什么感觉？你会怎么叫它？如果哪张明显不属于它所在的组，或者你觉得两组其实是一组，直接说。</p>
${groups.map((g, i) => `<section>
<h2>第 ${i + 1} 组 <span>${g.length} 张</span></h2>
<p class="ask">这组你会叫它什么？</p>
<div class="grid">${cards(g)}</div>
</section>`).join('\n')}
</div>`;

writeFileSync(OUT, html);
rmSync(tmp, { recursive: true, force: true });
console.log(`已生成 ${OUT}  ${(html.length / 1024 / 1024).toFixed(1)} MB`);
