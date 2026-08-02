# 闭环生图：codex exec + 内置 image_gen

2026-08-02 冒烟测试实测结论。推翻了 [roadmap](roadmap.md) 里"agent 不能生图"那条。

## 环境事实

| 项 | 实测 |
|---|---|
| Codex CLI | `0.144.1` |
| `image_generation` feature | `stable / true` |
| 系统 skill | `~/.codex/skills/.system/imagegen/`（SKILL.md + scripts + references） |
| 内置模式是否要 `OPENAI_API_KEY` | **不要**（SKILL.md 原文：built-in tool mode "Does not require `OPENAI_API_KEY`"） |
| 图片落点 | `~/.codex/generated_images/<session-uuid>/<exec-uuid>.png`，**按 session 分子目录** |

## 跑通的命令

```bash
codex exec --ephemeral --skip-git-repo-check --sandbox workspace-write \
  -C <任务目录> \
  --output-schema <generation-result.schema.json> \
  -o <任务目录>/result.json \
  - < instruction.txt
```

指令从 stdin 进，首行 `$imagegen` 显式点名 skill。耗时约 3~4 分钟（识图约 2.5 分钟，**别复用识图的超时值**，至少给 10 分钟）。

## 四条必须写死的指令约束

imagegen SKILL.md 自带 `Prompt augmentation` 一节（"Reformat user prompts into a
structured, production-oriented spec"），还有 `When not to use` 分支会把海报/图表类
劝去用 SVG/HTML/CSS，以及一条转 `scripts/image_gen.py` 的 fallback（**那条要 API key**）。
四句都写进指令才拦得住：

1. 只使用内置 `image_gen`，只调一次
2. 不许用 SVG / HTML / CSS / canvas 代替
3. 不许切换到 CLI fallback，不许用 `OPENAI_API_KEY`
4. 提示词**逐字原样使用**，不要重写、规范化、结构化、增删

实测有效：回传的 `final_prompt` 与编译器产出**逐字相同**（456 字符，`==` 为 True）。

## result schema 必须带 `final_prompt`

这是整条链路里唯一能证明实验有效的字段——没有它，图偏了就分不清是编译器的锅
还是 Codex 改写的锅。同时要 `size` 和 `tool_used` 用来发现下面那个坑。

```json
{ "status", "image_path", "final_prompt", "size", "tool_used", "error" }
```

## 三个坑

### 1. 画幅只能写进提示词，不能当参数传（踩了两次才定位对）

**第一次（冒烟测试）**：指令里写了 `1200x1600`。实际发生的是内置 `image_gen` 生成了
**1024×1536（2:3）**，Codex 随后用 `ffmpeg scale=1200:1600:flags=neighbor` 拉成 3:4。
**非等比拉伸，画面横向被拉宽 12.5%。** 回报的 `size` 是"我事后拉成了这个"，不是"我按这个生成的"。

**第二次（改成禁止缩放 + 只提示取向）**：要 3:4，拿到 **1254×1254 方图**。

第二次才暴露出真正的机制：`gpt-image-2` 的 size 参数写在 SKILL.md 的
**"gpt-image-2 guidance for CLI fallback"** 一节——**尺寸控制是 CLI fallback 专属，
内置工具根本不暴露这个参数**。所以"画幅取向"那句话是说给 *agent* 听的，
而 agent 没有通道把它传给生图模型；我们又禁止了它事后拉伸，于是画幅信息彻底丢失。

**唯一能到达生图模型的通道是提示词本身。** 现在 `CodexImageProvider.composePrompt`
在编译器产出后面追加一句：

```
。画幅比例严格为 3:4（竖构图），整幅图按这个比例出图，不要方图、不要留白补边
```

实测有效：同一条提示词，加之前 1254×1254，加之后 **1086×1448（正好 3:4）**。

两条纪律跟着这个坑走：

- 追加只能往后加，编译器产出必须原样在前（有测试盯着 `hasPrefix`）。
- 这仍然是**软约束**，模型可能不听。所以 `Record.aspectMatches` 拿实测像素和要求的比例
  比对（5% 容差），没中的图在界面上打橙色徽标——**没中的图不能拿去量构图数据**。

尺寸一律以 ImageIO 实测为准，不采信 agent 自述。

### 2. Codex 会先吐一条假的中间 JSON

本次 stdout 里先出现过：

```json
{"status":"success","image_path":null,"final_prompt":"我将按 imagegen skill 使用内置 image_gen 单次生成…"}
```

`-o` 写的是最后一条，`result.json` 是对的。但 **App 必须读 `-o` 指定的文件，绝不解析 stdout**。

### 3. skill 描述被截断

本机 skill 装得多，Codex 报 `Skill descriptions were shortened to fit the 2% skills
context budget`。这次 `$imagegen` 显式点名生效了，但这是可靠性风险——
`tool_used` 字段就是用来发现它没生效的。

## 没有踩到的坑

- **沙盒拷贝不需要 `--add-dir`。** `workspace-write` 下从 `~/.codex/generated_images`
  读、往 `-C` 目录写，直接成功。
- `--ephemeral` 不影响图片落盘，只是不留 session 文件。
- `ERROR codex_models_manager: failed to renew cache TTL` 是噪声，不影响结果。

## App 里怎么接的

```
StyleSpec + Brief
  ↓ Compiler（既有）
CompiledPrompt.text2img
  ↓ CodexImageProvider.composePrompt（追加画幅句）
  ↓ codex exec + 内置 image_gen
result.png + result.json
  ↓ GenerationStore（目录即记录，不进 SQLite）
详情页「生成结果」卡
```

| 新增 | 位置 |
|---|---|
| `GenerationProvider` 协议 + `GenerationRequest/Result/Error` | `FormlessCore/Generation/GenerationProvider.swift` |
| `CodexImageProvider` | `FormlessCore/Generation/CodexImageProvider.swift` |
| `GenerationStore`（生成历史落盘） | `FormlessCore/Generation/GenerationStore.swift` |
| 生成按钮 + 结果卡 | `Formless/UI/BriefSection.swift` |

唯一改动的既有代码是 `AgentRunner`：多了一个通用 `run(executable:arguments:stdin:timeout:currentDirectory:)`
入口（识图那条 `AgentPreset` 路径不变），以及 `EngineStatus.canGenerate` 从写死 `false`
改成跟着 `CodexImageProvider.isAvailable` 走——**生图和识图是两条独立的路**，
选 Mock 识图照样能生图。

超时默认 900 秒（`Settings.generationTimeout`）。实测单张 107~148 秒，
但 agent 编排的波动大，别卡太紧。

实跑验证（默认跳过，要花额度）：

```bash
FORMLESS_LIVE_GEN=1 swift test --filter liveGeneration
```

## 顺带撞出的编译器问题（不是链路问题）

生成图里出现了大量我们没要的文字（`HELVETIA` / `SWISS DESIGN` / `PIXEL` / `2024`），
而 brief 是 `render_text_in_image: false`、`copy` 全空。原因在编译器：
`medium: typography_poster` 被编译成"排版海报"，`mood` 里还有"复古电子游戏感"——
模型当然要排字。这正是 B1 要收集的证据类型，记在 [analysis-gaps](analysis-gaps.md) 的 G6 名下。
