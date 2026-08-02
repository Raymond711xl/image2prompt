# 更新日志

记录每次值得记的改动，以及**为什么**改——决定往往比改动本身更值得回头看。

尚未发布任何版本。唯一带 tag 的是前身 skill 的 [`v1.0.0`](https://github.com/Raymond711xl/image2prompt/tree/v1.0.0)。
App 的版本号会在 A1 验收通过后才开始走。

---

## 未发布

### 2026-08-02 · 闭环生图跑通，Brief 改由 AI 读，长任务有了声音和进度

**新增**

- **闭环生图：`codex exec` + 内置 `image_gen`**。推翻了 roadmap 里"agent 不能生图"那条硬限制
  ——Codex CLI 0.144.1 起 `image_generation` 为 stable，自带 `~/.codex/skills/.system/imagegen`，
  **内置工具走 Codex 登录额度，不需要 `OPENAI_API_KEY`**。识图和生图两头都能压进订阅成本内，
  这是"提示词 → 图 → 对比原图"这条验证链能不能天天跑的前提。实测结论见
  [`docs/codex-imagegen.md`](docs/codex-imagegen.md)。

  三条实现上的硬规矩，每条都是被实测逼出来的：

  - **产物落在本次任务的唯一目录**，不去猜"`~/.codex/generated_images` 里最新的那张"。
    Codex 按 session 分子目录，并发跑两张就会互相认错图。
  - **尺寸自己用 ImageIO 量，不采信 agent 自述**。冒烟测试里 agent 报的 size 是它事后
    用 ffmpeg 拉伸的结果——要 3:4 拿到 1024×1536，它非等比拉成 1200×1600 再告诉你"好了"。
    指令里已明令禁止任何缩放裁切，但**回报的数字仍然只能以实测为准**。
  - **要求 agent 逐字回报 `final_prompt`**。生图 agent 中途会不会改写提示词，决定了这张图
    能不能用来评判编译器。改写过的图只能看个热闹，不能当证据，所以"提示词逐字一致"这个
    徽标直接显示在图旁边，而不是藏进详情。

  已知限制照实写在界面上：**内置模式控制不了精确画幅**。尺寸参数是 CLI fallback 专属
  （那条要 API key），画幅只能作为一句话写进提示词软约束，中没中以实测像素为准。

- **Brief 改由本地 agent 读**（`ModelBriefParser`）。正则解析只认「换成 X」「「引号」」「不要 Y」
  几个句式，别的全当噪声。实测一段 94 字的描述里，只有"老邮票""不要人物""不要现代元素"
  进了提示词，天安门、齿孔、怀旧、别太亮、右下角留白全部蒸发——用户觉得"解析没什么用"
  就是这么来的。

  **只让 AI 填字段，不让它直接写提示词。** 编译器里攒着的纪律（否定词转正向、画质词截断至
  2 个、垫图边界四纪律、accent 色不按面积过滤）是这个产品真正的资产，让 AI 出提示词
  等于把它们全绕过去。AI 解析失败时退回正则，并在界面上如实说明降级了。

- **完成提示音**。一张图分析 2~3 分钟、生成 3~4 分钟，没人会盯着屏幕等——声音是切走之后
  唯一能把人叫回来的通道。分析完成、生成完成、失败三个音，同一套音色的"亲戚"关系，
  不看屏幕也能分清是哪件事结束了。

  失败单独一个音是刻意的：不区分的话，跑批时失败也响"完成"音，人走开一趟回来会以为全成了。
  同一个音 0.25 秒内只响一次——并发三张同时跑完，听到的是一声，不是糊成一团的三声。
  设置里有独立开关、试听和音量。

- **长任务进度条**（侧栏 + 详情页）。**这条进度是推算的，不是测出来的**：底层是一次性子进程，
  跑完之前不吐任何百分比。所以定了两条不能破的规矩——条子封顶 92%、永远不假装完成；
  条子旁边必须同时显示真实已用时，跑超预期时条不动、数字继续涨，一眼看得出这次比平常慢。
  分析蓝条、生成紫条，共用同一块位置（一张图不会边分析边生成），行高不跳。

- **「画面文字」独立成卡**。文案是这次输入里**最确定**的东西（用户心里就是那几个字），
  不该和"主体是什么、什么调子"这种要 AI 揣摩的内容混在一个框里等解析。

- **引擎状态拆成识图 / 生图两份**，设置里也分成两页。两条路互相独立——选 Mock 识图
  照样能生图——合成一份状态会让人看不出"哪一半连上了"。

**修复**

- **生成状态从视图搬进 `GenerationQueue`**。原来跑在 `BriefSection` 的 `@State` 里，
  有两个后果：侧栏读不到（只有当前选中的那张图知道自己在跑，进度条无从画起），
  以及 SwiftUI 复用视图时状态跟着串台，切到另一张图那张也显示"生成中"。

- **取消是真的取消了**。`AgentRunner` 的 `onCancel` 里原来只有一句注释，取消只放开我们
  这边的等待：`codex` 子进程照跑、额度照烧，而队列已经以为自己空闲，下一次点生成会
  并排再起一个。现在真的杀子进程。分析那条路一直有同样的毛病，一起修了。

- **GPT Image 适配器漏了两段信息**（两侧同步，Swift + TS 一起改）：`medium_detail`
  （分析器写的具体媒介描述，比 `medium` 枚举信息量高一个数量级）整段被丢掉；
  `density` 即梦走 `compositionText` 一直带着、GPT Image 自己拼 placement 时漏了——
  这是两个适配器的不一致，不是设计取舍。golden 与快照跟着更新。

- **`GenerationStore` 的根目录可注入**。不给这个口子，任何碰生成流程的测试都会往真实的
  Application Support 里写目录。做成参数而不是全局开关——测试是并行跑的，全局可变状态
  会在用例之间互相踩。

### 2026-08-02 · 画幅改由宿主量，菜单栏改左键直开

**修复**

- **精确画幅不再委托给分析 agent**。上一版把「量像素尺寸」写进了分析指令，让 agent 自己跑
  `sips`。但 App 里的 Claude Code 预设锁了 `--allowed-tools Read`（刻意的限制，换更快更稳），
  指令要求它跑 shell、权限又不让跑，agent 会卡在这一步——拖慢分析，还可能顺带搞坏输出。

  改由宿主做：App 走 ImageIO 读图片属性（不启子进程、不要额外权限，和生成缩略图同一条路），
  core-ts 侧脚本自己跑 `sips`，量好的数字通过 `{{EXACT_DIMENSIONS}}` 占位符填进指令，
  agent 只管抄。读不出来时如实说明并要求标进 `uncertain_fields`，不允许为了填满字段编数。

  **确定性计算不该麻烦模型**——这条适用范围比画幅大得多，以后再遇到类似的先想想宿主能不能算。

- **`VisionError` 新增 `agentFailed`**。本地 agent 走子进程，超时、非零退出、找不到可执行
  文件都不是「网络请求失败」，之前一律报 `transport` 是在说假话，用户永远猜不出真实原因。
  `transport` 保留给真正的 HTTP provider。

**变更**

- **菜单栏图标左键直接开窗**，右键（或 control + 左键）才弹菜单。十次点击里九次要的是开窗，
  之前每次都得先弹菜单再选一次。菜单本身不能省——菜单栏应用没有 Dock 图标也没有主菜单栏，
  它是找到设置和退出的唯一入口。

- **详情页「内容与文字」卡片挪到风格字段之后并默认折叠**。`content` 是隔离区、换主体时整个
  丢弃，它是核对用的原始事实，不该占据第一眼的位置。折叠行没用 `DisclosureGroup`：
  那个组件只有小三角能点，整行做成按钮热区更好用。

**新增**

- **调色盘第三栏可交互原型**（`core-ts/scripts/build-pad-prototype.ts`）：把真引擎
  （drift + compile + lint）连同一份真 StyleSpec 内联进单个 HTML，拖旋钮跑的是和 CLI
  同一套代码。用假数据的原型只能验证界面好不好看，验证不了「这个轴拨出来对不对」，
  而后者才是 A2 要回答的问题。产物落在 `.prototype/`，已 gitignore。

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
