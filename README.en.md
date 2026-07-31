<img src="app/Resources/AppIcon.png" width="120" align="right" alt="Formless app icon">

# Formless · 得意忘形

[中文](README.md) · **English**

A macOS menu-bar tool: **drop in a reference image → understand its style → nudge the knobs → get prompts you can paste straight into an image model.**

## The name

The Chinese name 得意忘形 is an idiom. Literally it reads *grasp the meaning, forget the form*;
in everyday use it means *to get carried away* — to be so pleased with yourself that you lose
your composure. Both readings are intended, and there is a third.

**One — it's a warning.** This tool can make you ten times faster, and fast is not the same as
good. Taste is accumulated the hard way: how many good images you've studied, how many layouts
you've taken apart, how many times you got it wrong. There's no shortcut. A tool that hands you
a finished prompt shouldn't leave you thinking you've learned something you haven't.

**Two — it's only a tool; the form is still yours to fill in.** Nothing here makes work for you.
It takes a reference image apart into something you can read and edit. You choose the image, you
decide which direction to push it, and what comes out depends on the subject, the copy, and the
judgment you bring. The tool's job is turning *"I can't describe it but I want that feeling"*
into fields you can actually operate. The rest is yours.

**Three — forgetting the form is literally what the program does.** It drops the reference
image's **form** (what was depicted: subject, copy, brand) and keeps only its **meaning**
(how it was made: type, palette, composition, texture). That's a hard rule, not a metaphor —
if any term from `content` shows up in `style_dna`, lint fails with an error. Failing to forget
the form is called copying. Forgetting it is what makes it style.

> Grasp the meaning, forget the form.

`Formless` carries the third reading, and is the word used for the executable and the bundle ID.

## How this differs from image-to-image

Feeding pixels straight to a generative model gives you a copy — and gives you **no knobs**.
You can't tell a reference image to "rotate hue 20 degrees, drop density one notch."

This tool parses style into a structured `StyleSpec` first, then applies controlled
transformations at the field level, so every nudge can name exactly which fields changed.

> Re-rolling gives you noise. Controlled drift gives you variants.

Image-to-image isn't abandoned — it's demoted to a fallback, used only when two rounds of
text-to-image still miss.

## The idea

In one line: **separate *seeing* from *compiling*, and give each to whichever is good at it.**

```
you drop in an image
   ↓  seeing —— an agent's job (Claude Code / Codex / API)
StyleSpec JSON —— structured style, storable, searchable, reusable, editable
   ↓  compiling —— deterministic code's job (not a model improvising)
Jimeng-family prompt + GPT Image 2 prompt
```

Three judgments hold this up:

**Seeing needs a model; compiling shouldn't use one.** Only a vision model can tell you what
style something is. But translating a style description into something a specific image model
will swallow is a pile of rules with definite right answers — Jimeng can't take negations,
more than two quality adjectives make output *worse*, an edit instruction without a protection
list will quietly "harmonize" elements you never mentioned. Rules written as code can be
asserted, tested, and reused. A model improvising them each time is a coin flip.

**`StyleSpec` is an atomic unit, not an intermediate artifact.** Each image is analyzed once and
stored as one JSON file. The future library, its search, and "this one's palette with that one's
composition" are all built on it. That's why it has a schema, a linter, and tests.

**Vision cost has to go to zero.** Across a few thousand images, seeing is the expensive half;
generating is loose change. So the default path calls a local agent — the `claude` / `codex` CLI
already installed on your machine, on the subscription you already pay for. No extra API bill.

## Development stages

Two tracks, deliberately on different environments so they don't compete for resources.
The dependency runs one way: Track B's conclusions feed Track A.

| | Track A: Mac app | Track B: knob validation |
|---|---|---|
| Environment | Swift / SwiftPM | Claude Code + the `core-ts/` CLI harness |
| Output | the tool you use daily | drift rules you can trust |
| Cost | zero on a local agent | subscription only, no extra spend |

**Rules always change in `core-ts/` first, get validated against real images, and only then get
ported to Swift.** The app doesn't ship unvalidated rules.

| Stage | Scope | Status |
|---|---|---|
| **A0** | Convert the repo from a skill into an app project; SwiftPM skeleton | ✅ done |
| **A1** | Drop → queue → background analysis → prompts in both dialects | pipeline works, acceptance not yet passed |
| **A2** | Knob panel (form/density and temperature/key axes + intensity ring) | waiting on B1 |
| **A3** | Generation output | not yet designed |
| **B0** | Drift engine: axis movement, color math, field diff | ✅ done (547 lines, 25 tests) |
| **B1–B3** | 30 → 100 → 1000 real images, validating that drift is meaningful | not started |

