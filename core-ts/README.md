# core-ts —— Track B 工装

规则的**参考实现**和验证场。规则永远先在这里改、跑通真图验证，再移植进 `../app/` 的 Swift 版；
App 不 ship 未经验证的规则。两侧共用同一批 golden fixture 和同一份 `../schema/`。

```
Claude Code / Codex 看图  →  StyleSpec JSON  →  i2p compile  →  各模型提示词
     （Read 工具，零 API）      （可存储/检索/复用）    （确定性代码 + lint）
```

`analyze` 刻意**没有**被实现成程序。Claude Code 的 `Read` 已经是最好的视觉引擎，
零 API、零配置、零成本。本包只负责把方法论编成一份会产出合法 StyleSpec 的指令
（`i2p analyze-prompt`），以及之后的全部确定性工作。

`StyleSpec` 同时是图库的原子单位：每张图分析一次、存一份 JSON，检索、收藏、
组合参考都建立在它上面。

## 用法

```bash
npm install
```

```bash
# 1. 生成分析指令，贴给 Claude Code / Codex 执行（它会 Read 图片并写出 StyleSpec JSON）
npx tsx src/cli.ts analyze-prompt <图片路径>

# 2. 校验与检查
npx tsx src/cli.ts validate specs/xxx.stylespec.json
npx tsx src/cli.ts lint     specs/xxx.stylespec.json

# 3. 写一份 Brief（本次要生成什么），编译成提示词
npx tsx src/cli.ts compile -s specs/xxx.stylespec.json -b briefs/yyy.brief.json
npx tsx src/cli.ts compile -s ... -b ... -m jimeng      # 只要国产模型版

# 4. 调参盘：在 spec 上做受控偏移，产出变体 + 改动清单
npx tsx src/cli.ts drift specs/xxx.stylespec.json --form 1 --intensity 2

# 5. 风格迁移测试：把风格套到三个不相关主体上，验证没带出原图内容
npx tsx src/cli.ts transfer-test specs/xxx.stylespec.json
```

`npm run i2p -- <子命令>` 是同一件事的简写。`palette` 从像素里算色板——
hex 和占比由程序算，不靠模型用眼睛估。

## 六条 lint 规则

每一条都来自 skill 三轮真实测试踩出来的坑，规则源标在代码注释里。

| ID | 规则 | 级别 |
|---|---|---|
| L1 | `style_dna` 不得包含 `content` 里的任何词条 | error |
| L2 | 形态词冲突：几何阵营与有机阵营的词混用 | warn |
| L3 | 垫图编辑指令必须四部件齐全（范围锚点 / 保护清单 / 枚举替换 / 禁增禁删） | error |
| L4 | 即梦版不得出现否定式表述 | warn |
| L5 | 画质词 ≤ 2 个 | warn |
| L6 | 原图品牌名不得出现在编译产物里 | error |

L3 检查的是结构化槽位而非关键词——部件缺失、或替换目标里出现「所有/全部」这类
扫射性量词，在 `compile()` 里就抛 `CompileError`，不会产出一条已知会溢出的指令。

## 已知的 v0.1 局限

- **`shot` / `angle` / `lighting` 对纯平面设计不适用。** 目前填最接近的枚举值并标进
  `confidence.uncertain_fields`；编译时靠 `FLAT_MEDIA` 白名单抑制光影描述。
  v0.2 应允许 `not_applicable`。
- **自由文本字段仍可能泄漏原图内容。** `composition.grid`、`form_language.gap_rule`、
  `material.surfaces[].where`、`mood` 会被编进提示词，写成「主图形与底部大字之间」
  这类描述就会把原图元素带走。L1 查不到（它只比对 `content.keywords`），
  `transfer-test` 能兜住一部分。`visual_flow` 和各种 `note` 已明确不参与编译。
- **模型适配器只有两个**（即梦系 / GPT Image 2），且未按模型版本分文件。

## 评测集

`evals/fixtures/` 存人工审定的 golden StyleSpec，**不存图片**——`source.path` 指向原图，
原图全程只读、不复制、不移动。

自动断言（`npm test`，68 passed）：schema 校验、lint 无 error、编译产物快照、
风格迁移测试、drift 的锚点性质与输出自洽性、以及一批故意构造的违规输入
（内容泄漏、量词扫射、保护清单缺失、品牌外泄）。

其中 43 个是**两份实现的共同契约**：期望字符串逐字相同，Swift 侧的
`CompilerParityTests` 必须给出一模一样的结果。

人工评测记在 `evals/manual-log.md`：把编译出的提示词贴到即梦 / GPT Image 网页，
人工判断风格像不像、有没有带出原图内容。这部分不进 CI。
