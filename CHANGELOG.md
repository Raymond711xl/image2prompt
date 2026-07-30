# 更新日志

记录每次值得记的改动，以及**为什么**改——决定往往比改动本身更值得回头看。

尚未发布任何版本。唯一带 tag 的是前身 skill 的 [`v1.0.0`](https://github.com/Raymond711xl/image2prompt/tree/v1.0.0)。
App 的版本号会在 A1 验收通过后才开始走。

---

## 未发布

### 2026-07-30 · 分析层纠偏

**修复**

- **L1 内容泄漏检查扩到所有会被编译的自由文本字段**：`mood[]`、`composition.grid`、
  `typography.safe_area`、`form_language.gap_rule/repetition`、`lighting.sources[]`、
  `material.surfaces[].where/detail`。判定标准只有一条——编译器真的读了它。

  起因是一轮盲测误撞出的病灶：旧 L1 只查 `style_dna`，而 `style_dna` 压根不进 text2img
  提示词（只有 `style_dna_en` 出现在垫图风格参考句尾）。真正被逐字编进正向提示词的是
  `mood` 和 `composition.grid`——一张动态摄影海报把「文人书卷气」写进 `mood`，
  生成结果满屏是书，旧规则一条都查不出来。

  `visual_flow`、各种 `note`、`notes` 仍然放行：它们刻意不参与编译，是给人看的分析记录。

- **窗口恢复尺寸不再卡在过窄的旧值**。`setFrameAutosaveName` 还原的 frame 不受 `minSize`
  校正，存过一次过窄的尺寸之后，每次打开都是那个窄窗口。

- 两个 coverage 脚本里写死的 `pictext` 绝对路径改成相对路径（目录合并后原路径已不存在）。

**变更**

- **分析指令两份同步收紧**（`core-ts/src/analyze/prompt.ts` 与 App 内的 `analyze-prompt.md`）：
  主体边界分不清时 `subject_position` 填 `none`，而不是编一个「占画面 70%」；
  网格必须声明是否可见，否则生图模型会把「三栏网格」当图形画出三条竖线；
  `mood` 只写气质不写名物性联想词（模型会把「书卷气」实体化成书本）；
  运动与排版方向在 v0.1 schema 里没有对应字段，给了临时落点，不硬塞进 `material`。

- **首次启动自动检测本机装了哪个 agent**，装了就直接用。Mock 是兜底，不该是大多数人
  第一次打开时看到的东西。之后用户显式选了什么就是什么，包括显式选回 Mock。

**新增**

- **主窗口顶部的引擎横幅**：当前引擎不会真的分析时直接挑明。Mock 的结果页和真实分析
  长得一模一样，不在主流程里说清楚，用户会把预置样本当成自己那张图的结果，
  还因为「跑得特别快」反而觉得工具好用。

- [`docs/analysis-gaps.md`](docs/analysis-gaps.md)：8 条挂账缺口，每条写了证据、触发条件、
  改动面，以及 4 条明确不做的建议和理由。附拖影轴的实测数据——原图只偏离水平 10 度，
  报告里那句「斜向」是转述出来的新错误。

  **这份文档的状态是「刻意不改」**：链路还没跑完就动 schema 是拿猜测下注，
  空改的风险不是白做工，是把猜测焊进 schema。只落地了两条零 schema 变更的修复。

- A1 验收标准加一个维度：**还原度**。原来只有「提示词直接可用」，没有「照它生成出来像不像」。

### 2026-07-29 · 定名与仓库整理

**变更**

- **定名「得意忘形 / Formless」**，bundle id 改为 `com.raymond711xl.formless`，
  Swift 模块从 `Image2Prompt*` 改为 `Formless*`。

  改名不是纯文本替换：bundle id 同时是 Application Support 下的数据目录名和 Keychain 的
  service 名，直接改会让已存的 `library.sqlite` 静默失联——App 照常启动，库是空的。
  因此加了一次性迁移（`.sqlite` / `-wal` / `-shm` 三个文件一起搬，只搬主文件会丢掉
  未 checkpoint 的写入），Keychain 读不到就回退老 service。三处名字收进 `AppIdentity.swift`
  单点定义，并有测试真的去读 `bundle.sh` 校验两边一致——这两份对不上不会编译报错，
  只会让数据消失。

- **仓库从 skill 切换为 App 本体**：`main` 现在是 App，前身 skill 完整保留在
  [`skill` 分支](https://github.com/Raymond711xl/image2prompt/tree/skill)和 `v1.0.0` tag。
  两者指向同一个 commit，它也在 `main` 的历史里——是快进不是覆盖。

- 打包脚本只收本包的资源 bundle（`${EXECUTABLE}_*.bundle`）。原来用 `*.bundle` 通配，
  改名后 `.build` 里残留的旧资源包会被一起塞进 `.app`：幽灵资源不报错，只是多一份过期数据。

**新增**

- **中英双版 README**：[`README.md`](README.md) 与 [`README.en.md`](README.en.md)，两份独立。
- [`core-ts/README.md`](core-ts/README.md)：六条 lint 规则、v0.1 已知局限、评测集说明。

### 2026-07-29 · A1 主链路

拖入 → 待办队列 → 后台反推 → 双版本提示词，整条链路跑通（验收未过，见 README 的阶段表）。

- **`LocalAgentProvider`**：调本机已装的 `claude` / `codex` CLI 识图，用你已经付过的订阅额度。
  识图是全库几千张里最贵的一环，生图只是零头——把贵的那半边成本降到零。
  实测单张完整分析约 2 分 30 秒。
- 编译层从 TypeScript 移植进 Swift，43 个用例作为两侧的共同契约，期望字符串逐字相同。
- SQLite 本地库：队列、StyleSpec、Brief 关掉再开还在。**原图全程只读**，库里只存路径。
- 菜单栏图标本身是投放目标；主菜单快捷键、导入文件夹、Release 打包安装到 `/Applications`。
- 窗口尺寸按屏幕比例给，并记住用户的调整。

### 2026-07-29 · A0 仓库改造

skill 仓库改造成 App 项目：`schema/` 和 `knowledge/` 提到仓库根（两条轨道共用，
复制两份必然漂移），TS 内核迁进 `core-ts/`，SwiftPM 工程就位。

三处原方案在动手时被证伪，如实记在 [`docs/A0-改造方案.md`](docs/A0-改造方案.md)：
`git checkout` 会打断软链所以改用 worktree、Swift target 必须拆成库 + 可执行两个、
XCTest 随 Xcode 走所以统一用 swift-testing（这决定了不装 Xcode 也能开发）。

---

## v1.0.0 — 2026-07-12 · image2prompt skill

前身：一个在 Claude Code 和 Codex 里跑的参考图反推提示词 skill。
三轮真实测试沉淀下来的东西（形态词避坑、先问再开方、编辑边界四纪律）没有丢，
它们变成了 `schema/` 的字段设计、`core-ts/src/lint/` 的检查规则和 `knowledge/` 的知识库。

完整内容仍可在 [`v1.0.0`](https://github.com/Raymond711xl/image2prompt/tree/v1.0.0) 下浏览、
下载、照旧安装。
