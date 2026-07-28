import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { drift, composeStyleDna } from '../src/drift/index.js';
import { FORM_AXIS, moveOnAxis } from '../src/drift/axes.js';
import { hexToHsl, hslToHex, rotateTowardPole, scaleSaturation, shiftLightness, WARM_POLE, COOL_POLE } from '../src/drift/color.js';
import { lintSpec, hasError } from '../src/lint/rules.js';
import { runTransferTest } from '../src/eval/transferTest.js';
import type { StyleSpec } from '../src/types.js';

const fixture = (name: string): StyleSpec =>
  JSON.parse(readFileSync(resolve(__dirname, `../evals/fixtures/${name}.stylespec.json`), 'utf8'));

const RED = fixture('red-pixel-newyear-poster');
const WHITE = fixture('white-highkey-scale-hero');
const ALL = [RED, WHITE];

describe('色彩运算', () => {
  it('hex ↔ HSL 往返不失真（容差 1/255）', () => {
    for (const hex of ['#FF2424', '#FED4AB', '#010101', '#FFFFFF', '#7F7F7F', '#0A4C8B']) {
      const back = hslToHex(hexToHsl(hex));
      for (let i = 1; i < 7; i += 2) {
        const a = parseInt(hex.slice(i, i + 2), 16);
        const b = parseInt(back.slice(i, i + 2), 16);
        expect(Math.abs(a - b)).toBeLessThanOrEqual(1);
      }
    }
  });

  it('无彩色不参与色相旋转——转灰色只会凭空造出颜色', () => {
    for (const gray of ['#010101', '#FFFFFF', '#808080']) {
      expect(rotateTowardPole(gray, WARM_POLE, 60)).toBe(gray.toUpperCase());
    }
  });

  it('朝极点旋转不会越过极点', () => {
    // 从冷极出发朝暖极转 500 度，应该停在暖极而不是绕圈
    const atCool = hslToHex({ h: COOL_POLE, s: 0.6, l: 0.5 });
    const rotated = hexToHsl(rotateTowardPole(atCool, WARM_POLE, 500));
    expect(Math.abs(rotated.h - WARM_POLE)).toBeLessThan(1);
  });

  it('色相的相对顺序在旋转后保持', () => {
    const before = ['#FF2424', '#FED4AB', '#24FF24'].map(hexToHsl).map((c) => c.h);
    const after = ['#FF2424', '#FED4AB', '#24FF24']
      .map((h) => rotateTowardPole(h, WARM_POLE, 12))
      .map(hexToHsl)
      .map((c) => c.h);
    // 三个色相两两之间的先后关系不变
    expect(Math.sign(after[1] - after[0])).toBe(Math.sign(before[1] - before[0]));
    expect(Math.sign(after[2] - after[1])).toBe(Math.sign(before[2] - before[1]));
  });

  it('撞到明度/饱和度上下限时报 clamped', () => {
    expect(shiftLightness('#FFFFFF', 0.2).clamped).toBe(true);
    expect(shiftLightness('#808080', 0.1).clamped).toBe(false);
    expect(scaleSaturation('#FF0000', 2).clamped).toBe(true);
  });

  it('明度平移保持相对结构：同样的位移量，差值不变', () => {
    const a = hexToHsl(shiftLightness('#404040', 0.1).hex).l;
    const b = hexToHsl(shiftLightness('#808080', 0.1).hex).l;
    const gap = hexToHsl('#808080').l - hexToHsl('#404040').l;
    expect(Math.abs((b - a) - gap)).toBeLessThan(0.01);
  });
});

describe('轴移动', () => {
  it('超出端点停在端点，并报实走步数', () => {
    const r = moveOnAxis(FORM_AXIS, 'geometric_hard', 5);
    expect(r.value).toBe('angular_sharp');
    expect(r.moved).toBe(1);
    expect(r.requested).toBe(5);
  });

  it('不在轴上的值原样返回', () => {
    const r = moveOnAxis(FORM_AXIS, 'none', 2);
    expect(r.value).toBe('none');
    expect(r.moved).toBe(0);
  });
});

describe('drift 的锚点性质', () => {
  it('强度环为 0 时任何拖动都不产生变化——中心点永远是原图的忠实值', () => {
    for (const spec of ALL) {
      const { spec: next, diff } = drift(spec, {
        form: 1, density: -1, temperature: 1, brightness: -1, saturation: 1, intensity: 0,
      });
      expect(diff.changed).toBe(false);
      expect(next).toEqual(spec);
    }
  });

  it('所有旋钮居中时不产生变化', () => {
    for (const spec of ALL) {
      const { diff } = drift(spec, { intensity: 3 });
      expect(diff.changed).toBe(false);
    }
  });

  it('不修改传入的 spec', () => {
    const before = JSON.stringify(RED);
    drift(RED, { form: 1, temperature: -1, intensity: 3 });
    expect(JSON.stringify(RED)).toBe(before);
  });

  it('枚举轴上一去一回回到原点', () => {
    const out = drift(RED, { density: 1, intensity: 1 });
    const back = drift(out.spec, { density: -1, intensity: 1 });
    expect(back.spec.composition.density).toBe(RED.composition.density);
  });
});

