import type { Brief, CompiledPrompt, StyleSpec } from '../../types.js';
import {
  join, paletteText, colorText, lightingText, materialText, formText,
  compositionText, styleFamilyText, rewriteAvoid, qualityWords, refProtocol, copyText,
} from '../shared.js';
import { SHOT_CN, ANGLE_CN, MEDIUM_CN } from '../vocab.js';

/**
 * 即梦 / 豆包 / 可灵适配器。规则源：references/jimeng.md
 *
 * 基本公式：风格媒介 + 景别视角 + 主体（外观细节）+ 动作状态 + 场景环境
 *          + 光线 + 色调 + 氛围 + 画质词
 *
 * 关键约束（由代码保证，不靠模型自觉）：
 * - 先重后轻：模型对开头权重更高，风格 + 主体必须排最前。
 * - 正向表述：禁止项转正向，转不了的不写进提示词（见 rewriteAvoid）。
 * - 画质词 ≤ 2：堆砌只会稀释权重（见 qualityWords）。
 * - 画幅比例在平台界面选，提示词里只写构图意图。
 */
export function compileJimeng(spec: StyleSpec, brief: Brief): CompiledPrompt {
  const notes: string[] = [];

  const styleHead = join([styleFamilyText(spec, 'cn'), MEDIUM_CN[spec.medium]], '');
  const shot = `${SHOT_CN[spec.composition.shot]}${ANGLE_CN[spec.composition.angle]}`;
  const subject = join([brief.subject, brief.subject_detail], '，');

  const avoid = rewriteAvoid(brief.must_avoid);
  if (avoid.unconvertible.length) {
    notes.push(
      `以下禁止项无法转成正向表述，不写进提示词（模型对否定词不敏感）；` +
      `请在平台的负向词/排除词输入框填写：${avoid.unconvertible.join('、')}`,
    );
  }

  const q = qualityWords(brief);
  if (q.dropped.length) {
    notes.push(`画质词点到为止，已丢弃超出 2 个的部分：${q.dropped.join('、')}`);
  }

  // 先重后轻。顺序即权重，不要随意调整。
  const text2img = join([
    styleHead,
    shot,
    subject,
    brief.action,
    brief.scene,
    lightingText(spec),
    join([colorText(spec), paletteText(spec, false)]),
    materialText(spec),
    formText(spec),
    compositionText(spec, brief),
    copyText(brief, spec),
    spec.mood.join('、') + '氛围',
    ...avoid.positives,
    ...q.words,
  ]);

  if (!brief.render_text_in_image && (brief.copy?.title || brief.copy?.subtitle || brief.copy?.body)) {
    notes.push('文案未写进提示词：先生成主视觉，标题后期以可编辑图层叠加，文字正确性和排版更可控。需要模型直接画字请把 brief.render_text_in_image 设为 true。');
  }

  notes.push(`画幅比例 ${brief.aspect_ratio} 请在平台界面选择，提示词里只写了构图意图。`);

  const styleRef = buildStyleRef(spec, brief);

  return {
    model: 'jimeng',
    aspect_ratio: brief.aspect_ratio,
    text2img,
    img2img_edit: null, // 边界控制四纪律是 GPT Image 2 的编辑能力，即梦侧不产出局部编辑指令
    img2img_style_ref: styleRef,
    ref_protocol: refProtocol(brief),
    notes,
    parts: { edit: null },
  };
}

/**
 * 图生图风格参考指令。
 * 形态这类「只可意会」的特征，让模型看一眼原图比纯文字描述准得多——
 * 文生图两轮都不像时，这是第一修复路线。
 */
function buildStyleRef(spec: StyleSpec, brief: Brief): string {
  const keep = join([
    formText(spec),
    `${colorText(spec)}的色彩关系`,
    materialText(spec),
  ], '；');
  return join([
    '上传参考图作为风格参考',
    `保持其${keep}`,
    `画面主体替换为${join([brief.subject, brief.subject_detail], '，')}`,
    '仅提取参考图的视觉风格，画面内容与文字全部按新主体重新绘制',
  ], '，');
}
