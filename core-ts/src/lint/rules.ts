import type { Brief, CompiledPrompt, StyleSpec } from '../types.js';
import { GEOMETRY_CAMP, EDGE_CAMP } from '../compile/vocab.js';

export type Level = 'error' | 'warn';

export interface Finding {
  rule: 'L1' | 'L2' | 'L3' | 'L4' | 'L5' | 'L6';
  level: Level;
  where: string;
  message: string;
}

export const hasError = (findings: Finding[]): boolean => findings.some((f) => f.level === 'error');

const CJK = /[一-鿿]/;

/** 中文按子串匹配，拉丁按词边界匹配，避免 "art" 命中 "smart"。 */
function contains(haystack: string, needle: string): boolean {
  const t = needle.trim();
  if (!t) return false;
  if (CJK.test(t)) {
    // 单字中文词太容易误报（"光""金"），交由 analyze 阶段保证 keywords 写具体名词
    if (t.length < 2) return false;
    return haystack.includes(t);
  }
  const escaped = t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`\\b${escaped}\\b`, 'i').test(haystack);
}

/** 内容层的全部词条：keywords + 品牌名 + 画面文字。 */
export function contentTerms(spec: StyleSpec): string[] {
  return [
    ...spec.content.keywords,
    ...spec.content.brand_marks,
    ...spec.content.on_image_text.map((t) => t.text),
  ].filter((t) => t && t.trim().length > 0);
}

/**
 * 会被编译进提示词的自由文本字段。
 *
 * 判定标准只有一条：编译器真的读了它。改这张表前先去 compile/ 里确认——
 * `visual_flow`、`negative_space.note`、`typography.note`、`notes` 是给人看的分析记录，
 * 刻意不编译，所以不受 L1 约束，可以放心点名原图元素。
 */
function compiledFreeText(spec: StyleSpec): Array<[string, string | null | undefined]> {
  const out: Array<[string, string | null | undefined]> = [
    ['style_dna', spec.style_dna],
    ['style_dna_en', spec.style_dna_en],
    ['composition.grid', spec.composition.grid],
    ['typography.safe_area', spec.typography.safe_area],
    ['form_language.gap_rule', spec.form_language.gap_rule],
    ['form_language.repetition', spec.form_language.repetition],
  ];
  spec.mood.forEach((m, i) => out.push([`mood[${i}]`, m]));
  (spec.lighting.sources ?? []).forEach((s, i) => out.push([`lighting.sources[${i}]`, s]));
  spec.material.surfaces.forEach((s, i) => {
    out.push([`material.surfaces[${i}].where`, s.where]);
    out.push([`material.surfaces[${i}].detail`, s.detail]);
  });
  return out;
}

/**
 * L1 内容泄漏：任何会进提示词的自由文本字段都不得包含内容层词条。
 *
 * 这是模式 A 的核心价值。检验标准是「把任何新主体塞进去都成立」——
 * 一旦风格描述里留着原图的具体物件，换主体复用就会把原图内容一起带出来。
 *
 * 早期只查 `style_dna`，实测教训是漏得最狠的不是它：`style_dna` 压根不进 text2img
 * （只有 `style_dna_en` 出现在垫图风格参考句里），而 `mood` 和 `composition.grid`
 * 是被逐字编进正向提示词的。一张动态摄影海报把「文人书卷气」写进 mood，
 * 生成结果满屏是书——真凶是 mood，查 style_dna 查不出来。
 */
export function lintContentLeakage(spec: StyleSpec): Finding[] {
  const findings: Finding[] = [];
  const terms = contentTerms(spec);

  for (const [field, text] of compiledFreeText(spec)) {
    if (!text) continue;
    for (const term of terms) {
      if (contains(text, term)) {
        findings.push({
          rule: 'L1',
          level: 'error',
          where: field,
          message: `内容泄漏：${field} 中出现了内容层词条「${term}」。这个字段会被编进提示词，必须写成换任何主体都成立的抽象描述。`,
        });
      }
    }
  }
  return findings;
}