describe('drift 的输出必须自洽', () => {
  // 覆盖五个轴的正负满拖 × 三档强度
  const knobSets = (['form', 'density', 'temperature', 'brightness', 'saturation'] as const)
    .flatMap((axis) => [-1, 1].flatMap((v) => ([1, 2, 3] as const).map((i) => ({ [axis]: v, intensity: i }))));

  it('偏移后的 spec 仍能通过 lint（形态不跨阵营自相矛盾）', () => {
    for (const spec of ALL) {
      for (const knobs of knobSets) {
        const { spec: next } = drift(spec, knobs);
        const findings = lintSpec(next);
        expect(hasError(findings), `${JSON.stringify(knobs)} → ${findings.map((f) => f.message).join('; ')}`).toBe(false);
      }
    }
  });

  it('geometry 与 edge 永远同阵营', () => {
    const organic = ['organic_fluid', 'organic_irregular'];
    const organicEdge = ['wavy', 'irregular'];
    for (const spec of ALL) {
      for (const knobs of knobSets) {
        const { spec: next } = drift(spec, knobs);
        const g = next.form_language.geometry;
        const e = next.form_language.edge;
        if (organic.includes(g)) expect(organicEdge).toContain(e);
        if (g === 'geometric_hard' || g === 'angular_sharp') expect(e).toBe('straight');
      }
    }
  });

  it('构图数值始终在合法区间内', () => {
    for (const spec of ALL) {
      for (const knobs of knobSets) {
        const { spec: next } = drift(spec, knobs);
        expect(next.composition.subject_coverage).toBeGreaterThanOrEqual(0);
        expect(next.composition.subject_coverage).toBeLessThanOrEqual(1);
        expect(next.composition.negative_space.ratio).toBeGreaterThanOrEqual(0);
        expect(next.composition.negative_space.ratio).toBeLessThanOrEqual(1);
      }
    }
  });

  it('色板永远是合法 hex', () => {
    for (const spec of ALL) {
      for (const knobs of knobSets) {
        const { spec: next } = drift(spec, knobs);
        for (const c of next.palette) expect(c.hex).toMatch(/^#[0-9A-F]{6}$/);
      }
    }
  });
});

describe('重拼的 style_dna', () => {
  it('不含内容层任何词条——只取风格层字段，天然无泄漏', () => {
    for (const spec of ALL) {
      const { spec: next, diff } = drift(spec, { form: 1, temperature: 1, intensity: 2 });
      expect(diff.changed).toBe(true);
      const dna = next.style_dna;
      for (const kw of spec.content.keywords) {
        if (kw.length < 2) continue;
        expect(dna.includes(kw), `style_dna 泄漏了内容词「${kw}」`).toBe(false);
      }
      expect(dna).not.toContain(spec.content.subject);
    }
  });

  it('偏移后的 spec 仍能通过风格迁移测试', () => {
    for (const spec of ALL) {
      const { spec: next } = drift(spec, { form: -1, density: 1, saturation: -1, intensity: 2 });
      expect(runTransferTest(next).passed).toBe(true);
    }
  });

  it('不留下未翻译的原始枚举值', () => {
    for (const spec of ALL) {
      const dna = composeStyleDna(drift(spec, { form: 1, intensity: 1 }).spec);
      for (const raw of ['extreme', 'ultra_bold', 'grotesque_sans', 'justified', 'geometric_hard', 'low_key']) {
        expect(dna.includes(raw), `DNA 里漏出了原始枚举值「${raw}」`).toBe(false);
      }
    }
  });

  it('英文 DNA 被清空而不是留着和字段打架', () => {
    const { spec: next } = drift(RED, { form: -1, intensity: 3 });
    expect(next.style_dna_en).toBeNull();
  });
});

describe('diff 的可解释性', () => {
  it('形态跨阵营时清除锚在原形态上的描述，并标记待重写字段', () => {
    const { spec: next, diff } = drift(RED, { form: -1, intensity: 3 });
    expect(next.form_language.repetition).toBeUndefined();
    expect(next.form_language.gap_rule).toBeUndefined();
    expect(next.form_language.corner_radius_note).toBeUndefined();
    expect(diff.stale).toContain('style_family');
    expect(diff.stale).toContain('mood');
  });

  it('同阵营内移动保留形态描述——那种程度的变化不至于让描述失效', () => {
    const { spec: next, diff } = drift(RED, { form: -1, intensity: 1 });
    expect(next.form_language.geometry).toBe('geometric_rounded');
    expect(next.form_language.repetition).toBe(RED.form_language.repetition);
    expect(diff.stale).not.toContain('style_family');
  });

  it('撞到轴端点时给出说明', () => {
    const { diff } = drift(RED, { density: -1, intensity: 3 });
    expect(diff.notes.some((n) => n.includes('端点'))).toBe(true);
  });

  it('色值变化后清掉中文色名——色名锚在原色值上，颜色一变它就是错标签', () => {
    const { spec: next, diff } = drift(RED, { temperature: -1, intensity: 3 });
    const changedRoles = new Set(diff.palette.map((p) => p.role));
    for (const c of next.palette) {
      if (changedRoles.has(c.role)) expect(c.name_cn).toBeUndefined();
    }
  });

  it('每一处字段改动都能说清 from → to', () => {
    const { diff } = drift(RED, { form: 1, density: 1, saturation: 1, intensity: 2 });
    expect(diff.changes.length).toBeGreaterThan(0);
    for (const c of diff.changes) {
      expect(c.field).toBeTruthy();
      expect(c.from).not.toBe(c.to);
    }
  });
});
