import type { Brief, CompiledPrompt, EditParts, StyleSpec } from '../../types.js';
import {
  join, pct, paletteText, colorText, lightingText, materialText, formText,
  compositionText, styleFamilyText, rewriteAvoid, qualityWords, refProtocol, copyText,
  resolveSafeArea, panelText, stackingText,
} from '../shared.js';
import { SHOT_CN, ANGLE_CN, MEDIUM_CN, NEGATIVE_REGION_CN, DENSITY_CN } from '../vocab.js';

/** 编译期失败：提示词不该被产出成一个已知会出问题的样子。 */
export class CompileError extends Error {
  constructor(public rule: string, message: string) {
    super(message);
    this.name = 'CompileError';
  }
}

/** 量词会扫射到编辑边界外，必须在编译期拦下。 */
const BLANKET_QUANTIFIER = /所有|全部|每一个|每个|各个|凡是|一切/;

/**
 * GPT Image 2 适配器。规则源：references/gpt-image.md
 *
 * 与国产模型写法的最大差异：指令遵循极强，空间关系、数量、占比可以写死硬约束。
 */
export function compileGptImage(spec: StyleSpec, brief: Brief): CompiledPrompt {
  const notes: string[] = [];

  const avoid = rewriteAvoid(brief.must_avoid);
  const q = qualityWords(brief);
  if (q.dropped.length) notes.push(`画质词已截断至 2 个，丢弃：${q.dropped.join('、')}`);

  const text2img = buildText2Img(spec, brief, avoid.positives, q.words);

  let editParts: EditParts | null = null;
  let img2imgEdit: string | null = null;
  if (brief.edit) {
    editParts = buildEditParts(brief);
    img2imgEdit = join([editParts.scope, editParts.protect, editParts.replace, editParts.noAddNoRemove], '。') + '。';
    if (brief.edit.merge_requirements) {
      img2imgEdit += brief.edit.merge_requirements.replace(/。$/, '') + '。';
    } else {
      notes.push('brief.edit.merge_requirements 为空。融合要求（新元素匹配原图光影透视、接触面阴影自然）这一句决定成品像不像 P 上去的，建议补上。');
    }
  } else {
    notes.push('未提供 brief.edit，不产出垫图编辑指令。换主体/改局部请填写 edit 块（scope_anchor + protect + replace），四个部件齐全才会编译。');
  }

  if (avoid.unconvertible.length) {
    notes.push(`GPT Image 2 对否定约束的遵循强于国产模型，以下禁止项已直接写入提示词：${avoid.unconvertible.join('、')}`);
  }

  return {
    model: 'gpt-image',
    aspect_ratio: brief.aspect_ratio,
    text2img,
    img2img_edit: img2imgEdit,
    img2img_style_ref: buildStyleRef(spec, brief),
    ref_protocol: refProtocol(brief),
    notes,
    parts: { edit: editParts },
  };
}

function buildText2Img(spec: StyleSpec, brief: Brief, positives: string[], quality: string[]): string {
  const c = spec.composition;
  const head = join([styleFamilyText(spec, 'cn'), MEDIUM_CN[spec.medium]], '') + '：';
  const shot = `${SHOT_CN[c.shot]}${ANGLE_CN[c.angle]}`;

  // GPT Image 2 的强项：位置和占比可以写死
  const placement = c.subject_position === 'none'
    ? '画面无明确主体'
    : join([
        join([brief.subject, brief.subject_detail], '，'),
        `位于${compositionAnchor(spec)}，占画面约 ${pct(c.subject_coverage)}`,
      ]);

  const region = NEGATIVE_REGION_CN[c.negative_space.region] ?? '';
  const negative = region ? `${region}为干净负空间，约占画面 ${pct(c.negative_space.ratio)}` : null;
  const safeArea = resolveSafeArea(spec, brief);

  const avoidClause = brief.must_avoid?.length
    ? `画面中不出现${brief.must_avoid.join('、')}`
    : null;

  // medium_detail 是分析器写的具体媒介描述（"平面海报设计：像素图形 + 超大字重排版"），
  // 比 medium 枚举（"排版海报"）信息量高一个数量级，之前整段被丢掉。
  // 单独一段而不是拼进 head：它自带冒号，塞进 head 会拼出两个冒号的病句。
  const mediumDetail = spec.medium_detail?.trim() || null;

  return join([
    head + shot,
    mediumDetail,
    placement,
    brief.action,
    brief.scene,
    lightingText(spec),
    join([colorText(spec), paletteText(spec, true)]),
    materialText(spec),
    formText(spec),
    negative,
    c.grid,
    // 密度：即梦走 compositionText 一直带着它，GPT Image 自己拼 placement 时漏了。
    // 这是两个适配器的不一致，不是设计取舍。
    DENSITY_CN[c.density],
    c.bleed ? '图形四边出血裁切' : null,
    panelText(spec),
    stackingText(spec),
    safeArea && !brief.render_text_in_image ? `${safeArea}保持干净，供后期叠加文字图层` : null,
    copyText(brief, spec),
    spec.mood.join('、') + '氛围',
    ...positives,
    avoidClause,
    ...quality,
  ]);
}

