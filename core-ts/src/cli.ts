#!/usr/bin/env node
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { Command } from 'commander';
import { buildAnalyzePrompt } from './analyze/prompt.js';
import { extractPalette } from './analyze/palette.js';
import { compile, compileAll, CompileError, MODEL_IDS } from './compile/index.js';
import { drift, type DriftKnobs } from './drift/index.js';
import { hasError, lintPrompt, lintSpec, type Finding } from './lint/rules.js';
import { runTransferTest } from './eval/transferTest.js';
import { readBrief, readStyleSpec, validateBrief, validateStyleSpec } from './validate.js';
import type { CompiledPrompt, ModelId } from './types.js';

const C = {
  dim: (s: string) => `\x1b[2m${s}\x1b[0m`,
  bold: (s: string) => `\x1b[1m${s}\x1b[0m`,
  red: (s: string) => `\x1b[31m${s}\x1b[0m`,
  yellow: (s: string) => `\x1b[33m${s}\x1b[0m`,
  green: (s: string) => `\x1b[32m${s}\x1b[0m`,
  cyan: (s: string) => `\x1b[36m${s}\x1b[0m`,
};

function printFindings(findings: Finding[]): void {
  if (!findings.length) {
    console.log(C.green('  ✓ 无问题'));
    return;
  }
  for (const f of findings) {
    const tag = f.level === 'error' ? C.red(`  ✗ ${f.rule}`) : C.yellow(`  ! ${f.rule}`);
    console.log(`${tag} ${C.dim(f.where)}  ${f.message}`);
  }
}

function printPrompt(p: CompiledPrompt): void {
  const label = p.model === 'jimeng' ? '即梦 / 豆包 / 可灵' : 'GPT Image 2';
  console.log(`\n${C.bold(C.cyan(`━━ ${label} ━━`))}  ${C.dim(`画幅 ${p.aspect_ratio}`)}`);

  if (p.text2img) {
    console.log(`\n${C.bold('文生图')}\n`);
    console.log(p.text2img);
  }
  if (p.img2img_style_ref) {
    console.log(`\n${C.bold('垫图 · 风格参考')}\n`);
    console.log(p.img2img_style_ref);
  }
  if (p.img2img_edit) {
    console.log(`\n${C.bold('垫图 · 局部编辑')} ${C.dim('（边界控制四纪律）')}\n`);
    console.log(p.img2img_edit);
  }
  if (p.ref_protocol) {
    console.log(`\n${C.bold('参考槽协议')} ${C.dim('（明确从哪张图参考什么，避免多图互相污染）')}\n`);
    console.log(p.ref_protocol);
  }
  if (p.notes.length) {
    console.log(`\n${C.bold('使用提示')}`);
    for (const n of p.notes) console.log(`  · ${n}`);
  }
}

const program = new Command();
program
  .name('i2p')
  .description('得意忘形 core-ts：StyleSpec v0.1 + 提示词编译器（Track B 工装）')
  .version('0.1.0');

program
  .command('analyze-prompt')
  .description('生成分析指令，交给 Claude Code / Codex 执行 Read 并产出 StyleSpec JSON')
  .argument('<image>', '图片路径')
  .option('-o, --out <path>', 'StyleSpec 输出路径')
  .action((image: string, opts: { out?: string }) => {
    const abs = resolve(image);
    if (!existsSync(abs)) {
      console.error(C.red(`图片不存在：${abs}`));
      process.exit(1);
    }
    console.log(buildAnalyzePrompt(abs, opts.out ? resolve(opts.out) : undefined));
  });

program
  .command('palette')
  .description('从图片像素里算色板（hex 和占比由程序算，不靠模型用眼睛估）')
  .argument('<image>', '图片路径')
  .option('-n, --max <n>', '最多返回几个色', (v) => parseInt(v, 10), 5)
  .option('--json', '输出 JSON')
  .action((image: string, opts: { max: number; json?: boolean }) => {
    const abs = resolve(image);
    if (!existsSync(abs)) {
      console.error(C.red(`图片不存在：${abs}`));
      process.exit(1);
    }
    const palette = extractPalette(abs, { max: opts.max });
    if (opts.json) {
      console.log(JSON.stringify(palette, null, 2));
      return;
    }
    for (const p of palette) {
      const [r, g, b] = [1, 3, 5].map((i) => parseInt(p.hex.slice(i, i + 2), 16));
      const swatch = `\x1b[48;2;${r};${g};${b}m      \x1b[0m`;
      console.log(`  ${swatch}  ${p.hex}  ${String(Math.round(p.ratio * 100)).padStart(3)}%  ${C.dim(p.role)}`);
    }
  });

