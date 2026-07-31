import type { Brief, StyleSpec } from '../types.js';
import {
  POSITIVE_REWRITE, POSITION_CN, SAFE_AREA_CN, FINISH_CN, TEXTURE_CN,
  SATURATION_CN, TEMPERATURE_CN, COLOR_CONTRAST_CN, BRIGHTNESS_CN,
  LIGHT_DIR_CN, LIGHT_QUALITY_CN, LIGHT_CONTRAST_CN, DENSITY_CN, GEOMETRY_CN, EDGE_CN,
  TYPEFACE_CN, ALIGNMENT_CN, NEGATIVE_REGION_CN, EDGE_IMPLIED_BY, FLAT_MEDIA,
} from './vocab.js';

/** 过滤空片段并用分隔符连接。适配器里到处是可选片段，统一在这里收口。 */
export const join = (parts: Array<string | null | undefined | false>, sep = '，'): string =>
  parts.filter((p): p is string => typeof p === 'string' && p.trim().length > 0)
    .map((p) => p.trim())
    .join(sep);

export const pct = (n: number): string => `${Math.round(n * 100)}%`;

/**
 * 色板描述。
 *
 * 主色/辅色按面积过滤（占比过小的色相写进提示词只会稀释权重），但 accent 一律保留：
 * 「低明度墨绿 + 高明度米白 + 一点铬黄」里的铬黄可能只占 0.4% 面积，却是这张图的签名色，
 * 按面积滤掉就把风格的关键一笔丢了。
 */
export function paletteText(spec: StyleSpec, withHex: boolean): string {
  const roleCn = { base: '主色', secondary: '辅色', accent: '点缀色' } as const;
  const items = spec.palette
    .filter((c) => c.role === 'accent' || c.ratio >= 0.05)
    .sort((a, b) => b.ratio - a.ratio)
    .map((c) => {
      const name = c.name_cn || c.hex;
      const hex = withHex && c.name_cn ? `（${c.hex}）` : '';
      const amount = c.ratio < 0.02 ? '小面积点缀' : `约占 ${pct(c.ratio)}`;
      return `${roleCn[c.role]}${name}${hex}${amount}`;
    });
  return items.join('、');
}

export function colorText(spec: StyleSpec): string {
  return join([
    SATURATION_CN[spec.color.saturation],
    TEMPERATURE_CN[spec.color.temperature],
    COLOR_CONTRAST_CN[spec.color.contrast],
    spec.color.brightness_key ? BRIGHTNESS_CN[spec.color.brightness_key] : null,
  ]);
}

/**
 * 光线描述。
 * 纯平面媒介（平面设计/排版海报/矢量插画/拼贴）且判为无光比时，不编出「柔和环境漫射光」
 * 这类描述——它会把生图模型往三维渲染感上推，正好毁掉平面感。
 */
export function lightingText(spec: StyleSpec): string {
  const isFlatArtwork = FLAT_MEDIA.includes(spec.medium)
    && spec.lighting.contrast === 'flat'
    && !spec.lighting.sources?.length;
  if (isFlatArtwork) return '纯平面无光影模拟，无投影无高光';

  const sources = spec.lighting.sources?.length ? spec.lighting.sources.join('、') : null;
  return join([
    sources,
    `${LIGHT_QUALITY_CN[spec.lighting.quality]}${LIGHT_DIR_CN[spec.lighting.direction]}`,
    LIGHT_CONTRAST_CN[spec.lighting.contrast],
    spec.lighting.time_of_day || null,
  ]);
}

export function materialText(spec: StyleSpec): string {
  const surfaces = spec.material.surfaces
    .map((s) => `${s.where}呈${FINISH_CN[s.finish as keyof typeof FINISH_CN] ?? s.finish}质感${s.detail ? `（${s.detail}）` : ''}`)
    .join('、');
  const overlay = (spec.material.texture_overlay ?? [])
    .filter((t) => t !== 'none')
    .map((t) => TEXTURE_CN[t as keyof typeof TEXTURE_CN] ?? t)
    .join('、');
  return join([surfaces, overlay]);
}

/** 形态描述。几何类形态会自带排除句，见 vocab.GEOMETRY_CN 的说明。 */
export function formText(spec: StyleSpec): string {
  const f = spec.form_language;
  const edgeImplied = (EDGE_IMPLIED_BY[f.geometry] ?? []).includes(f.edge);
  return join([
    GEOMETRY_CN[f.geometry],
    edgeImplied ? null : EDGE_CN[f.edge],
    f.corner_radius_note,
    f.gap_rule,
    f.repetition,
  ]);
}

export function compositionText(spec: StyleSpec, brief: Brief): string {
  const c = spec.composition;
  const pos = POSITION_CN[c.subject_position] ?? c.subject_position;
  const subjectPart = c.subject_position === 'none'
    ? null
    : `主体位于${pos}、占画面约 ${pct(c.subject_coverage)}`;
  const region = NEGATIVE_REGION_CN[c.negative_space.region] ?? '';
  const negative = region ? `${region}保留约 ${pct(c.negative_space.ratio)} 负空间` : null;
  const safeArea = resolveSafeArea(spec, brief);
  // visual_flow 刻意不编译：动线描述必然依附原图的具体元素，换主体后不成立
  return join([
    subjectPart,
    negative,
    safeArea ? `${safeArea}保持干净可排版` : null,
    c.grid,
    DENSITY_CN[c.density],
    c.bleed ? '图形四边出血裁切' : null,
  ]);
}