/** 主体位置锚点，尽量落成 GPT Image 2 能精确执行的空间描述。 */
function compositionAnchor(spec: StyleSpec): string {
  const map: Record<string, string> = {
    center: '画面正中',
    left: '画面左侧',
    right: '画面右侧',
    top: '画面上方',
    bottom: '画面下方',
    top_left: '画面左上角区域',
    top_right: '画面右上角区域',
    bottom_left: '画面左下角区域',
    bottom_right: '画面右下角区域',
    lower_third: '画面下三分之一处',
    upper_third: '画面上三分之一处',
  };
  return map[spec.composition.subject_position] ?? spec.composition.subject_position;
}

/**
 * 边界控制四纪律。编辑模型有「主题一致化」倾向：大面积替换后会把画面里相似的元素
 * 全部和谐成同一主题，还可能无中生有补充「符合主题」的新物体。
 *
 * 四个部件必须齐全——任一缺失在这里抛错，而不是产出一条已知会溢出的指令。
 */
function buildEditParts(brief: Brief): EditParts {
  const edit = brief.edit!;

  // 纪律一：第一句先用视觉锚点圈范围
  if (!edit.scope_anchor?.trim()) {
    throw new CompileError('L3.scope', '缺少 edit.scope_anchor：编辑指令第一句必须用看得见的视觉锚点圈定范围。');
  }
  if (/我们的|自己的|本方|该公司的/.test(edit.scope_anchor)) {
    throw new CompileError(
      'L3.scope',
      `scope_anchor 使用了模型看不见产权的概念词（"${edit.scope_anchor}"）。改用视觉锚点，如「画面中央偏右、带深灰色悬浮顶棚的那一个展位」。`,
    );
  }
  const scope = `仅编辑${edit.scope_anchor.replace(/。$/, '')}，此范围以外的画面保持与原图完全一致`;

  // 纪律二：保护清单点名原有内容——点名原内容等于把它锚死
  if (!edit.protect?.length) {
    throw new CompileError('L3.protect', '缺少 edit.protect：保护清单与修改清单同等重要，必须点名不许动的元素及其原有内容。');
  }
  const protectItems = edit.protect.map((p) => {
    if (!p.original_content?.trim()) {
      throw new CompileError('L3.protect', `保护项「${p.element}」未写 original_content。点名原有内容才能把它锚死。`);
    }
    return `${p.element}（原为${p.original_content}）`;
  });
  const protect = `以下元素保持与原图完全一致：${protectItems.join('、')}`;

  // 纪律三：枚举替换目标，禁用量词
  if (!edit.replace?.length) {
    throw new CompileError('L3.replace', '缺少 edit.replace：必须逐个枚举替换目标。');
  }
  const replaceItems = edit.replace.map((r) => {
    if (BLANKET_QUANTIFIER.test(r.target)) {
      throw new CompileError(
        'L3.replace',
        `替换目标「${r.target}」含扫射性量词。量词会让编辑溢出到边界外，请逐个枚举具体目标（如「该展位正面两块大屏 + 右侧双面灯箱」）。`,
      );
    }
    return `${r.target}替换为${r.new_content}`;
  });
  const replace = `在上述范围内，将${replaceItems.join('；')}`;

  // 纪律四：禁增禁删
  const noAddNoRemove = '只替换以上点名的元素，不新增任何原图中不存在的物体，不删除未点名的元素';

  return { scope, protect, replace, noAddNoRemove };
}

/**
 * 垫图风格参考指令（区别于局部编辑）。模式 A 的标配输出。
 * 中英并写：GPT Image 2 对英文风格术语响应更准。
 */
function buildStyleRef(spec: StyleSpec, brief: Brief): string {
  const en = spec.style_dna_en ? `（英文风格参考：${spec.style_dna_en}）` : '';
  const enFamily = styleFamilyText(spec, 'en');
  return join([
    '上传参考图，仅作风格参考',
    `提取其风格语言：${join([formText(spec), materialText(spec), colorText(spec)], '；')}`,
    enFamily ? `风格流派 ${enFamily}` : null,
    `画面内容改为${join([brief.subject, brief.subject_detail], '，')}，按新主体重新构图`,
    '参考图的具体物体、场景和文字不进入生成结果',
  ], '，') + en;
}
