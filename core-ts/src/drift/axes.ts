/**
 * 偏移轴定义。
 *
 * 每个轴是一条**有序**的枚举序列，偏移就是在序列上走 N 步。之所以要有序，
 * 是因为「偏移」必须是可解释的方向性操作：往左走一步和往右走一步应该是相反的气质变化。
 * 随机重跑得到的是噪声，在有序轴上走一步得到的是变体——噪声没法说「这个方向再多一点」。
 */

import type { Edge, Geometry } from '../types.js';

/**
 * 形态轴：有机 ← → 几何。按「硬度」单调排列。
 *
 * organic_fluid 是最流动的（连续曲率液态），angular_sharp 是最硬的（尖锐棱角）。
 * mixed 放在中间当过渡档。none（无明确形态语言）不在轴上——没有形态可偏移。
 */
export const FORM_AXIS: Geometry[] = [
  'organic_fluid',
  'organic_irregular',
  'mixed',
  'geometric_rounded',
  'geometric_hard',
  'angular_sharp',
];

/**
 * geometry 变化时 edge 必须跟着走，否则会产出「几何硬朗 + 波浪边缘」这种自相矛盾的 spec。
 * lint L2 会把跨阵营的组合报出来，所以这张表实际上是在保证 drift 的输出能过 lint。
 */
export const EDGE_FOR_GEOMETRY: Record<Geometry, Edge> = {
  organic_fluid: 'wavy',
  organic_irregular: 'irregular',
  mixed: 'small_radius_rounded',
  geometric_rounded: 'large_radius_rounded',
  geometric_hard: 'straight',
  angular_sharp: 'straight',
  none: 'none',
};

/** 密度轴：疏 ← → 密。 */
export const DENSITY_AXIS = ['sparse', 'low', 'medium', 'high', 'saturated'] as const;

/** 色温轴：冷 ← → 暖。mixed（冷暖对比）不在轴上，它是一种关系而不是一个位置。 */
export const TEMPERATURE_AXIS = ['cool', 'neutral', 'warm'] as const;

/** 调性轴：暗调 ← → 亮调。 */
export const BRIGHTNESS_AXIS = ['low_key', 'mid_key', 'high_key'] as const;

/** 饱和度轴：无彩 ← → 撞色。 */
export const SATURATION_AXIS = ['desaturated', 'low', 'medium', 'high', 'hyper'] as const;

export interface AxisMove<T> {
  value: T;
  /** 实际走了几步。与请求步数不同即说明撞到了轴的端点。 */
  moved: number;
  /** 请求走的步数 */
  requested: number;
}

/**
 * 在有序轴上移动。超出端点就停在端点，并把实际步数报回去——
 * 界面需要知道「已经到头了」，否则用户会对着不再变化的面板反复拖。
 */
export function moveOnAxis<T>(axis: readonly T[], current: T, steps: number): AxisMove<T> {
  const idx = axis.indexOf(current);
  if (idx < 0) return { value: current, moved: 0, requested: steps };
  const target = Math.min(axis.length - 1, Math.max(0, idx + steps));
  return { value: axis[target], moved: target - idx, requested: steps };
}

/** 每档的色彩运算量。调这三个常数就能整体改变「一档」的手感。 */
export const COLOR_STEP = {
  /** 色相朝极点旋转的度数 */
  hueDegrees: 12,
  /** 明度平移量 */
  lightness: 0.06,
  /** 饱和度缩放倍率（每档乘或除） */
  saturationFactor: 1.18,
} as const;

/** 密度每档带动的构图数值。密度升高 = 主体占比升、负空间降。 */
export const DENSITY_STEP = {
  subjectCoverage: 0.05,
  negativeSpaceRatio: 0.06,
} as const;