const ORGANIC_WORDS = ['液态', '流动', '膨胀', '波浪', '有机曲线', '泡泡', '融化', '起伏', 'fluid', 'liquid', 'organic', 'blob', 'wavy', 'melting'];
const GEOMETRIC_WORDS = ['几何', '平直', '硬朗', '直边', '方正', '锐利', 'geometric', 'angular', 'straight', 'hard-edged', 'rectilinear'];

/**
 * L2 形态词冲突。
 *
 * 实测教训：「液态膨胀」单独使用会把生图模型推向有机泡泡字。几何圆角和有机曲线
 * 是两种气质，写错一个词生成方向就全偏。这里检查 form_language 的枚举判断
 * 与 style_dna 的自由文本描述是否互相打架。
 */
export function lintFormConflict(spec: StyleSpec): Finding[] {
  const findings: Finding[] = [];
  const camp = GEOMETRY_CAMP[spec.form_language.geometry] ?? 'neutral';
  const edgeCamp = EDGE_CAMP[spec.form_language.edge] ?? 'neutral';
  const dna = `${spec.style_dna} ${spec.style_dna_en ?? ''}`;

  if (camp !== 'neutral' && edgeCamp !== 'neutral' && camp !== edgeCamp) {
    findings.push({
      rule: 'L2',
      level: 'warn',
      where: 'form_language',
      message: `形态自相矛盾：geometry=${spec.form_language.geometry}（${camp}）与 edge=${spec.form_language.edge}（${edgeCamp}）不同阵营。确认这张图到底是几何圆角还是有机曲线。`,
    });
  }

  const strays = camp === 'geometric'
    ? ORGANIC_WORDS.filter((w) => contains(dna, w))
    : camp === 'organic'
      ? GEOMETRIC_WORDS.filter((w) => contains(dna, w))
      : [];

  if (strays.length) {
    const want = camp === 'geometric' ? '几何' : '有机';
    findings.push({
      rule: 'L2',
      level: 'warn',
      where: 'style_dna',
      message: `形态词冲突：form_language 判为${want}形态，但 style_dna 出现了对立阵营的词「${strays.join('、')}」。生图模型会被这些词带偏——几何形态需显式排除有机曲线。`,
    });
  }
  return findings;
}

/**
 * L3 边界控制四纪律。
 *
 * 检查的是结构化部件槽位而非字符串关键词——部件缺失应该在编译期就失败
 * （见 gptImage.buildEditParts），这里是编译产物的最后一道复核。
 */
export function lintEditBoundary(prompt: CompiledPrompt): Finding[] {
  const findings: Finding[] = [];
  if (!prompt.img2img_edit) return findings;

  const parts = prompt.parts.edit;
  if (!parts) {
    findings.push({
      rule: 'L3',
      level: 'error',
      where: `${prompt.model}.img2img_edit`,
      message: '产出了垫图编辑指令但没有结构化部件。编辑指令必须由四纪律槽位组装，不能自由拼接。',
    });
    return findings;
  }

  const required: Array<[keyof typeof parts, string]> = [
    ['scope', '纪律一 范围锚点'],
    ['protect', '纪律二 保护清单'],
    ['replace', '纪律三 枚举替换目标'],
    ['noAddNoRemove', '纪律四 禁增禁删条款'],
  ];
  for (const [key, label] of required) {
    if (!parts[key] || !parts[key].trim()) {
      findings.push({
        rule: 'L3',
        level: 'error',
        where: `${prompt.model}.parts.edit.${key}`,
        message: `${label}缺失。编辑模型有「主题一致化」倾向，四个部件缺一就会溢出到无关元素。`,
      });
    }
  }
  return findings;
}

/**
 * 已验证有效的排除句白名单。
 *
 * jimeng.md 要求用正向表述规避负向内容，但 design-styles.md 的形态词避坑
 * 明确要求几何形态必须写出「不要波浪形有机曲线」——这是三轮实测得出的必要例外，
 * 因为不排除的话模型默认会往有机形态跑。两条规则在此处真实冲突，取实测优先。
 */
const ALLOWED_NEGATIONS = ['不要波浪形有机曲线'];

