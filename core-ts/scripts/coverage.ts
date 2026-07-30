import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { imageCoords } from '../src/analyze/coords.js';
import {
  toPoint, kmeans, describe, histogram, FORM_ORDER, DENSITY_ORDER,
  BRIGHTNESS_ORDER, SATURATION_ORDER, TEMPERATURE_ORDER, type CoverageInput,
} from '../src/eval/coverage.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const PIC = resolve(HERE, '../../pictext');
const meta = JSON.parse(readFileSync(resolve(HERE, '../../evals/coverage/form-density.json'), 'utf8'));
const files = readdirSync(PIC).filter((f) => /\.jpe?g$/i.test(f));

const rows: CoverageInput[] = meta.images.map((m: any) => {
  const f = files.find((x) => x.startsWith(m.file));
  if (!f) throw new Error(`找不到图：${m.file}`);
  const c = imageCoords(join(PIC, f));
  return { short: m.short, geometry: m.geometry, density: m.density,
           brightness_key: c.brightness_key, saturation_level: c.saturation_level, temperature: c.temperature };
});

const bar = (n: number) => '█'.repeat(n) + '·'.repeat(Math.max(0, 6 - n));
const axis = (label: string, key: keyof CoverageInput, order: readonly string[]) => {
  console.log(`\n${label}`);
  for (const { value, count } of histogram(rows, key, order)) {
    const flag = count === 0 ? '   ← 空' : count === 1 ? '   ← 只有 1 张' : '';
    console.log(`  ${value.padEnd(18)} ${bar(count)} ${String(count).padStart(2)}${flag}`);
  }
};

console.log('═══ 五轴分布（共 ' + rows.length + ' 张）═══');
axis('形态轴  有机 → 几何', 'geometry', FORM_ORDER);
axis('密度轴  疏 → 密', 'density', DENSITY_ORDER);
axis('调性轴  暗 → 亮', 'brightness_key', BRIGHTNESS_ORDER);
axis('饱和轴  无彩 → 撞色', 'saturation_level', SATURATION_ORDER);
axis('色温轴  冷 → 暖', 'temperature', TEMPERATURE_ORDER);

console.log('\n═══ 形态 × 密度 平面 ═══');
console.log('            ' + DENSITY_ORDER.map((d) => d.slice(0, 6).padEnd(7)).join(''));
for (const g of [...FORM_ORDER, 'none']) {
  const cells = DENSITY_ORDER.map((d) => {
    const n = rows.filter((r) => r.geometry === g && r.density === d).length;
    return (n === 0 ? '·' : String(n)).padEnd(7);
  });
  console.log(g.padEnd(19) + cells.join(''));
}

console.log('\n═══ 自动聚类（供命名）═══');
const pts = rows.map(toPoint);
for (const [i, c] of kmeans(pts, 6).entries()) {
  console.log(`\n簇 ${i + 1}  ${describe(c.centroid)}`);
  console.log(`   ${c.members.join('、')}`);
}