Measured during A1: one full analysis takes about **2 min 30 s** on a local agent, schema
validation passed on the first try, and lint caught two content leaks (the analysis prompt has
since been fixed). What remains is a ten-image run-through and wiring up the Anthropic API.

`StyleSpec` is now at **0.2**: after a 28-image blind-reconstruction regression against Image 2,
six field groups went into the schema on the strength of that evidence — exact canvas dimensions,
text layout (line breaks, front/back layering, color, relative size, distortion, OCR
confidence), carrier judgment, panel structure, an anti-hallucination flag, and a basic
front-to-back element order. Both codebases and their test suites are in sync. Scope and
trade-offs: [`docs/stylespec-v0.2-scope.md`](docs/stylespec-v0.2-scope.md) (in Chinese).

Full roadmap, knob-panel design, and cost estimates: [`docs/roadmap.md`](docs/roadmap.md).
Change-by-change history and the reasoning behind each: [`CHANGELOG.md`](CHANGELOG.md) (in Chinese).
The eight known gaps in the analysis layer, with evidence and trigger conditions:
[`docs/analysis-gaps.md`](docs/analysis-gaps.md) (in Chinese).

## Install and use

Requires Swift 6.1+ (Command Line Tools is enough — **Xcode is not needed**).

```bash
cd app && ./Scripts/bundle.sh release install
```

Installs to `/Applications/得意忘形.app`. Launch it and a ✨ icon appears in the menu bar.
The icon is itself a drop target — drag images onto it to enqueue them.

### Wiring up your own agent (recommended — no API spend)

Settings → vision engine:

| Option | What it does |
|---|---|
| Mock | Fake data, no network. For development and trying the flow. |
| Claude Code | Shells out to the local `claude` CLI, on your subscription |
| Codex | Shells out to the local `codex` CLI |
| Custom agent | Executable + argument template + stdin toggle; any "read instructions, emit text" CLI works |
| Anthropic API | Bring your own key (not yet wired) |

Hit "detect" to confirm the CLI can be found.

**Two limits**: an agent can see images but can't generate them, so generation still means
pasting prompts into a web UI or calling an image API; and this mode spawns subprocesses, which
is incompatible with the Mac App Store sandbox (direct distribution is unaffected).

## Layout

```
├── schema/          Single source of truth for StyleSpec / Brief, shared by core-ts and app
├── knowledge/       The methodology itself: style library, model quirks, retouching templates
├── core-ts/         TypeScript reference implementation + validation harness (Track B)
├── app/             Swift app (Track A)
├── docs/            Roadmap, StyleSpec notes, conversion plan
├── pictext/         Reference-image corpus, local only, never committed
└── SKILL.md         Kept through the transition, deleted once A1 is accepted
```

`schema/` and `knowledge/` sit at the repo root on purpose: both tracks read them, and two
copies would inevitably drift apart.

## Development

```bash
cd app && swift test          # 77 passed — swift-testing, no Xcode required
```

```bash
cd core-ts && npm install && npm test    # 71 passed
```

Xcode is needed for exactly two things: SwiftUI live previews, and notarizing for distribution.

## Branches and history

`main` is the app. The skill it grew out of is preserved in two places:

| Where | What |
|---|---|
| [`skill` branch](https://github.com/Raymond711xl/image2prompt/tree/skill) | The v1.0.0 skill, untouched — browsable, downloadable, still installable |
| [`v1.0.0` tag](https://github.com/Raymond711xl/image2prompt/tree/v1.0.0) | The same commit, with auto-generated source archives |

Both point at one commit, and that commit is in `main`'s own history — the app grew out of it
rather than replacing it.

`SKILL.md` stays on `main` for now; it gets deleted once A1 is accepted.

## Origins

This repo started as the `image2prompt` skill — a reference-image-to-prompt tool that ran inside
Claude Code and Codex.

What three rounds of real testing produced (the shape-vocabulary traps, ask-before-prescribing,
the four disciplines of edit boundaries) wasn't lost: it became the field design in `schema/`,
the lint rules in `core-ts/src/lint/`, and the knowledge base in `knowledge/`. Only `SKILL.md`
is being retired — the dispatcher, whose job of picking a mode and sequencing the work is now
the app's UI.

## License

MIT
