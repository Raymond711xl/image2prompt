# 更新日志

记录每次值得记的改动，以及**为什么**改——决定往往比改动本身更值得回头看。

尚未发布任何版本。唯一带 tag 的是前身 skill 的 [`v1.0.0`](https://github.com/Raymond711xl/image2prompt/tree/v1.0.0)。
App 的版本号会在 A1 验收通过后才开始走。

---

## 未发布

### 2026-07-31 · StyleSpec 0.2

**变更**

- **StyleSpec 从 0.1 升到 0.2**，新增 [`schema/stylespec.v0.2.json`](schema/stylespec.v0.2.json)
  （v0.1 保留不删，已存数据不会被静默当成新版本误读）。依据是 28 张 Image2 复现回归测试的
  真实证据——每张都过了 StyleSpec → 生成 → 对比 → 人工反馈的全链路，不是凭空扩字段。
  定案范围和取舍见 [`docs/stylespec-v0.2-scope.md`](docs/stylespec-v0.2-scope.md)。

  六个改造点，只挑了证据里高频、高杀伤力的那几条，其余明确挂账（文档里写了触发条件）：

  - **精确画幅**：`source.width/height/aspect_exact` 直接读文件，不再让分析模型猜
    "3:4" 这种四舍五入的类别值。
  - **文字版式**（全表最高频问题，19/28 张图栽在这上面）：每段 `on_image_text` 加
    `region/layer/ocr_status/line_breaks/color/relative_size/distortion/typeface_note`，
    `typography` 加 `implicit_alignment`。专治"手写花体签名文字"这种认不出的字被当正文
    照抄进提示词的 bug——`ocr_status=unclear` 的文字编译时不得再作为 literal text。
  - **载体判断**：`content.carrier_type`，置信度低就留 `candidates`，不擅自锁死成一种
    （之前"书籍推荐"这类图会被误判成完整立体商品样机）。
  - **面板结构**：`composition.panel_count/panels`，作品页截图、杂志跨页这类多面板图
    不再被编译时拍扁成一张连续场景。
  - **禁止脑补**：`content.visible_only/external_expansion_risk`，专治品牌/IP 名字
    触发生成模型自己的常识联想、画出画面之外内容的问题。
  - **前后遮挡关系（基础版）**：`composition.element_stacking`，只给相对顺序不给坐标，
    先解决"东西被合并/穿模"这一层。

- **两侧代码同步实施，不是只停在文档**：core-ts 的 `analyze/prompt.ts`、
  `compile/shared.ts`（新增 `panelText`/`stackingText`）+ 两个 adapter、`lint/rules.ts`
  （新增 L7 结构一致性检查）、`validate.ts`；Swift 侧 `StyleSpec.swift` decode 模型、
  `CompileShared.swift` + 两个 Adapter、`DetailView.swift` 新增"内容与文字"卡片、
  `BuildInfo.swift` 版本号。两侧 fixture 与 golden 文件同步更新。
  core-ts 71 个测试、Swift 77 个测试全部通过。

**修复**

- lint L1 内容泄漏检查漏了 `composition.element_stacking` 和 `panels[].role`——这两个
  字段会被编进提示词，第一版随手写成"中央像素马图形"这种点名原图内容的写法，被跨主体
  测试（transfer-test）当场抓到泄漏。已修：两个字段补进 L1 检查表，两侧分析指令也加了
  "必须写成换主体也成立的抽象角色"的规则和反例。

### 2026-07-31 · 菜单栏菜单在带刘海的屏上错位

**修复**

- **菜单不再自己算弹出位置，交回系统**。之前手算锚点（按钮底边下方 5pt），在外接屏正常，
  在内建屏上会错位、顶部还长出一个 `^` 滚动箭头，得再移一次才能看到第一项。

  量出来的原因：**按钮高度恒为 22pt，不随刘海变**，但内建屏菜单栏高 38pt
  （`safeAreaInsets.top` = 32），外接屏只有 25pt。那个距按钮顶端 27pt 的锚点，
  在外接屏上已经出了菜单栏，在内建屏上还埋在里面；AppKit 不让菜单压住菜单栏，
  只好把它挪位并裁短——滚动箭头就是被裁短的证据。把 5 调大只是换一块屏出错。

  改成弹出时临时把菜单挂到 `statusItem` 上再 `performClick`，位置、屏幕边界、刘海、
  按钮高亮全归系统管。平时仍不挂 `statusItem.menu`——拖放层盖在按钮上，
  点击本来就到不了按钮。

### 2026-07-31 · 菜单栏图标改为自绘

**变更**

- **菜单栏不再借用系统的 SF Symbol，改为自绘的矢量图标**（`MenuBarIcon.swift`）：
  斜置的魔法棒 + 左上右下两颗四角星，和主图标共用同一套构图。

  画法是手写路径不是位图：菜单栏图标要在 @1x/@2x 之间来回切（拖到外接屏就会发生），
  位图缩放必糊；模板图又要求纯黑 + alpha，位图资源多一道"导出时带了灰底"的坑。

  中途绕过一段路，记下来免得再走：先把魔杖换成了棱镜分光（"一束光进去、几条色带出来"
  确实对应 `图 → StyleSpec`），但那就是平克·弗洛伊德那张封面，等于把一个 cliché
  换成另一个。回到魔法棒，只是自己画。

- **忙碌态从换符号（`wand.and.stars.inverse`）改为棒尖多冒一颗星**。轮廓不变才不会让人
  以为换了个 App。另外三种都在 16px 上死了：棒身改空心 → 变成一条虚线；星星换实心圆点
  → 整个图标读成一只哑铃；只把星放大一档 → 看不出差别。

  几何全是渲成真实像素挑的，不是照着大图想当然。同理废掉的还有：水平色带像"文字行"图标、
  一点发散的扇形收拢端糊成 `≤`、四角星腰收到 0.16 时右下那颗在 16px 直接消失。

**新增**

- **App 有图标了**，和菜单栏共用一套构图：暖米白底、石墨黑魔法棒、左上朱砂四角星、
  右下同款黑色小星，带一层极细的印刷颗粒。`Resources/AppIcon-source.png` 是生图原件，
  `Scripts/make-icon.swift` 负责把它做成 `AppIcon.icns`，换图重跑脚本即可。

  脚本干的两件事都不能省。**一是抠四角**：生图模型画的圆角是画上去的，角上那块是不透明的
  白，直接进 icns 就是四个白角。**二是缩到 824/1024**：macOS 图标网格四周留 100px，
  全出血的图标在访达里比旁边的系统图标明显大一圈。

  圆角用超椭圆 `|x/a|ⁿ + |y/b|ⁿ = 1`（n=5）而不是正圆弧——正圆弧在角上会留一处折点。
  参数不是查来的，是拿 Notes / Reminders / Calendar 的 alpha 边界反推的：本体 824×824、
  n≈4.93，三个一模一样。生成后按同一套量法验过，数值对得上。

- `bundle.sh` 补上 `CFBundleIconFile` 和 `.icns` 的拷贝；install 分支加了一次 `touch`——
  访达缓存图标，同路径换了 bundle 也照旧显示旧的，改一次修改时间才会重读。

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
