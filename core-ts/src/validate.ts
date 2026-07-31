import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import _Ajv, { type ErrorObject } from 'ajv';
import type { Brief, StyleSpec } from './types.js';

// ajv v8 是 CJS，NodeNext 下默认导出解析成命名空间，需要显式取 .default
const Ajv = _Ajv as unknown as typeof _Ajv.default;

const here = dirname(fileURLToPath(import.meta.url));
export const SCHEMA_DIR = resolve(here, '..', '..', 'schema');

const ajv = new Ajv({ allErrors: true, strict: false });
// 不引 ajv-formats：只用到 date-time 一个格式，自带一条 ISO 8601 正则即可真的校验
ajv.addFormat('date-time', /^\d{4}-\d{2}-\d{2}[Tt]\d{2}:\d{2}:\d{2}(\.\d+)?([Zz]|[+-]\d{2}:\d{2})$/);

const loadSchema = (file: string) => JSON.parse(readFileSync(resolve(SCHEMA_DIR, file), 'utf8'));

const validateStyleSpecFn = ajv.compile(loadSchema('stylespec.v0.2.json'));
const validateBriefFn = ajv.compile(loadSchema('brief.v0.1.json'));

export interface ValidationResult<T> {
  ok: boolean;
  value?: T;
  errors: string[];
}

const formatErrors = (errors: ErrorObject[] | null | undefined): string[] =>
  (errors ?? []).map((e) => {
    const path = e.instancePath || '(根)';
    const allowed = e.params && 'allowedValues' in e.params
      ? `（可选值：${(e.params.allowedValues as string[]).join(' / ')}）`
      : '';
    return `${path} ${e.message}${allowed}`;
  });

export function validateStyleSpec(data: unknown): ValidationResult<StyleSpec> {
  const ok = validateStyleSpecFn(data);
  return ok
    ? { ok: true, value: data as StyleSpec, errors: [] }
    : { ok: false, errors: formatErrors(validateStyleSpecFn.errors) };
}

export function validateBrief(data: unknown): ValidationResult<Brief> {
  const ok = validateBriefFn(data);
  return ok
    ? { ok: true, value: data as Brief, errors: [] }
    : { ok: false, errors: formatErrors(validateBriefFn.errors) };
}

/** 读 JSON 文件并校验。校验失败直接抛，CLI 层统一渲染。 */
export function readStyleSpec(path: string): StyleSpec {
  const raw = JSON.parse(readFileSync(path, 'utf8'));
  const r = validateStyleSpec(raw);
  if (!r.ok) throw new Error(`StyleSpec 校验失败 (${path}):\n  ${r.errors.join('\n  ')}`);
  return r.value!;
}

export function readBrief(path: string): Brief {
  const raw = JSON.parse(readFileSync(path, 'utf8'));
  const r = validateBrief(raw);
  if (!r.ok) throw new Error(`Brief 校验失败 (${path}):\n  ${r.errors.join('\n  ')}`);
  return r.value!;
}
