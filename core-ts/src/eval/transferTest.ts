import type { Brief, StyleSpec } from '../types.js';
import { compileAll } from '../compile/index.js';
import { contentTerms, lintContentLeakage, type Finding } from '../lint/rules.js';

/**
 * 三个互不相关的主体。
 * 评测一段风格 DNA 是否合格，最好的办法不是让它重画原图，而是把它套到毫不相关的主体上——
 * 如果色彩、材质、排版、密度、气质都还在，且没有带出原图内容，才证明风格真被抽出来了。
 */
export const TRANSFER_SUBJECTS: Array<{ subject: string; subject_detail: string }> = [
  { subject: '一只陶瓷咖啡杯', subject_detail: '素色无标识，杯口正对镜头略微倾斜' },
  { subject: '一栋现代混凝土建筑', subject_detail: '清水混凝土外立面，方正体量，无招牌文字' },
  { subject: '一位时尚人物半身像', subject_detail: '素色服装，面部朝向侧前方' },
];

export interface TransferResult {
  passed: boolean;
  /** style_dna 自身的内容泄漏（L1） */
  dnaFindings: Finding[];
  /** 编译产物里出现的内容词。来源多为 spec 的自由文本字段（material.where / lighting.sources / mood 等） */
  compiledLeaks: Array<{ subject: string; model: string; field: string; term: string }>;
}

const CJK = /[一-鿿]/;
function contains(haystack: string, needle: string): boolean {
  const t = needle.trim();
  if (!t) return false;
  if (CJK.test(t)) return t.length >= 2 && haystack.includes(t);
  const escaped = t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`\\b${escaped}\\b`, 'i').test(haystack);
}

/**
 * 风格迁移测试。
 *
 * 除了查 style_dna，还把 spec 套到三个不相关主体上真的编译一遍——
 * 因为泄漏也可能藏在会被编进提示词的自由文本字段里（比如 material.surfaces[].where
 * 写成「咖啡机机身」，换主体后这个词照样会跟着跑出来）。
 */
export function runTransferTest(spec: StyleSpec): TransferResult {
  const dnaFindings = lintContentLeakage(spec);
  const terms = contentTerms(spec);
  const compiledLeaks: TransferResult['compiledLeaks'] = [];

  for (const s of TRANSFER_SUBJECTS) {
    const brief: Brief = {
      schema_version: '0.1',
      purpose: 'poster',
      aspect_ratio: spec.composition.aspect_ratio,
      subject: s.subject,
      subject_detail: s.subject_detail,
    };
    for (const prompt of compileAll(spec, brief)) {
      const outputs: Array<[string, string | null]> = [
        ['text2img', prompt.text2img],
        ['img2img_style_ref', prompt.img2img_style_ref],
      ];
      for (const [field, text] of outputs) {
        if (!text) continue;
        for (const term of terms) {
          if (contains(text, term)) {
            compiledLeaks.push({ subject: s.subject, model: prompt.model, field, term });
          }
        }
      }
    }
  }

  return {
    passed: dnaFindings.length === 0 && compiledLeaks.length === 0,
    dnaFindings,
    compiledLeaks,
  };
}
