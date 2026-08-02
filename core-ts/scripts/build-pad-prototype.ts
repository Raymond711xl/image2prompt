/**
 * 生成调色盘第三栏的可交互原型。
 *
 * 把真引擎（drift + compile + lint）连同一份真 StyleSpec 内联进单个 HTML，
 * 拖旋钮跑的是和 CLI 同一套代码。原型用假数据只能验证界面好不好看，
 * 验证不了「这个轴拨出来对不对」——后者才是这一版要回答的问题。
 */

import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = process.argv[2];
const FIX = resolve(HERE, '../evals/fixtures');

const tmp = mkdtempSync(join(tmpdir(), 'pad-'));
execFileSync('npx', [
  'esbuild', resolve(HERE, 'pad-bundle-entry.ts'),
  '--bundle', '--format=iife', '--target=es2020', '--minify',
  `--outfile=${join(tmp, 'engine.js')}`,
], { cwd: resolve(HERE, '..'), stdio: 'ignore' });
const engine = readFileSync(join(tmp, 'engine.js'), 'utf8');
rmSync(tmp, { recursive: true, force: true });

const spec = JSON.parse(readFileSync(join(FIX, 'red-pixel-newyear-poster.stylespec.json'), 'utf8'));
const brief = JSON.parse(readFileSync(join(FIX, 'glucose-meter-wechat-cover.brief.json'), 'utf8'));

