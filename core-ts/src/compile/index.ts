import type { Brief, CompiledPrompt, ModelId, StyleSpec } from '../types.js';
import { compileJimeng } from './adapters/jimeng.js';
import { compileGptImage, CompileError } from './adapters/gptImage.js';

export { CompileError };

const ADAPTERS: Record<ModelId, (spec: StyleSpec, brief: Brief) => CompiledPrompt> = {
  jimeng: compileJimeng,
  'gpt-image': compileGptImage,
};

export const MODEL_IDS = Object.keys(ADAPTERS) as ModelId[];

/**
 * StyleSpec + Brief → 模型专用提示词。纯函数，无网络无 IO。
 *
 * 模型只是可替换的生成出口，新增模型 = 新增一个适配器，不动 StyleSpec。
 */
export function compile(spec: StyleSpec, brief: Brief, model: ModelId): CompiledPrompt {
  const adapter = ADAPTERS[model];
  if (!adapter) {
    throw new CompileError('model', `未知模型 "${model}"。可用：${MODEL_IDS.join(' / ')}`);
  }
  return adapter(spec, brief);
}

/** 一次编译全部模型，用于对比和快照测试。 */
export function compileAll(spec: StyleSpec, brief: Brief): CompiledPrompt[] {
  return MODEL_IDS.map((m) => compile(spec, brief, m));
}
