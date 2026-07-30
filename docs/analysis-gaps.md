# 分析层已知缺口

来源：2026-07-30 的纠偏报告（`~/Documents/Codex/2026-07-28/1-2-3/outputs/image2prompt-analysis-correction-report-2026-07-30.md`）
加一轮代码复核和实测。

**这份文档的状态是「刻意不改」。** 除下面「已落地」那两条，其余全部挂账。理由：链路还没跑完，
现在改 schema 是拿猜测下注——空改的风险不是白做工，是把猜测焊进 schema，之后每一版都得背着它。
等批量跑图出了证据再动，每条都写了触发条件。

先记一个容易搞错的前提：**那次盲测没有测到产品的输出。** 它把 App 详情页三张展示卡片
（风格 DNA / 色板 / 视觉语法）的文字喂给生图模型，而 `text2img` 是从结构化字段现拼的，
`style_dna` 压根不进提示词（只有 `style_dna_en` 出现在垫图风格参考句尾，
[gptImage.ts:183](../core-ts/src/compile/adapters/gptImage.ts:183)）。
所以「三个板块有没有意义」这个问题问偏了，但它误撞出的病灶是真的——见下。

---

## 已落地（2026-07-30）

| 改动 | 位置 | 解决什么 |
|---|---|---|
| L1 lint 从只查 `style_dna` 扩到**所有会被编译的自由文本字段**：`mood[]`、`composition.grid`、`typography.safe_area`、`form_language.gap_rule/repetition`、`lighting.sources[]`、`material.surfaces[].where/detail` | `core-ts/src/lint/rules.ts` 的 `compiledFreeText()` | 「书卷气 → 满屏是书」的真凶是 `mood`（被逐字编进正向提示词，`gptImage.ts:99` / `jimeng.ts:53`），旧 L1 查不到它 |
| 分析指令两份同步：`subject_position: none` 出口、网格必须声明隐形、`mood` 禁名物性联想词、运动与排版方向的临时落点 | `core-ts/src/analyze/prompt.ts` + `app/.../Resources/analyze-prompt.md` | 编造的「占 70%」、被画出来的栏线、被实体化的气质词 |

两条都是零 schema 变更。`subject_position: none` 是 schema 里本来就有的出口——填它编译器会整段跳过
位置和占比（[shared.ts:94](../core-ts/src/compile/shared.ts:94)），不需要等 nullable 改造。

**App 里没有 lint。** 详情页那张「内容泄漏」卡显示的是分析器自己填的 `content_leakage` 字段，
不是 L1 的结果。批量跑完要补一轮：

```bash
for f in specs/*.stylespec.json; do npx i2p lint "$f"; done
```

---

## 回归证据（别删这两张图）

| | 路径 |
|---|---|
| 原图 | `pictext/🔴设计师是个岗位，而设计是一场生意_1_平面秩序_来自小红书网页版.jpg` |
| 盲测生成图 | `~/Documents/Codex/2026-07-28/1-2-3/outputs/image-evals/style-dna-blind-reconstruction-2026-07-30.png` |

拖影轴实测（ffmpeg 降到 270×360 转灰度 + 结构张量；0°=水平，正值=向右下倾，方向性 0–1 越高越像单一方向的干净长条）：

| 区域 | 原图 | 盲测生成图 |
|---|---|---|
| 上部 0–25% | +12.1°，方向性 0.24 | +87.6°，0.52 ← 量到的是它自己画的竖分隔线 |
| 中部 25–62% | +76.1°，0.10 ← 被竖排中文的梯度污染 | −0.2°，0.96 |
| 下部 62–100% | +9.4°，0.18 | +1.1°，0.68 |

两个结论都反直觉，将来做 motion 块时别忘：

1. 原图的轴只偏离水平 **10 度左右**，不是"斜向"。报告里那句 `diagonal toward upper-left`
   照抄进提示词会让模型转到 45 度，是**换一个新错误**。角度必须实测，不能靠形容词转述。
2. 真正丢掉的不是角度，是**方向一致性**（0.10–0.24 → 0.70–0.96，生成图的拖影干净了 4–9 倍：
   原图是软糊、人形还认得出，生成图是长条光轨）和**主体可辨识度**。
   所以 motion 块的字段应该是 `{ angle, coherence, subject_legibility }`，前两个都能用二十行代码算，
   不需要模型估。测之前要先掉字或上 OCR mask，否则竖排中文会污染中部读数。

---

## 挂账清单

按「跑图之后大概会撞到的顺序」排，不是按重要性。