program
  .command('validate')
  .description('按 JSON Schema 校验 StyleSpec 或 Brief')
  .argument('<file>', 'JSON 文件路径')
  .option('-t, --type <type>', 'stylespec | brief（默认按内容自动判断）')
  .action((file: string, opts: { type?: string }) => {
    const raw = JSON.parse(readFileSync(resolve(file), 'utf8'));
    const type = opts.type ?? (('style_dna' in raw) ? 'stylespec' : 'brief');
    const r = type === 'stylespec' ? validateStyleSpec(raw) : validateBrief(raw);
    if (r.ok) {
      console.log(C.green(`✓ ${type} 校验通过`));
      return;
    }
    console.error(C.red(`✗ ${type} 校验失败：`));
    for (const e of r.errors) console.error(`  ${e}`);
    process.exit(1);
  });

program
  .command('lint')
  .description('对 StyleSpec 跑 L1 内容泄漏 / L2 形态词冲突')
  .argument('<spec>', 'StyleSpec JSON 路径')
  .action((specPath: string) => {
    const spec = readStyleSpec(resolve(specPath));
    const findings = lintSpec(spec);
    console.log(C.bold('StyleSpec 检查'));
    printFindings(findings);
    if (hasError(findings)) process.exit(1);
  });

program
  .command('compile')
  .description('StyleSpec + Brief → 模型专用提示词')
  .requiredOption('-s, --spec <path>', 'StyleSpec JSON')
  .requiredOption('-b, --brief <path>', 'Brief JSON')
  .option('-m, --model <model>', `目标模型：${MODEL_IDS.join(' | ')}（留空则全部）`)
  .option('--json', '输出 JSON 而非可读文本')
  .action((opts: { spec: string; brief: string; model?: string; json?: boolean }) => {
    const spec = readStyleSpec(resolve(opts.spec));
    const brief = readBrief(resolve(opts.brief));

    if (opts.model && !MODEL_IDS.includes(opts.model as ModelId)) {
      console.error(C.red(`未知模型 "${opts.model}"。可用：${MODEL_IDS.join(' / ')}`));
      process.exit(1);
    }

    const prompts = opts.model
      ? [compile(spec, brief, opts.model as ModelId)]
      : compileAll(spec, brief);

    if (opts.json) {
      console.log(JSON.stringify({ style_dna: spec.style_dna, prompts }, null, 2));
      return;
    }

    console.log(`${C.bold('风格 DNA')} ${C.dim('（与内容无关，可套任何主体）')}\n`);
    console.log(spec.style_dna);
    if (spec.style_dna_en) console.log(`\n${C.dim(spec.style_dna_en)}`);

    const all: Finding[] = [...lintSpec(spec)];
    for (const p of prompts) {
      printPrompt(p);
      all.push(...lintPrompt(spec, brief, p));
    }

    console.log(`\n${C.bold('检查')}`);
    printFindings(all);
    if (hasError(all)) process.exit(1);
  });

