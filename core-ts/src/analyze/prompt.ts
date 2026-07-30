import { basename, resolve } from 'node:path';
import { SCHEMA_DIR } from '../validate.js';

/**
 * 生成交给 Claude Code / Codex 执行的分析指令。
 *
 * 视觉层刻意留在平台原生能力上：Read 工具（或 Codex 原生多模态）就是最好的识图引擎，
 * 零 API、零配置、零成本。本模块只负责把 SKILL.md 模式 A 的方法论编成一份
 * 会产出合法 StyleSpec JSON 的指令，不做任何视觉调用。
 */
export function buildAnalyzePrompt(imagePath: string, outPath?: string): string {
  const schemaPath = resolve(SCHEMA_DIR, 'stylespec.v0.1.json');
  // 默认写到当前工作目录的 specs/ 下，绝不落回原图目录——原始图片全程只读
  const out = outPath
    ?? resolve(process.cwd(), 'specs', basename(imagePath).replace(/\.[^.]+$/, '') + '.stylespec.json');

  return `# 任务：把参考图分析成 StyleSpec v0.1

## 图片
${imagePath}

**先用 Read 工具真的把这张图读进来再分析。绝不凭记忆或想象猜测图片内容。**
读不到（路径不存在）就停下来说明，不要编造。

## 输出
写入 JSON 文件：${out}
Schema（先读一遍，字段和枚举值以它为准）：${schemaPath}

## 分析方法

### 1. 判别广告图类型 → ad_type
先看两个信号，最快把类型分开：主体占比、背景干净程度。

- 单一主体占 1/3 以上 + 影棚感光线 + 背景干净 → \`hero_shot\`
- 主体处于真实生活环境、常有人物或手部交互、自然光 → \`lifestyle\`
- 大面积留白、主体小或边缘化、情绪光、预留文案位 → \`mood_poster\`
- 没有明确主体，画面是纹理/渐变/空镜，明显为叠加内容服务 → \`background\`
- 高饱和明快、促销道具、文案占比大 → \`promo_banner\`
- 超现实元素（尺度错位、材质置换、场景嫁接）→ \`concept\`

判别出类型后，按该类型的强化维度重点观察：
- hero_shot：轮廓光方向和颜色、台面材质、高光和反射位置、背景渐变走向
- lifestyle：人物具体动作（尤其手怎么接触产品）、时段和光源、背景虚化程度
- mood_poster：留白位置和占比、文案位在哪、主体的精确位置（几分之几处）
- background：纹理类型和渐变走向、明暗分布、细节密度是否均匀、可叠加安全区
- promo_banner：文案区位置和占比、道具清单、舞台结构、主色系
- concept：创意手法是哪种、喻体是什么、写实程度

### 2. 风格命名 → style_family
给最接近的 1-2 个流派命名，每个都要写 \`evidence\`（画面上的具体证据，不是感受）。
混合风格标 \`role\`：\`primary\` 主体流派 + \`borrowed\` 借用元素。
\`name_en\` 必填——GPT Image 2 对英文风格术语响应更准。

### 3. 内容与风格彻底分开（本任务的核心）

\`content\` 块是隔离区，写清楚画面里**实际有什么**：
- \`subject\` / \`scene\`：具体描述
- \`brand_marks\`：所有品牌名和 logo 文字，一个都不能漏
- \`on_image_text\`：画面上的文字及其位置
- \`keywords\`：内容层的所有具体名词，**中英并列都写**。这个数组会被 lint 逐个拿去检查 style_dna 有没有泄漏，所以要写具体名词（"登山靴""云海""iPhone"），不要写形容词（"高级""干净"）。单个汉字不会被检查，至少两个字。

\`style_dna\` 是与画面内容**完全无关**的风格描述块。
检验标准：把任何新主体塞进去都成立。写完自己过一遍——里面出现了 \`keywords\` 里的任何词，就是失败，重写。
\`style_dna_en\` 同样写一份英文版。

反例：「低饱和冷蓝色调，海边的女孩位于下三分之一」← "海边""女孩"是内容，泄漏了
正例：「低饱和冷蓝色调，大面积天空负空间，主体位于下三分之一，柔和逆光，胶片颗粒，安静疏离的电影感」

### 4. 形态语言 → form_language（最容易写错的一块）
先自问：**这是几何圆角，还是有机曲线？** 两者气质完全不同，写错一个词生成方向就全偏。

- 平直边缘 + 圆角，饱满但硬朗 → \`geometry: geometric_rounded\`，\`edge: large_radius_rounded\`
- 连续曲率、液态感轮廓、波浪起伏 → \`geometry: organic_fluid\`，\`edge: wavy\`

\`gap_rule\` 写成可执行的比例——「宽度严格一致，约为笔画宽度的三分之一」这种。
等宽窄沟槽和随意宽缝隙是两种设计，负空间的宽度规则是风格的一部分。

**注意**：如果判为几何形态，style_dna 里就不要出现"液态""流动""膨胀""波浪"这类词，
lint 会报冲突——这些词单独使用会把生图模型推向有机泡泡形态。

### 5. 量化优先
\`subject_coverage\`、\`negative_space.ratio\`、\`palette[].ratio\` 全部用 0-1 的数值。
"大面积留白"编译不成硬约束，"上方 55%" 可以。
\`density\` + \`bleed\` + \`subject_coverage\` 三个字段一起把"满版"这类模糊描述写死。

色板取到能看出的主色/辅色/点缀色，\`hex\` 要真的从画面取色，\`ratio\` 加起来接近 1。

**但主体边界分不出来时，\`subject_position\` 填 \`none\`。** 动态模糊、纹理背景、多主体重叠
都属于这一类。schema 不收 null，\`none\` 就是它的出口——填了它，编译器会整段跳过位置和占比，
不会把一个编造的「占画面 70%」写成硬约束。分不清还硬填数字，比留空有害。

### 6. 自由文本字段不要点名原图的具体元素

会被编进提示词的自由文本字段（\`composition.grid\`、\`form_language.gap_rule\` /
\`repetition\`、\`lighting.sources\`、\`material.surfaces[].where\`、\`mood\`）必须写成
**换个主体照样成立**的抽象规则。

- ✗ \`grid: "主图形与底部大字之间留一条横带"\` — "底部大字"是原图内容，换主体后是噪音
- ✓ \`grid: "四边贴边满宽单栏 + 居中对称轴"\`

**网格必须说明可见性。** 排版网格通常只是对齐用的隐形约束，但生图模型会把「三栏网格」
当成要画出来的图形，直接给你画三条竖线。

- ✗ \`grid: "三栏满宽网格"\`
- ✓ \`grid: "隐形三栏对齐系统，不画分隔线、栏线和边框"\`

**\`mood\` 只写气质，不写名物性的联想词。** 生图模型会把「书卷气」实体化成书本、
把「科技感」实体化成芯片。要写「克制、内敏的编辑感」，不要写「文人书卷气」。
mood 是被逐字编进正向提示词的——它比 style_dna 更靠近生成结果。

这几个字段的内容泄漏 lint L1 现在会逐个查（早期只查 style_dna，漏得最狠的恰好不是它）。

以下字段是给人看的分析记录，**不会**进入编译产物，可以放心点名原图元素：
\`composition.visual_flow\`、\`negative_space.note\`、\`typography.note\`、\`notes\`。

### 7. 运动和排版方向：schema 还没有它们的家

v0.1 没有 motion 块，也没有排版方向字段。遇到这两类特征，按下面临时安置，不要硬塞进
\`material\` 或 \`form_language\`——那两块有各自的编译语义，塞错会串味：

- 拖影、长曝、频闪 → 写进 \`style_family\`（如「长曝光动态摄影 / long-exposure motion
  photography」，它会被编在提示词最前面），角度和强度写进 \`notes\`。
  角度靠眼估很容易夸大：看着像斜的，实测常常只偏离水平 10 度左右，写"斜向"会让模型转到 45 度。
  说不准就只写"近水平的方向性拖影"。
- 横排拉丁 + 竖排中文混排 → 写进 \`typography.note\`（不进提示词，但是分析记录的一部分）。

### 8. 不确定就标出来
一眼看不准的维度写进 \`confidence.uncertain_fields\`（点号路径，如 \`typography.typeface_class\`），
不要含糊带过，也不要瞎猜。\`confidence.overall\` 给一个诚实的整体置信度。

## 完成后
运行这两条命令确认合法：

\`\`\`bash
npx i2p validate ${out}
npx i2p lint ${out}
\`\`\`

lint 报 error 必须修掉再交付（L1 内容泄漏、L2 形态词冲突是最常见的两条）。
`;
}
