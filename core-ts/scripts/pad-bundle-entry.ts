/**
 * 调色盘原型的浏览器入口。
 *
 * 把真实的 drift + compile 打包进网页，拖旋钮时跑的是和 CLI 完全同一套代码——
 * 原型如果用假数据，验证的就只是界面好不好看，验证不了「这个轴拨出来对不对」，
 * 而后者才是这一版要回答的问题。
 */

import { drift, type DriftKnobs } from '../src/drift/index.js';
import { compile } from '../src/compile/index.js';
import { lintSpec, lintPrompt } from '../src/lint/rules.js';
import type { Brief, ModelId, StyleSpec } from '../src/types.js';

export interface PadResult {
  changes: Array<{ field: string; from: string; to: string }>;
  palette: Array<{ role: string; from: string; to: string }>;
  stale: string[];
  notes: string[];
  styleDna: string;
  /** 偏移后的完整色板，供界面刷色块 */
  swatches: Array<{ hex: string; ratio: number; role: string }>;
  prompts: Array<{ model: ModelId; label: string; text2img: string | null; note: string[] }>;
  findings: Array<{ rule: string; level: string; message: string }>;
}

const LABEL: Record<ModelId, string> = {
  jimeng: '即梦 / 豆包 / 可灵',
  'gpt-image': 'GPT Image 2',
};

export function run(spec: StyleSpec, brief: Brief, knobs: DriftKnobs): PadResult {
  const { spec: next, diff } = drift(spec, knobs);

  const prompts: PadResult['prompts'] = [];
  const findings: PadResult['findings'] = lintSpec(next).map((f) => ({
    rule: f.rule, level: f.level, message: f.message,
  }));

  for (const model of ['jimeng', 'gpt-image'] as ModelId[]) {
    try {
      const p = compile(next, brief, model);
      prompts.push({ model, label: LABEL[model], text2img: p.text2img, note: p.notes });
      for (const f of lintPrompt(next, brief, p)) {
        findings.push({ rule: f.rule, level: f.level, message: f.message });
      }
    } catch (e) {
      prompts.push({
        model, label: LABEL[model], text2img: null,
        note: [`编译失败：${e instanceof Error ? e.message : String(e)}`],
      });
    }
  }

  return {
    changes: diff.changes,
    palette: diff.palette,
    stale: diff.stale,
    notes: diff.notes,
    styleDna: next.style_dna,
    swatches: next.palette.map((c) => ({ hex: c.hex, ratio: c.ratio, role: c.role })),
    prompts,
    findings,
  };
}

declare global {
  interface Window { PAD: { run: typeof run } }
}
if (typeof window !== 'undefined') window.PAD = { run };
