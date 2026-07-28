/**
 * 图库覆盖度分析。
 *
 * 调参盘的五个轴要能被标定，图库就得在每个轴的两端和中间都有样本。
 * 这里把每张图放到五维旋钮空间里，报出：每个轴的分布、形态×密度平面上的空格、
 * 以及按坐标聚出的簇（供人给簇起名，那些名字就是个人感受词词典的种子）。
 *
 * 扩库要的不是数量是覆盖度——按空格补图，比凭感觉再存两百张有效得多。
 */

export const FORM_ORDER = [
  'organic_fluid', 'organic_irregular', 'mixed', 'geometric_rounded', 'geometric_hard', 'angular_sharp',
] as const;
export const DENSITY_ORDER = ['sparse', 'low', 'medium', 'high', 'saturated'] as const;
export const BRIGHTNESS_ORDER = ['low_key', 'mid_key', 'high_key'] as const;
export const SATURATION_ORDER = ['desaturated', 'low', 'medium', 'high', 'hyper'] as const;
export const TEMPERATURE_ORDER = ['cool', 'neutral', 'warm'] as const;

export interface CoverageInput {
  short: string;
  geometry: string;
  density: string;
  brightness_key: string;
  saturation_level: string;
  temperature: string;
}

/** 五维坐标，各轴归一化到 0-1。geometry=none 的图没有形态坐标。 */
export interface Point {
  short: string;
  form: number | null;
  density: number;
  brightness: number;
  saturation: number;
  /** temperature=mixed 是一种关系不是位置，不占轴上的点 */
  temperature: number | null;
}

const norm = (arr: readonly string[], v: string): number | null => {
  const i = arr.indexOf(v);
  return i < 0 ? null : arr.length === 1 ? 0 : i / (arr.length - 1);
};

export function toPoint(r: CoverageInput): Point {
  return {
    short: r.short,
    form: norm(FORM_ORDER, r.geometry),
    density: norm(DENSITY_ORDER, r.density) ?? 0.5,
    brightness: norm(BRIGHTNESS_ORDER, r.brightness_key) ?? 0.5,
    saturation: norm(SATURATION_ORDER, r.saturation_level) ?? 0.5,
    temperature: norm(TEMPERATURE_ORDER, r.temperature),
  };
}

/** 缺形态或色温坐标的图用中位数补齐，只为参与聚类；报告里会标出来。 */
const filled = (p: Point): number[] => [
  p.form ?? 0.5, p.density, p.brightness, p.saturation, p.temperature ?? 0.5,
];

const dist = (a: number[], b: number[]): number =>
  Math.sqrt(a.reduce((s, v, i) => s + (v - b[i]) ** 2, 0));

export interface Cluster {
  centroid: number[];
  members: string[];
}

/**
 * k-means，固定初始化（k-means++ 的确定性变体：先取第一个点，之后每次取离已选中心最远的点）。
 * 固定初始化是为了可复现——分布图每跑一次换一批簇，人就没法照着它命名。
 */
export function kmeans(points: Point[], k: number, iterations = 50): Cluster[] {
  const vecs = points.map(filled);
  if (vecs.length <= k) return vecs.map((v, i) => ({ centroid: v, members: [points[i].short] }));

  const centers: number[][] = [vecs[0]];
  while (centers.length < k) {
    let best = -1;
    let bestD = -1;
    vecs.forEach((v, i) => {
      const d = Math.min(...centers.map((c) => dist(v, c)));
      if (d > bestD) { bestD = d; best = i; }
    });
    centers.push(vecs[best]);
  }

  let assign: number[] = new Array(vecs.length).fill(0);
  for (let it = 0; it < iterations; it++) {
    const next = vecs.map((v) => {
      let bi = 0;
      let bd = Infinity;
      centers.forEach((c, i) => { const d = dist(v, c); if (d < bd) { bd = d; bi = i; } });
      return bi;
    });
    const stable = next.every((v, i) => v === assign[i]);
    assign = next;
    for (let c = 0; c < k; c++) {
      const mem = vecs.filter((_, i) => assign[i] === c);
      if (!mem.length) continue;
      centers[c] = mem[0].map((_, d) => mem.reduce((s, v) => s + v[d], 0) / mem.length);
    }
    if (stable) break;
  }

  return centers.map((centroid, c) => ({
    centroid,
    members: points.filter((_, i) => assign[i] === c).map((p) => p.short),
  }));
}

/** 把归一化坐标翻回最近的枚举名，用于给簇写一句人话描述。 */
export function describe(centroid: number[]): string {
  const pick = (arr: readonly string[], v: number) => arr[Math.round(v * (arr.length - 1))];
  return [
    pick(FORM_ORDER, centroid[0]),
    pick(DENSITY_ORDER, centroid[1]),
    pick(BRIGHTNESS_ORDER, centroid[2]),
    pick(SATURATION_ORDER, centroid[3]),
    pick(TEMPERATURE_ORDER, centroid[4]),
  ].join(' / ');
}

export function histogram(rows: CoverageInput[], key: keyof CoverageInput, order: readonly string[]): Array<{ value: string; count: number }> {
  const counts = new Map<string, number>();
  for (const r of rows) counts.set(String(r[key]), (counts.get(String(r[key])) ?? 0) + 1);
  const known = order.map((value) => ({ value, count: counts.get(value) ?? 0 }));
  const extra = [...counts.entries()]
    .filter(([v]) => !order.includes(v))
    .map(([value, count]) => ({ value, count }));
  return [...known, ...extra];
}
