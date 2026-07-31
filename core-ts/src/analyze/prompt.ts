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
  const schemaPath = resolve(SCHEMA_DIR, 'stylespec.v0.2.json');
  // 默认写到当前工作目录的 specs/ 下，绝不落回原图目录——原始图片全程只读
  const out = outPath
    ?? resolve(process.cwd(), 'specs', basename(imagePath).replace(/\.[^.]+$/, '') + '.stylespec.json');

  return `# 任务：把参考图分析成 StyleSpec v0.2

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
\`repetition\`、\`lighting.sources\`、\`material.surfaces[].where\`、\`mood\`、
\`composition.element_stacking\`、\`composition.panels[].role\`）必须写成
**换个主体照样成立**的抽象规则。

\`element_stacking\` 尤其容易犯错——它是这轮新加的字段，写的时候很自然会直接点名
"像素马图形""体重秤主体"这类原图具体物件，但这跟 \`grid\` 不能写"底部大字"是同一个坑：

- ✗ \`element_stacking: ["顶部大字标题", "中央像素马图形", "下部小字"]\` — "像素马图形"是原图内容
- ✓ \`element_stacking: ["标题文字组", "主图形", "小字组"]\` — 角色描述，换主体照样成立

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

### 7. 运动：schema 还没有它的家

v0.2 仍然没有 motion 块（已知缺口，见 docs/analysis-gaps.md 的 G4，等实测工具再补，
不是靠模型眼估）。拖影、长曝、频闪遇到时按下面临时安置，不要硬塞进 \`material\` 或
\`form_language\`——那两块有各自的编译语义，塞错会串味：

- 写进 \`style_family\`（如「长曝光动态摄影 / long-exposure motion photography」，
  它会被编在提示词最前面），角度和强度写进 \`notes\`。
  角度靠眼估很容易夸大：看着像斜的，实测常常只偏离水平 10 度左右，写"斜向"会让模型转到 45 度。
  说不准就只写"近水平的方向性拖影"。

排版方向（横排拉丁 + 竖排中文混排这类）现在有地方写了，见下一节。

### 8. 不确定就标出来
一眼看不准的维度写进 \`confidence.uncertain_fields\`（点号路径，如 \`typography.typeface_class\`），
不要含糊带过，也不要瞎猜。\`confidence.overall\` 给一个诚实的整体置信度。

### 9. v0.2 新增字段

这轮新增的字段专治"肉眼一眼就能看出错，但 v0.1 没地方写"的几类问题。逐条说明：

**source.width / source.height / source.aspect_exact —— 精确画幅，不许目测**
用 shell 工具量出真实像素尺寸（比如 macOS 的 \`sips -g pixelWidth -g pixelHeight "<路径>"\`，
或任何你能调用的图像信息工具），把读出来的整数直接填进去，\`aspect_exact = width / height\`。
这条不需要模型判断，只是不要用眼睛估"看起来像 3:4"——量出来的数字和估的数字经常对不上。
\`composition.aspect_ratio\` 那个"3:4"式的类别字段仍然保留，两个字段都要填。

**content.on_image_text[] 的新字段 —— 排版不只是文字内容**
每一段文字除了 \`text\`/\`position\`/\`role\`，都要补：

- \`ocr_status\`：\`exact\`=看得清能原样照抄；\`approx\`=大意对但个别字不确定；
  \`unclear\`=认不出具体文字，**这段绝不能编造成正文**，只描述字形和位置。这条是硬性的——
  编不出来的字硬编成文案，比留空更糟。
- \`line_breaks\`：这段文字实际怎么分行，按视觉顺序列出每一行。只有一行不用写。
  不要把画面上明明分成几行的字，在 JSON 里拼成一整句字符串——断行方式本身就是版式的一部分。
- \`layer\`：\`front\`/\`middle\`/\`back\`，这段字和画面其他元素比大致谁前谁后，不用精确坐标。
- \`color\`：这段字的颜色，优先给 hex（尽量能对上 \`palette\` 里的某个色），取不准写简短描述。
- \`relative_size\`：\`largest\`/\`large\`/\`medium\`/\`small\`/\`smallest\`，这段字相对画面里
  其他文字的大小级别，不是像素字号，是用来还原"哪段字最大、哪段最小"这个层级关系的。
- \`distortion\`：文字有没有被变形——沿路径弯曲、透视斜切、旋转、拉伸、描边分层立体字，
  平直无变形写 \`none\`（默认）。
- \`typeface_note\`：只有这段字的字体明显不同于 \`typography.typeface_class\` 整体判断时才填
  （比如正文是无衬线，但这个标题是手写花体或定制美术字）。

**typography.implicit_alignment —— 多段文字之间的隐形关系**
这些文字块靠什么互相咬合成一个整体：共用同一条左对齐线、顶边对齐、行距和字块间距保持统一
比例。写成可迁移的抽象规则（参考第 6 条的写法），不点名具体文案内容。

**content.carrier_type —— 这张图到底是什么载体**
判断这是 \`flat_design\`（平面设计原图本身）、\`print_on_object\`（印在书/T恤/杯子等物体上
被拍下来的照片）、\`screenshot\`（界面或作品页截图）、\`photo_scene\`（实景照片）还是
\`unknown\`（判断不了）。**判断不准就老实给低 confidence，并在 \`candidates\` 里列出备选**，
不要为了让字段"看起来确定"就瞎选一个锁死——载体判断错了，后面整个复现方向都会偏。

**composition.panel_count / panels —— 会不会其实是好几块拼的**
单张设计图写 \`panel_count: 1\`，不用填 \`panels\`。如果画面其实是作品页截图里的上下两张图、
杂志跨页、多宫格拼贴，\`panel_count\` 填实际块数，\`panels\` 逐块记大致区域和角色。
**多面板的图千万不要当成一整张来分析**——那正是 v0.1 最容易犯的错。

**content.visible_only / external_expansion_risk —— 禁止脑补**
默认 \`visible_only: true\`：只描述画面里实际可见的内容。如果画面里出现品牌名、IP、知名
作品这类容易触发你自己常识联想的词，把它们列进 \`external_expansion_risk\`——这是提醒
编译层"这里容易被模型自己脑补出画面之外的内容，需要加约束"，不是让你去联想着写更多细节。

**composition.element_stacking —— 谁挡谁（基础版）**
画面主要元素按前后顺序列出（从最前到最后的字符串数组），只要相对顺序，不用坐标。
只在确实存在遮挡/层叠关系时才有意义，元素本来就互不重叠可以不填。

## 完成后
运行这两条命令确认合法：

\`\`\`bash
npx i2p validate ${out}
npx i2p lint ${out}
\`\`\`

lint 报 error 必须修掉再交付（L1 内容泄漏、L2 形态词冲突是最常见的两条）。
`;
}