const html = String.raw`<title>调色盘 · 第三栏原型</title>
<style>
:root{
  --bg:#f6f6f7;--panel:#fff;--fg:#16181d;--mut:#6b7280;--dim:#9aa1ac;
  --line:#e2e4e8;--accent:#2f6df6;--warn:#c2410c;--ok:#15803d;--field:#f2f3f5;
}
@media(prefers-color-scheme:dark){:root{
  --bg:#0e1013;--panel:#171a1f;--fg:#e8eaed;--mut:#9aa1ac;--dim:#6b7280;
  --line:#282c33;--accent:#6a9bff;--warn:#fb923c;--ok:#4ade80;--field:#1f2329;}}
:root[data-theme=dark]{--bg:#0e1013;--panel:#171a1f;--fg:#e8eaed;--mut:#9aa1ac;--dim:#6b7280;--line:#282c33;--accent:#6a9bff;--warn:#fb923c;--ok:#4ade80;--field:#1f2329;}
:root[data-theme=light]{--bg:#f6f6f7;--panel:#fff;--fg:#16181d;--mut:#6b7280;--dim:#9aa1ac;--line:#e2e4e8;--accent:#2f6df6;--warn:#c2410c;--ok:#15803d;--field:#f2f3f5;}

*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
  font:13px/1.55 -apple-system,BlinkMacSystemFont,"PingFang SC","Helvetica Neue",sans-serif;}
.page{max-width:520px;margin:0 auto;padding:20px 16px 60px}
.hint{color:var(--mut);font-size:12px;margin:0 0 14px;padding:9px 12px;
  background:var(--panel);border:1px solid var(--line);border-radius:8px}
.hint b{color:var(--fg);font-weight:600}

.col{background:var(--panel);border:1px solid var(--line);border-radius:12px;overflow:hidden}
.colhead{padding:10px 14px;border-bottom:1px solid var(--line);
  font-size:11px;color:var(--mut);letter-spacing:.04em;text-transform:uppercase}
section{padding:14px;border-bottom:1px solid var(--line)}
section:last-child{border-bottom:0}
h3{margin:0 0 3px;font-size:12.5px;font-weight:600;display:flex;align-items:center;gap:7px}
h3 .n{width:17px;height:17px;border-radius:5px;background:var(--accent);color:#fff;
  font-size:10px;display:grid;place-items:center;flex:none;font-weight:700}
.sub{color:var(--mut);font-size:11px;margin:0 0 11px}

label.f{display:block;margin-bottom:9px}
label.f>span{display:block;font-size:10.5px;color:var(--mut);margin-bottom:3px}
input[type=text],textarea{width:100%;background:var(--field);color:var(--fg);
  border:1px solid var(--line);border-radius:7px;padding:7px 9px;font:inherit;font-size:12px;resize:vertical}
input:focus,textarea:focus{outline:none;border-color:var(--accent)}
.row2{display:grid;grid-template-columns:1fr 1fr;gap:9px}

.pads{display:grid;grid-template-columns:1fr 1fr;gap:14px}
.pad{max-width:190px}
.pad{-webkit-user-select:none;user-select:none}
.padlabel{font-size:10.5px;color:var(--mut);margin-bottom:5px;display:flex;justify-content:space-between}
.surface{position:relative;aspect-ratio:1;max-width:190px;background:var(--field);
  border:1px solid var(--line);border-radius:9px;cursor:crosshair;touch-action:none;overflow:hidden}
.surface .ax{position:absolute;background:var(--line)}
.surface .ax.h{left:0;right:0;top:50%;height:1px}
.surface .ax.v{top:0;bottom:0;left:50%;width:1px}
.dot{position:absolute;width:15px;height:15px;border-radius:50%;background:var(--accent);
  border:2.5px solid var(--panel);box-shadow:0 1px 5px rgba(0,0,0,.35);
  transform:translate(-50%,-50%);pointer-events:none;transition:background .12s}
.dot.zero{background:var(--dim)}
.ends{display:flex;justify-content:space-between;font-size:9.5px;color:var(--dim);margin-top:3px}
.vend{position:absolute;left:50%;transform:translateX(-50%);font-size:9.5px;color:var(--dim);pointer-events:none}
.vend.t{top:3px}.vend.b{bottom:3px}

.ring{display:flex;gap:6px;align-items:center;margin-top:13px}
.ring b{font-size:10.5px;color:var(--mut);font-weight:400;margin-right:2px}
.seg{flex:1;display:flex;background:var(--field);border:1px solid var(--line);border-radius:7px;padding:2px}
.seg button{flex:1;border:0;background:none;color:var(--mut);font:inherit;font-size:11px;
  padding:4px 0;border-radius:5px;cursor:pointer}
.seg button.on{background:var(--accent);color:#fff;font-weight:600}

.slider{margin-top:12px}
.slider input{width:100%;accent-color:var(--accent)}

.sw{display:flex;gap:5px;margin-top:11px;height:34px}
.sw div{border-radius:6px;border:1px solid var(--line);position:relative;
  transition:background .12s;display:grid;place-items:end center;padding-bottom:2px}
.sw span{font-size:8.5px;color:#fff;mix-blend-mode:difference;font-variant-numeric:tabular-nums}

.diff{margin-top:11px;font-size:11px}
.diff .empty{color:var(--dim)}
.diff .r{display:flex;gap:6px;padding:2.5px 0;align-items:baseline}
.diff code{font-size:10px;color:var(--mut);flex:none;font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
.diff .to{color:var(--fg);font-weight:600}
.diff .from{color:var(--dim);text-decoration:line-through}
.flag{margin-top:9px;padding:7px 9px;border-radius:7px;font-size:10.5px;line-height:1.5}
.flag.stale{background:color-mix(in srgb,var(--warn) 12%,transparent);color:var(--warn)}
.flag.note{background:var(--field);color:var(--mut)}
.flag.cant{background:var(--field);color:var(--mut);margin-top:11px}

.pblock{margin-bottom:11px}
.pbar{display:flex;justify-content:space-between;align-items:center;margin-bottom:5px}
.pbar strong{font-size:11px;font-weight:600}
.pbar button{border:1px solid var(--line);background:var(--field);color:var(--mut);
  font:inherit;font-size:10.5px;padding:2.5px 9px;border-radius:6px;cursor:pointer}
.pbar button:hover{color:var(--fg);border-color:var(--accent)}
.pbar button.done{color:var(--ok);border-color:var(--ok)}
pre{margin:0;background:var(--field);border:1px solid var(--line);border-radius:7px;
  padding:9px;font:11px/1.65 ui-monospace,SFMono-Regular,Menlo,monospace;
  white-space:pre-wrap;word-break:break-word;color:var(--fg);max-height:190px;overflow:auto}
.dna{font-size:11px;color:var(--mut);line-height:1.65;margin-top:4px}
.lint{margin-top:9px;font-size:10.5px;color:var(--warn)}
.lint .ok{color:var(--ok)}
@media(max-width:640px){.pads{grid-template-columns:1fr}.row2{grid-template-columns:1fr}}
</style>

<div class="page">
<p class="hint">这是<b>真引擎</b>跑的原型，不是静态图：拖动圆点会真的调用 <code>drift()</code> 和 <code>compile()</code>，下面的提示词是当场编译出来的。参考图是「像素风新年海报」，要生成的是「白色血糖仪 · 微信头图」——<b>换主体验证风格能不能迁移</b>。</p>

<div class="col">
<div class="colhead">第三栏</div>

<section>
  <h3><span class="n">1</span>想生成什么</h3>
  <p class="sub">这里填这次要画的东西。风格来自左边选中的参考图，内容由你定。</p>
  <label class="f"><span>主体</span><input type="text" id="subject"></label>
  <label class="f"><span>主体细节</span><textarea id="detail" rows="2"></textarea></label>
  <div class="row2">
    <label class="f"><span>标题文案</span><input type="text" id="title"></label>
    <label class="f"><span>画幅</span><input type="text" id="ratio"></label>
  </div>
  <label class="f" style="margin-bottom:0"><span>口述调整（说人话，不用管下面的旋钮）</span>
    <textarea id="say" rows="2" placeholder="例：更安静一点，但那个红色要留着"></textarea></label>
  <div class="flag note" style="margin-top:9px">口述这一栏在 App 里会先过一次模型，把话拆成<b>拨旋钮</b>、<b>锁字段</b>、<b>转 Brief</b>、<b>没接住</b>四份，全部可见可撤。本原型只展示位置，解析尚未接。</div>
</section>

<section>
  <h3><span class="n">2</span>调色盘</h3>
  <p class="sub">中心点＝原图的忠实值。强度环为 0 时怎么拖都不动，「回到原点」永远可用。</p>

  <div class="pads">
    <div class="pad" data-pad="style">
      <div class="padlabel"><span>风格盘</span><span id="lab-style">中心</span></div>
      <div class="surface" data-x="form" data-y="density">
        <div class="ax h"></div><div class="ax v"></div>
        <div class="vend t">密</div><div class="vend b">疏</div>
        <div class="dot zero" style="left:50%;top:50%"></div>
      </div>
      <div class="ends"><span>有机流动</span><span>几何硬朗</span></div>
    </div>

    <div class="pad" data-pad="color">
      <div class="padlabel"><span>色彩盘</span><span id="lab-color">中心</span></div>
      <div class="surface" data-x="temperature" data-y="brightness">
        <div class="ax h"></div><div class="ax v"></div>
        <div class="vend t">亮调</div><div class="vend b">暗调</div>
        <div class="dot zero" style="left:50%;top:50%"></div>
      </div>
      <div class="ends"><span>冷</span><span>暖</span></div>
    </div>
  </div>

  <div class="slider">
    <div class="padlabel"><span>饱和度</span><span id="lab-sat">中心</span></div>
    <input type="range" id="sat" min="-1" max="1" step="0.25" value="0">
  </div>

  <div class="ring">
    <b>强度</b>
    <div class="seg" id="ring">
      <button data-i="0">0 忠实</button><button data-i="1" class="on">1 小</button>
      <button data-i="2">2 中</button><button data-i="3">3 大</button>
    </div>
  </div>

  <div class="sw" id="sw"></div>
  <div class="flag cant">色板是实时算的，所见即所得。<b>形态和密度没法预览</b>——那两个轴的效果必须真出图才看得见，界面上只能给字段清单，不假装能预览。</div>

  <div class="diff" id="diff"></div>
  <div id="flags"></div>
</section>

<section>
  <h3><span class="n">3</span>提示词</h3>
  <p class="sub">想复刻就直接复制。没有生图 API 也是完整可用的——这是主路径，不是降级。</p>
  <div id="prompts"></div>
  <div class="pbar" style="margin-top:13px"><strong>风格 DNA</strong>
    <button data-copy="dna">复制</button></div>
  <div class="dna" id="dna"></div>
  <div class="lint" id="lint"></div>
</section>
</div>
</div>

<script>__ENGINE__</script>
<script>
const SPEC = __SPEC__, BRIEF = __BRIEF__;
const knobs = { form:0, density:0, temperature:0, brightness:0, saturation:0, intensity:1 };
const $ = (s)=>document.querySelector(s);

$('#subject').value = BRIEF.subject;
$('#detail').value  = BRIEF.subject_detail || '';
$('#title').value   = (BRIEF.copy && BRIEF.copy.title) || '';
$('#ratio').value   = BRIEF.aspect_ratio;

function brief(){
  return { ...BRIEF, subject:$('#subject').value, subject_detail:$('#detail').value,
           aspect_ratio:$('#ratio').value,
           copy:{ ...(BRIEF.copy||{}), title:$('#title').value || null } };
}
const fmt = (v)=> v===0 ? '中心' : (v>0?'+':'') + v.toFixed(2).replace(/0+$/,'').replace(/\.$/,'');

function render(){
  const r = PAD.run(SPEC, brief(), knobs);

  $('#sw').innerHTML = r.swatches.map(s=>
    '<div style="flex:'+Math.max(s.ratio,0.06)+';background:'+s.hex+'"><span>'+s.hex+'</span></div>').join('');

  $('#diff').innerHTML = r.changes.length || r.palette.length
    ? [...r.changes.map(c=>'<div class="r"><code>'+c.field+'</code><span class="from">'+c.from+'</span><span class="to">'+c.to+'</span></div>'),
       ...r.palette.map(p=>'<div class="r"><code>palette.'+p.role+'</code><span class="from">'+p.from+'</span><span class="to">'+p.to+'</span></div>')].join('')
    : '<div class="empty">没有任何字段变化。</div>';

  let f = '';
  if (r.stale.length) f += '<div class="flag stale">这几项偏移算不出来，已标为待重写：<b>'+r.stale.join('、')+'</b>。交给模型按上面的改动重写一遍（纯文本调用，不用再看图）。</div>';
  for (const n of r.notes) f += '<div class="flag note">'+n+'</div>';
  $('#flags').innerHTML = f;

  $('#prompts').innerHTML = r.prompts.map((p,i)=>
    '<div class="pblock"><div class="pbar"><strong>'+p.label+'</strong>'+
    (p.text2img?'<button data-copy="p'+i+'">复制</button>':'')+'</div>'+
    '<pre id="p'+i+'">'+(p.text2img||'（本模型此次无文生图产出）')+'</pre></div>').join('');

  $('#dna').textContent = r.styleDna;
  $('#lint').innerHTML = r.findings.length
    ? r.findings.map(x=>'· ['+x.rule+'] '+x.message).join('<br>')
    : '<span class="ok">✓ 偏移后的 spec 仍然自洽，无 lint 问题</span>';

  $('#lab-style').textContent = knobs.form||knobs.density ? '形态 '+fmt(knobs.form)+' · 密度 '+fmt(knobs.density) : '中心';
  $('#lab-color').textContent = knobs.temperature||knobs.brightness ? '色温 '+fmt(knobs.temperature)+' · 调性 '+fmt(knobs.brightness) : '中心';
  $('#lab-sat').textContent = fmt(knobs.saturation);
  document.querySelectorAll('.dot').forEach(d=>d.classList.toggle('zero', knobs.intensity===0));
}

document.querySelectorAll('.surface').forEach(surf=>{
  const kx = surf.dataset.x, ky = surf.dataset.y, dot = surf.querySelector('.dot');
  const set = (e)=>{
    const b = surf.getBoundingClientRect();
    const x = Math.min(1, Math.max(0, (e.clientX-b.left)/b.width));
    const y = Math.min(1, Math.max(0, (e.clientY-b.top)/b.height));
    knobs[kx] = Math.round((x*2-1)*4)/4;
    knobs[ky] = Math.round(((1-y)*2-1)*4)/4;
    dot.style.left = ((knobs[kx]+1)/2*100)+'%';
    dot.style.top  = ((1-(knobs[ky]+1)/2)*100)+'%';
    render();
  };
  surf.addEventListener('pointerdown', e=>{ surf.setPointerCapture(e.pointerId); set(e); });
  surf.addEventListener('pointermove', e=>{ if(e.buttons) set(e); });
  surf.addEventListener('dblclick', ()=>{ knobs[kx]=0; knobs[ky]=0;
    dot.style.left='50%'; dot.style.top='50%'; render(); });
});

$('#sat').addEventListener('input', e=>{ knobs.saturation=+e.target.value; render(); });
$('#ring').addEventListener('click', e=>{
  const b = e.target.closest('button'); if(!b) return;
  knobs.intensity = +b.dataset.i;
  document.querySelectorAll('#ring button').forEach(x=>x.classList.toggle('on', x===b));
  render();
});
['subject','detail','title','ratio'].forEach(id=>$('#'+id).addEventListener('input', render));

document.addEventListener('click', async e=>{
  const b = e.target.closest('[data-copy]'); if(!b) return;
  const src = b.dataset.copy==='dna' ? $('#dna') : document.getElementById(b.dataset.copy);
  try{ await navigator.clipboard.writeText(src.textContent); }catch{}
  const t = b.textContent; b.textContent='已复制'; b.classList.add('done');
  setTimeout(()=>{ b.textContent=t; b.classList.remove('done'); }, 1200);
});

render();
</script>`;

// 替换必须用函数形式：压缩后的 JS 里满是 `$&` `$'` 这类序列，
// 用字符串形式的 replace 会把它们当成特殊替换模式，把匹配到的占位符原样塞回去。
writeFileSync(
  OUT,
  html.replace('__ENGINE__', () => engine)
    .replace('__SPEC__', () => JSON.stringify(spec))
    .replace('__BRIEF__', () => JSON.stringify(brief)),
);
console.log(`已生成 ${OUT}`);