| # | 缺口 | 证据 | 触发条件 | 改动面 |
|---|---|---|---|---|
| G1 | `composition.grid` 只有自由文本，没有 `grid_visibility` 枚举——隐形网格靠分析器自觉写"不画分隔线"，没有强制 | grid 原样进提示词（[gptImage.ts:95](../core-ts/src/compile/adapters/gptImage.ts:95)） | 批量跑完后仍有图被画出栏线 | schema 加可选枚举 + 两套 compile + Swift decode。可选字段，无迁移 |
| G2 | schema 逼模型编造：`composition.required` 里 `shot`/`angle`/`subject_coverage` 必填不可 null，枚举也没有 unknown 档 | `schema/stylespec.v0.1.json` | 现在有 `none` 兜住占比；等出现"景别也不该有值"的样本再动 | 少数字段 nullable，**不要**给全字段套 `EvidenceValue<T>` |
| G3 | 不确定性从不影响提示词：`confidence` 在 `core-ts/src/compile/` 和 `lint/` 里零引用，`uncertain_fields` 是纯展示 | grep 无命中 | 与 G2 同批做 | compiler 读 `uncertain_fields`：列进去的字段降级为柔性描述或不编译 |
| G4 | 全库没有「运动」这个概念：`motion`/`blur`/长曝在 schema、vocab、knowledge 里全无。唯一相关的一条还是反向的——`vocab.ts:294` 把"模糊"当缺陷改写成「全画面清晰锐利」 | 见上 | 图库里动态摄影类样本比例值得投入时（先数一下 `pictext/` 里有几张） | 新增 `motion` 块 + 一个实测角度的小工具 + 两套 compile |
| G5 | 排版只有 `typeface_class`/`alignment`/`case`，**没有方向也没有分块**。原图最抢眼的横排拉丁 + 竖排中文双系统交错完全不可表达，所以盲测把所有字排成了横的 | `schema` 的 `typography` 块 | **做「塞我自己的内容」之前必须先做**——这是复制度的主菜 | 新增 `layout` 块（文字块位置/方向/断行/层级）。它既不是风格也不是内容，是容器 |
| G6 | `mood` 的实体化风险只靠分析指令约束，lint 查不出来（L1 只比对内容词，管不了"书卷气"这种从没在画面里出现过的联想词） | 已落地那条只解决了内容词 | 跑图后统计有多少张 mood 里带名物性联想词 | 要么一份禁用词表（脆），要么 compile 时把 mood 降级成弱提示（更稳） |
| G7 | `ad_type` 在 compile 和 drift 里零消费，只在分析指令里当观察引导 + 详情页显示一行 | grep 只有 4 处命中 | 顺手 | 展示卡去掉这一行，或标注"仅供分析"。零风险 |
| G8 | 「视觉语法」卡三种性质混装：5 行是 drift 真能运算的轴（形态/密度/色温/明暗/饱和），4 行是编译期硬约束，1 行是会被实体化的联想词（气质），1 行没人消费（广告类型） | [DetailView.swift:163](../app/Sources/Formless/UI/DetailView.swift:163) | 做调色盘 UI 时一起改 | 按「可运算 / 硬约束 / 仅供理解」分三组。用户现在没法知道改哪行会真的变 |

---

## 不打算做的

| 报告的建议 | 不做的理由 |
|---|---|
| 给全字段套 `EvidenceValue<T>`（value + confidence + provenance + evidence） | TS 类型、两套 compile、Swift decode、drift、lint、两个 fixture 全要改，收益集中在少数几个真会被编造的字段上。改法降级为 G2 + G3 |
| `confidence.overall` 从数字换成 5 档字符串 | 真问题不是精度表示法，是 compiler 不读它（G3）。换表示法收益接近零 |
| 删掉中英双份风格 DNA | `style_dna_en` 是唯一进提示词的 DNA 字段（垫图 style-ref），删了就真丢了 |
| 把三个板块原样拼成最终提示词 | 现在的 `text2img` 不是那么拼的，也不该是。板块是给人看的视图，提示词由 compiler 从字段生成 |

---

## 顺带记一条设计边界

现在这套架构是**刻意为迁移设计的**：`content` 是隔离区、L1 强制风格块不含内容词、
`visual_flow` 明确注释"刻意不编译"。它做不了复刻，这不是 bug。

要做「我的文案 + 这张图的样子」，缺的既不是风格也不是内容，是**容器**（G5 的 `layout` 块）。
它可以点名位置而不点名文字（"左下角竖排两列，字号为标题的 40%" 不含任何原图文案），
所以能在不破坏内容隔离原则的前提下把复制度提上去。这是唯一两头都不得罪的做法。
