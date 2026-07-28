# Image to Prompt

macOS 菜单栏工具：**拖一张图进来 → 理解它的风格 → 调参偏移 → 产出可直接用的生图提示词**。

> 名字是占位的，未定。

## 它和"垫图"的区别

垫图把像素直接喂给生图模型，得到的是复制品，而且**没有旋钮**——你没法对一张垫图说"色相转 20 度、密度降一档"。

本工具先把风格解析成结构化的 `StyleSpec`，再在字段上做受控变换，所以每次偏移都能说清改了哪几个字段。

> 随机重跑得到的是噪声，受控偏移得到的是变体。

垫图没有被废弃，但降级为保底修复路线：文生图两轮都不像时才上。

## 当前状态

**A0 已完成**：仓库结构就位，SwiftPM 能编出可运行的空壳菜单栏 App。

**A1 下一步**：拖入 → 待办队列 → 后台反推 → 出提示词。

完整路线见 [`docs/roadmap.md`](docs/roadmap.md)。

## 目录结构

```
├── schema/          StyleSpec / Brief 的单一事实来源，core-ts 和 app 共用
├── knowledge/       方法论原文：设计风格库、模型规范、修图模板
├── core-ts/         TypeScript 参考实现 + 验证工装（Track B）
├── app/             Swift App（Track A）
├── docs/            路线图、StyleSpec 说明、改造方案
└── SKILL.md         过渡期保留，A1 跑通后删除
```

`schema/` 和 `knowledge/` 刻意放在仓库根：两条轨道都要读它们，复制两份必然漂移。

## 开发

需要 Swift 6.1+（Command Line Tools 即可，**不需要 Xcode**）和 Node 20+。

```bash
# Swift App
cd app
swift build
swift test                  # 用 swift-testing，不依赖 Xcode
./Scripts/bundle.sh         # 打成 .app，菜单栏出现图标
open ".build/debug/Image to Prompt.app"
```

```bash
# TypeScript 内核
cd core-ts
npm install
npm test                    # 43 passed
npx tsx src/cli.ts --help
```

Xcode 只在两种情况下需要：SwiftUI 实时预览、公证后分发给别人。

## 分支

```
main   ← v1.0.0 skill 原样保留，两个软链继续工作
  └── app   ← App 开发全部在这里（用 git worktree，不是 checkout）
```

`~/.claude/skills/image2prompt` 和 `~/.codex/skills/image2prompt` 都软链到仓库工作目录，
`git checkout` 会当场换掉它们看到的文件。所以 app 分支用独立 worktree：

```bash
git worktree add ../image2prompt-app app
```

A1 跑通后才合并回 `main` 并删除 `SKILL.md`。

## 由来

本仓库前身是 [`image2prompt`](https://github.com/Raymond711xl/image2prompt) skill——一个在 Claude Code
和 Codex 里跑的参考图反推提示词工具。三轮真实测试沉淀下来的东西（形态词避坑、先问再开方、
编辑边界四纪律）没有丢，它们变成了 `schema/` 里的字段设计、`core-ts/src/lint/` 里的检查规则，
和 `knowledge/` 里的知识库。

## License

MIT