/**
 * 面板结构。panel_count > 1 时明确告诉生成模型这是多面板拼合画面，不要拍扁成一张连续场景——
 * v0.1 时代最容易犯的错就是这个（作品页截图里的上下两张图被合并成一张）。
 */
export function panelText(spec: StyleSpec): string | null {
  const c = spec.composition;
  if (!c.panel_count || c.panel_count <= 1) return null;
  const base = `画面由 ${c.panel_count} 个独立版块拼合而成，各版块保持独立边界，不要合并成一个连续场景`;
  if (!c.panels?.length) return base;
  const detail = c.panels.map((p, i) => `第${i + 1}块（${p.region}）：${p.role}`).join('；');
  return `${base}——${detail}`;
}

/** 元素前后顺序（基础版，只给相对顺序，不给坐标）。 */
export function stackingText(spec: StyleSpec): string | null {
  const order = spec.composition.element_stacking;
  if (!order?.length) return null;
  return `画面元素前后顺序（从前到后）：${order.join(' → ')}`;
}

/** 文案安全区：Brief 显式指定优先，否则继承 StyleSpec 的 typography.safe_area。 */
export function resolveSafeArea(spec: StyleSpec, brief: Brief): string | null {
  if (brief.copy_safe_area && brief.copy_safe_area !== 'none') {
    return SAFE_AREA_CN[brief.copy_safe_area] ?? brief.copy_safe_area;
  }
  return spec.typography.safe_area || null;
}

export function styleFamilyText(spec: StyleSpec, lang: 'cn' | 'en'): string {
  return spec.style_family
    .map((f) => (lang === 'cn' ? f.name : f.name_en))
    .filter(Boolean)
    .join(lang === 'cn' ? ' + ' : ' + ');
}

export interface AvoidResult {
  /** 可转成正向表述的，直接进提示词 */
  positives: string[];
  /** 转不了的，落到 notes 建议用平台负向词框 */
  unconvertible: string[];
}

/**
 * 禁止项处理。模型对否定词不敏感——「没有杂物」不如「纯色极简背景」。
 * 查不到映射时不硬造否定句，交还给用户在平台负向词框填写。
 */
export function rewriteAvoid(mustAvoid: string[] | undefined): AvoidResult {
  const positives: string[] = [];
  const unconvertible: string[] = [];
  for (const term of mustAvoid ?? []) {
    const hit = POSITIVE_REWRITE.find((r) => r.match.test(term));
    if (hit) {
      if (!positives.includes(hit.positive)) positives.push(hit.positive);
    } else {
      unconvertible.push(term);
    }
  }
  return { positives, unconvertible };
}

/** 画质词点到为止：最多 2 个，多余的丢弃并在 notes 里说明。 */
export function qualityWords(brief: Brief): { words: string[]; dropped: string[] } {
  const all = brief.quality_words ?? [];
  return { words: all.slice(0, 2), dropped: all.slice(2) };
}

/**
 * 三个参考槽的分工协议。
 * 必须明确告诉模型「从哪张图参考什么」，否则多张参考图会互相污染。
 */
export function refProtocol(brief: Brief): string | null {
  const refs = brief.refs;
  if (!refs) return null;
  const lines: string[] = [];
  if (refs.style) lines.push(`图 A（${refs.style}）：只参考视觉风格——色彩、材质、光线、质感。忽略其画面内容与构图。`);
  if (refs.composition) lines.push(`图 B（${refs.composition}）：只参考构图——主体位置、留白分布、画幅比例。忽略其风格与主体外观。`);
  if (refs.subject) lines.push(`图 C（${refs.subject}）：只参考主体外观——形状、比例、材质细节。忽略其背景、光线与色调。`);
  return lines.length ? lines.join('\n') : null;
}

/** 画面文字片段。render_text_in_image 为 false 时不写进提示词，改由后期图层叠加。 */
export function copyText(brief: Brief, spec: StyleSpec): string | null {
  if (!brief.render_text_in_image) return null;
  const copy = brief.copy;
  if (!copy) return null;
  const safeArea = resolveSafeArea(spec, brief);
  const face = spec.typography.typeface_class
    ? TYPEFACE_CN[spec.typography.typeface_class as keyof typeof TYPEFACE_CN] || null
    : null;
  const align = spec.typography.alignment
    ? ALIGNMENT_CN[spec.typography.alignment as keyof typeof ALIGNMENT_CN] || null
    : null;
  const bits: string[] = [];
  if (copy.title) bits.push(`${safeArea ?? '画面上方'}排版标题文字"${copy.title}"`);
  if (copy.subtitle) bits.push(`副标题"${copy.subtitle}"`);
  if (copy.body) bits.push(`正文小字"${copy.body}"`);
  if (!bits.length) return null;
  return join([...bits, face, align]);
}
