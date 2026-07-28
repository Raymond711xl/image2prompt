/**
 * 调参盘内核：在 StyleSpec 上做受控偏移。
 *
 * 为什么偏移必须做在 spec 上、而不是在编译好的提示词文字上改：
 * 垫图没有旋钮。你没法对一张垫图说「色相转 20 度、密度降一档、保持明度结构」。
 * 只有把风格解析成结构化字段，旋钮才存在——这是「理解后重述」和「抄」的分界线。
 *
 * 每次偏移都产出一份 diff，说清改了哪几个字段、从什么变成什么。
 * 偏移必须是可解释的，否则它和随机重跑没有区别。
 */

import type { StyleSpec } from '../types.js';
import {
  colorText, formText, join, lightingText, materialText, paletteText,
} from '../compile/shared.js';
import {
  ALIGNMENT_CN, DENSITY_CN, GEOMETRY_CAMP, MEDIUM_CN, STROKE_WEIGHT_CN, TYPEFACE_CN, WEIGHT_CONTRAST_CN,
} from '../compile/vocab.js';
import {
  BRIGHTNESS_AXIS, COLOR_STEP, DENSITY_AXIS, DENSITY_STEP, EDGE_FOR_GEOMETRY,
  FORM_AXIS, SATURATION_AXIS, TEMPERATURE_AXIS, moveOnAxis,
} from './axes.js';
import { COOL_POLE, WARM_POLE, rotateTowardPole, scaleSaturation, shiftLightness } from './color.js';

/**
 * 五个旋钮，取值 -1..+1（十字轴上拖动点的坐标），外加一个强度环。
 *
 * intensity=0 时任何拖动都不产生变化——中心点永远是原图的忠实值，
 * 「回到原点」永远可用。这是整个交互的锚。
 */
export interface DriftKnobs {
  /** 形态：-1 有机流动 → +1 几何硬朗 */
  form?: number;
  /** 密度：-1 疏 → +1 密 */
  density?: number;
  /** 色温：-1 冷 → +1 暖 */
  temperature?: number;
  /** 调性：-1 暗调 → +1 亮调 */
  brightness?: number;
  /** 饱和度：-1 降 → +1 升 */
  saturation?: number;
  /** 强度环。决定满拖一格实际走几档。 */
  intensity?: 0 | 1 | 2 | 3;
}

export interface FieldChange {
  field: string;
  from: string;
  to: string;
}

export interface PaletteChange {
  role: string;
  from: string;
  to: string;
}

export interface DriftDiff {
  /** 有没有实际发生变化。全零旋钮或强度为 0 时为 false。 */
  changed: boolean;
  changes: FieldChange[];
  palette: PaletteChange[];
  /**
   * 偏移算不了、但很可能已经被偏移带得不再成立的自由文本字段。
   *
   * 「流派命名」和「氛围」是视觉模型看着原图下的判断，不是可计算的原语——
   * 把形态从几何硬朗挪到有机流动之后，「像素／8-bit 图形」这个流派名和
   * 「复古电子游戏感」这个氛围就都不成立了，但正确的新值是什么，确定性代码算不出来。
   * 所以不猜、也不静默保留，而是标出来交给模型按 diff 重写一遍（纯文本调用，不用再看图）。
   */
  stale: string[];
  /** 撞到轴端点、色值被截断之类的情况。界面据此提示「这个方向到头了」。 */
  notes: string[];
}

export interface DriftResult {
  spec: StyleSpec;
  diff: DriftDiff;
}

/** 旋钮值 × 强度 = 实际步数。旋钮是方向，强度是幅度。 */
const steps = (knob: number | undefined, intensity: number): number => {
  if (!knob || !intensity) return 0;
  return Math.round(Math.max(-1, Math.min(1, knob)) * intensity);
};

const fmtPct = (n: number): string => `${Math.round(n * 100)}%`;

/**
 * 用偏移后的字段重新拼出 style_dna。
 *
 * 为什么不保留原来那段散文：原 style_dna 是视觉模型看着原图写的，形态词和色彩词都锚在
 * 原图上。偏移把 geometry 从 geometric_hard 挪到 organic_fluid 之后，那段散文还写着
 * 「锐利转角」——lint L2 会立刻报形态词冲突，而且 GPT Image 适配器会把这段英文 DNA
 * 原样塞进提示词，等于往模型嘴里塞一句和字段打架的话。
 *
 * 机器拼出来的 DNA 不如视觉模型的散文有文采，但它有两个保证：与字段永远一致，
 * 且只取风格层字段、绝不碰内容层（subject/scene/brand_marks/on_image_text/keywords），
 * 所以天然不会有内容泄漏。要文采可以事后让模型按 diff 重写一遍，那是纯文本调用，不用再看图。
 */