const NEGATION_PATTERNS = [/没有/g, /不要/g, /不能/g, /无任何/g, /去掉/g, /去除/g, /禁止/g, /避免/g, /不出现/g, /不带/g];

/** L4 即梦版负向词。模型对否定词不敏感——想要干净背景写「纯色极简背景」，而不是「没有杂物」。 */
export function lintNegation(prompt: CompiledPrompt): Finding[] {
  if (prompt.model !== 'jimeng' || !prompt.text2img) return [];
  let text = prompt.text2img;
  for (const allowed of ALLOWED_NEGATIONS) text = text.split(allowed).join('');

  const hits = NEGATION_PATTERNS.flatMap((p) => text.match(p) ?? []);
  if (!hits.length) return [];
  return [{
    rule: 'L4',
    level: 'warn',
    where: 'jimeng.text2img',
    message: `即梦版提示词出现否定式表述「${[...new Set(hits)].join('、')}」。国产模型对否定词不敏感，改写成正向描述，或把该条移到平台的负向词输入框。`,
  }];
}

const QUALITY_LEXICON = [
  '8K细节', '8K', '4K', '超写实', '高清', '精致细节', '高级质感', '电影级画质',
  '商业广告级画质', '大师作品', '极致细节', 'masterpiece', 'best quality', 'photorealistic', 'ultra detailed',
];

/** L5 画质词点到为止。堆砌不会更清晰，只会稀释权重。 */
export function lintQualityWords(prompt: CompiledPrompt): Finding[] {
  if (!prompt.text2img) return [];
  const text = prompt.text2img;
  const hits: string[] = [];
  let remaining = text;
  // 长词优先，避免 "8K细节" 被 "8K" 抢先匹配后重复计数
  for (const w of [...QUALITY_LEXICON].sort((a, b) => b.length - a.length)) {
    if (contains(remaining, w)) {
      hits.push(w);
      remaining = remaining.split(w).join('');
    }
  }
  if (hits.length <= 2) return [];
  return [{
    rule: 'L5',
    level: 'warn',
    where: `${prompt.model}.text2img`,
    message: `画质词 ${hits.length} 个（${hits.join('、')}），超过 2 个。堆砌不会更清晰，只会稀释前面风格和主体的权重。`,
  }];
}

/**
 * L6 品牌名外泄。
 *
 * 参考图常是竞品或版权素材，反推的目的是提取风格语言。
 * 除非 Brief 显式 must_keep，原图品牌名不得出现在任何编译产物里。
 */
export function lintBrandLeak(spec: StyleSpec, brief: Brief, prompt: CompiledPrompt): Finding[] {
  const keep = new Set((brief.must_keep ?? []).map((s) => s.trim().toLowerCase()));
  const brands = spec.content.brand_marks.filter((b) => !keep.has(b.trim().toLowerCase()));
  if (!brands.length) return [];

  const findings: Finding[] = [];
  const outputs: Array<[string, string | null]> = [
    ['text2img', prompt.text2img],
    ['img2img_edit', prompt.img2img_edit],
    ['img2img_style_ref', prompt.img2img_style_ref],
  ];
  for (const [field, text] of outputs) {
    if (!text) continue;
    for (const brand of brands) {
      if (contains(text, brand)) {
        findings.push({
          rule: 'L6',
          level: 'error',
          where: `${prompt.model}.${field}`,
          message: `原图品牌「${brand}」出现在提示词中。参考图多为竞品或版权素材，品牌痕迹必须去除；确需保留请写进 brief.must_keep。`,
        });
      }
    }
  }
  return findings;
}

/** StyleSpec 级检查（不依赖 Brief 和编译产物）。 */
export function lintSpec(spec: StyleSpec): Finding[] {
  return [...lintContentLeakage(spec), ...lintFormConflict(spec)];
}

/** 编译产物级检查。 */
export function lintPrompt(spec: StyleSpec, brief: Brief, prompt: CompiledPrompt): Finding[] {
  return [
    ...lintEditBoundary(prompt),
    ...lintNegation(prompt),
    ...lintQualityWords(prompt),
    ...lintBrandLeak(spec, brief, prompt),
  ];
}