program
  .command('drift')
  .description('调参盘：在 StyleSpec 上做受控偏移，产出变体 spec + 改动清单')
  .argument('<spec>', 'StyleSpec JSON 路径')
  .option('--form <n>', '形态轴 -1(有机流动) .. +1(几何硬朗)', parseFloat)
  .option('--density <n>', '密度轴 -1(疏) .. +1(密)', parseFloat)
  .option('--temperature <n>', '色温轴 -1(冷) .. +1(暖)', parseFloat)
  .option('--brightness <n>', '调性轴 -1(暗调) .. +1(亮调)', parseFloat)
  .option('--saturation <n>', '饱和度轴 -1(降) .. +1(升)', parseFloat)
  .option('-i, --intensity <n>', '强度环 0(忠实复刻) .. 3(大幅偏移)', (v) => parseInt(v, 10), 1)
  .option('-o, --out <path>', '偏移后的 StyleSpec 写到此路径')
  .action((specPath: string, opts: Record<string, number | string | undefined>) => {
    const spec = readStyleSpec(resolve(specPath));
    const knobs: DriftKnobs = {
      form: opts.form as number | undefined,
      density: opts.density as number | undefined,
      temperature: opts.temperature as number | undefined,
      brightness: opts.brightness as number | undefined,
      saturation: opts.saturation as number | undefined,
      intensity: opts.intensity as DriftKnobs['intensity'],
    };
    const { spec: next, diff } = drift(spec, knobs);

    console.log(C.bold('偏移结果'));
    if (!diff.changed) {
      console.log(C.dim('  没有任何字段变化。强度环为 0，或所有旋钮都在中心，或已经撞到轴端点。'));
    }
    for (const c of diff.changes) {
      console.log(`  ${C.cyan(c.field)}  ${C.dim(c.from)} → ${C.bold(c.to)}`);
    }
    if (diff.palette.length) {
      console.log(`\n${C.bold('色板')}`);
      for (const p of diff.palette) {
        console.log(`  ${C.dim(p.role.padEnd(9))} ${p.from} → ${C.bold(p.to)}`);
      }
    }
    if (diff.stale.length) {
      console.log(`\n${C.bold('建议重写')} ${C.dim('（偏移算不了的自由文本，交给模型按上面的改动重写，纯文本调用不用再看图）')}`);
      for (const s of diff.stale) console.log(`  ${C.yellow('!')} ${s}`);
    }
    if (diff.notes.length) {
      console.log(`\n${C.bold('说明')}`);
      for (const n of diff.notes) console.log(`  · ${n}`);
    }

    console.log(`\n${C.bold('偏移后的风格 DNA')}\n`);
    console.log(next.style_dna);

    // drift 的输出必须能过 lint，否则说明轴的联动规则写错了
    console.log(`\n${C.bold('检查')} ${C.dim('（偏移后的 spec 必须仍然自洽）')}`);
    const findings = lintSpec(next);
    printFindings(findings);

    if (opts.out) {
      writeFileSync(resolve(opts.out as string), `${JSON.stringify(next, null, 2)}\n`, 'utf8');
      console.log(C.green(`\n✓ 已写入 ${opts.out}`));
    }
    if (hasError(findings)) process.exit(1);
  });

program
  .command('transfer-test')
  .description('风格迁移测试：把风格套到三个不相关主体上，验证没有带出原图内容')
  .argument('<spec>', 'StyleSpec JSON 路径')
  .action((specPath: string) => {
    const spec = readStyleSpec(resolve(specPath));
    const r = runTransferTest(spec);

    console.log(C.bold('风格迁移测试'));
    console.log(C.dim(`  主体：${['一只陶瓷咖啡杯', '一栋现代混凝土建筑', '一位时尚人物半身像'].join(' / ')}`));

    if (r.dnaFindings.length) {
      console.log(`\n${C.bold('style_dna 泄漏')}`);
      printFindings(r.dnaFindings);
    }
    if (r.compiledLeaks.length) {
      console.log(`\n${C.bold('编译产物泄漏')} ${C.dim('（多半来自 spec 的自由文本字段）')}`);
      for (const l of r.compiledLeaks) {
        console.log(`  ${C.red('✗')} ${l.model}.${l.field} 套用「${l.subject}」时仍出现「${l.term}」`);
      }
    }
    if (r.passed) {
      console.log(C.green('\n  ✓ 通过：换任何主体都没有带出原图内容，风格确实被抽出来了'));
      return;
    }
    process.exit(1);
  });

try {
  program.parse();
} catch (err) {
  if (err instanceof CompileError) {
    console.error(C.red(`✗ 编译期失败 [${err.rule}]`));
    console.error(`  ${err.message}`);
    process.exit(1);
  }
  console.error(C.red(err instanceof Error ? err.message : String(err)));
  process.exit(1);
}