export function composeStyleDna(spec: StyleSpec): string {
  const family = spec.style_family.map((f) => f.name).filter(Boolean).join(' + ');
  const medium = MEDIUM_CN[spec.medium] || '';
  const typo = spec.typography.present
    ? join([
      spec.typography.typeface_class
        ? TYPEFACE_CN[spec.typography.typeface_class as keyof typeof TYPEFACE_CN] || null
        : null,
      spec.typography.alignment
        ? ALIGNMENT_CN[spec.typography.alignment as keyof typeof ALIGNMENT_CN] || null
        : null,
      spec.typography.weight_contrast
        ? WEIGHT_CONTRAST_CN[spec.typography.weight_contrast as keyof typeof WEIGHT_CONTRAST_CN] || null
        : null,
    ])
    : null;

  // formText 目前不输出 stroke_weight，在这里补上——线宽是形态语言里很重的一笔，丢了 DNA 就瘦一圈
  const stroke = spec.form_language.stroke_weight
    ? STROKE_WEIGHT_CN[spec.form_language.stroke_weight as keyof typeof STROKE_WEIGHT_CN] || null
    : null;

  return join([
    join([family, medium], '，'),
    join([formText(spec), stroke]),
    join([colorText(spec), paletteText(spec, false)]),
    lightingText(spec),
    materialText(spec),
    DENSITY_CN[spec.composition.density],
    typo,
    spec.mood.join('、'),
  ]);
}

/**
 * 受控偏移。
 *
 * 返回一份新的 spec（不改原对象）和一份 diff。spec 可以直接丢进 compile 出提示词，
 * 也可以再喂给 lint 复查——drift 的输出必须能过 lint，否则说明轴的联动规则写错了。
 */
export function drift(spec: StyleSpec, knobs: DriftKnobs): DriftResult {
  const intensity = knobs.intensity ?? 1;
  const next: StyleSpec = structuredClone(spec);
  const changes: FieldChange[] = [];
  const notes: string[] = [];
  const stale: string[] = [];
  const paletteChanges: PaletteChange[] = [];

  // ---- 形态轴 ----
  const formSteps = steps(knobs.form, intensity);
  if (formSteps !== 0) {
    if (spec.form_language.geometry === 'none') {
      notes.push('这张图没有明确的形态语言（geometry=none），形态轴不适用。');
    } else {
      const move = moveOnAxis(FORM_AXIS, spec.form_language.geometry, formSteps);
      if (move.moved !== 0) {
        next.form_language.geometry = move.value;
        changes.push({ field: 'form_language.geometry', from: spec.form_language.geometry, to: move.value });

        // edge 必须跟着走，否则会产出跨阵营的自相矛盾组合（lint L2 会抓）
        const edge = EDGE_FOR_GEOMETRY[move.value];
        if (edge !== spec.form_language.edge) {
          next.form_language.edge = edge;
          changes.push({ field: 'form_language.edge', from: spec.form_language.edge, to: edge });
        }

        // form_language 里的三个自由文本字段（圆角备注/重复规律/间隙规则）都是对着原形态写的。
        // 跨阵营移动后它们必然变成错话——「像素块阶梯式堆叠」配上有机流动形态是自相矛盾的，
        // 而且这些字段会被 formText 原样编进提示词，等于往模型嘴里塞一句和 geometry 打架的话。
        // 同阵营内移动（如硬朗→圆角）则保留：那种程度的变化不至于让描述失效。
        if (GEOMETRY_CAMP[spec.form_language.geometry] !== GEOMETRY_CAMP[move.value]) {
          const dropped: string[] = [];
          for (const k of ['corner_radius_note', 'repetition', 'gap_rule'] as const) {
            if (next.form_language[k]) {
              delete next.form_language[k];
              dropped.push(k);
            }
          }
          if (dropped.length) {
            notes.push(`形态跨阵营移动，已清除锚在原形态上的描述：${dropped.join('、')}。`);
          }
          // material.surfaces[].detail 同样锚在原形态上（「无反锯齿」是像素美学专属的说法），
          // 但它是结构化数组不是单个字段，删掉损失太大，标出来让模型判断。
          stale.push('style_family', 'mood', 'material.surfaces[].detail');
        }
      }
      if (move.moved !== move.requested) {
        notes.push(`形态轴已到${formSteps > 0 ? '几何' : '有机'}端点，请求 ${Math.abs(move.requested)} 档、实走 ${Math.abs(move.moved)} 档。`);
      }
    }
  }

  // ---- 密度轴 ----
  const densitySteps = steps(knobs.density, intensity);
  if (densitySteps !== 0) {
    const move = moveOnAxis(DENSITY_AXIS, spec.composition.density, densitySteps);
    if (move.moved !== 0) {
      next.composition.density = move.value;
      changes.push({ field: 'composition.density', from: spec.composition.density, to: move.value });

      // 密度不是一个孤立的形容词——密起来意味着主体占比升、负空间降
      const cov = clampRange(spec.composition.subject_coverage + move.moved * DENSITY_STEP.subjectCoverage, 0.02, 0.95);
      if (cov !== spec.composition.subject_coverage) {
        next.composition.subject_coverage = round2(cov);
        changes.push({
          field: 'composition.subject_coverage',
          from: fmtPct(spec.composition.subject_coverage),
          to: fmtPct(next.composition.subject_coverage),
        });
      }
      const neg = clampRange(spec.composition.negative_space.ratio - move.moved * DENSITY_STEP.negativeSpaceRatio, 0.02, 0.9);
      if (neg !== spec.composition.negative_space.ratio) {
        next.composition.negative_space.ratio = round2(neg);
        changes.push({
          field: 'composition.negative_space.ratio',
          from: fmtPct(spec.composition.negative_space.ratio),
          to: fmtPct(next.composition.negative_space.ratio),
        });
      }
    }
    if (move.moved !== move.requested) {
      notes.push(`密度轴已到${densitySteps > 0 ? '满版' : '极简'}端点，请求 ${Math.abs(move.requested)} 档、实走 ${Math.abs(move.moved)} 档。`);
    }
  }

  // ---- 色彩三轴：先动枚举，再动 palette ----
  const tempSteps = steps(knobs.temperature, intensity);
  if (tempSteps !== 0) {
    if (spec.color.temperature === 'mixed') {
      notes.push('color.temperature=mixed（冷暖对比）是一种关系而非位置，枚举不动，但色板仍按色温轴旋转。');
    } else {
      const move = moveOnAxis(TEMPERATURE_AXIS, spec.color.temperature, tempSteps);
      if (move.moved !== 0) {
        next.color.temperature = move.value;
        changes.push({ field: 'color.temperature', from: spec.color.temperature, to: move.value });
      }
    }
  }

  const brightSteps = steps(knobs.brightness, intensity);
  if (brightSteps !== 0 && spec.color.brightness_key) {
    const move = moveOnAxis(BRIGHTNESS_AXIS, spec.color.brightness_key, brightSteps);
    if (move.moved !== 0) {
      next.color.brightness_key = move.value;
      changes.push({ field: 'color.brightness_key', from: spec.color.brightness_key, to: move.value });
    }
  }

  const satSteps = steps(knobs.saturation, intensity);
  if (satSteps !== 0) {
    const move = moveOnAxis(SATURATION_AXIS, spec.color.saturation, satSteps);
    if (move.moved !== 0) {
      next.color.saturation = move.value;
      changes.push({ field: 'color.saturation', from: spec.color.saturation, to: move.value });
    }
    if (move.moved !== move.requested) {
      notes.push(`饱和度轴已到${satSteps > 0 ? '撞色' : '无彩'}端点，请求 ${Math.abs(move.requested)} 档、实走 ${Math.abs(move.moved)} 档。`);
    }
  }

  if (tempSteps !== 0 || brightSteps !== 0 || satSteps !== 0) {
    let anyClamped = false;
    next.palette = spec.palette.map((c, i) => {
      let hex = c.hex.toUpperCase();

      if (tempSteps !== 0) {
        const pole = tempSteps > 0 ? WARM_POLE : COOL_POLE;
        hex = rotateTowardPole(hex, pole, Math.abs(tempSteps) * COLOR_STEP.hueDegrees);
      }
      if (brightSteps !== 0) {
        const r = shiftLightness(hex, brightSteps * COLOR_STEP.lightness);
        hex = r.hex;
        anyClamped ||= r.clamped;
      }
      if (satSteps !== 0) {
        const factor = COLOR_STEP.saturationFactor ** satSteps;
        const r = scaleSaturation(hex, factor);
        hex = r.hex;
        anyClamped ||= r.clamped;
      }

      const out = { ...spec.palette[i], hex };
      if (hex !== c.hex.toUpperCase()) {
        paletteChanges.push({ role: c.role, from: c.hex.toUpperCase(), to: hex });
        // 中文色名锚在原色值上，颜色一变它就是错的标签。清掉让 paletteText 回落到 hex。
        delete (out as { name_cn?: string }).name_cn;
      }
      return out;
    });
    if (anyClamped) {
      notes.push('部分色值撞到明度/饱和度上下限被截断，这一档没有完整走完，色彩结构被压缩了。');
    }
  }

  // 色彩大幅偏移同样会让「氛围」失效：热烈直接的正红满版转成低饱和冷调之后，
  // 氛围一定变了，但变成什么得由模型重新判断。
  if (Math.max(Math.abs(tempSteps), Math.abs(brightSteps), Math.abs(satSteps)) >= 2) {
    stale.push('mood');
  }

  const changed = changes.length > 0 || paletteChanges.length > 0;
  const staleUnique = [...new Set(stale)];

  // style_dna 必须跟着字段重写，否则它会和字段打架（详见 composeStyleDna 的说明）
  if (changed) {
    next.style_dna = composeStyleDna(next);
    // 不凭空造英文散文。需要英文版就按 diff 让模型重写一遍，那是纯文本调用。
    next.style_dna_en = null;
    next.notes = join([spec.notes, `本 spec 由 drift 从原始分析结果偏移得到，style_dna 已按字段重新拼合。`], ' ');
  }

  return {
    spec: next,
    diff: { changed, changes, palette: paletteChanges, stale: changed ? staleUnique : [], notes },
  };
}

const clampRange = (n: number, lo: number, hi: number): number => Math.min(hi, Math.max(lo, n));
const round2 = (n: number): number => Math.round(n * 100) / 100;
