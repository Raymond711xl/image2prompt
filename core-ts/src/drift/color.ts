/**
 * 色板运算。
 *
 * 色彩轴是整个调参盘里唯一能所见即所得的部分：palette 是 hex + ratio，
 * 色相旋转、明度平移、饱和度缩放都是纯计算，零 API、零延迟，界面上可以直接刷色块。
 * 形态轴做不到这一点——它只能显示字段 diff，效果必须真出图才看得见。
 */

export interface Hsl {
  /** 0-360 */
  h: number;
  /** 0-1 */
  s: number;
  /** 0-1 */
  l: number;
}

const clamp01 = (n: number): number => Math.min(1, Math.max(0, n));
const wrapHue = (h: number): number => ((h % 360) + 360) % 360;

export function hexToHsl(hex: string): Hsl {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim());
  if (!m) throw new Error(`色值格式不合法：${hex}（需要 #RRGGBB）`);
  const int = parseInt(m[1], 16);
  const r = ((int >> 16) & 255) / 255;
  const g = ((int >> 8) & 255) / 255;
  const b = (int & 255) / 255;

  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  const d = max - min;

  if (d === 0) return { h: 0, s: 0, l };

  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  let h: number;
  if (max === r) h = ((g - b) / d + (g < b ? 6 : 0)) * 60;
  else if (max === g) h = ((b - r) / d + 2) * 60;
  else h = ((r - g) / d + 4) * 60;

  return { h: wrapHue(h), s, l };
}

export function hslToHex({ h, s, l }: Hsl): string {
  const hh = wrapHue(h);
  const ss = clamp01(s);
  const ll = clamp01(l);

  if (ss === 0) {
    const v = Math.round(ll * 255);
    return `#${[v, v, v].map((n) => n.toString(16).padStart(2, '0')).join('')}`.toUpperCase();
  }

  const q = ll < 0.5 ? ll * (1 + ss) : ll + ss - ll * ss;
  const p = 2 * ll - q;
  const channel = (t: number): number => {
    let tt = t;
    if (tt < 0) tt += 1;
    if (tt > 1) tt -= 1;
    if (tt < 1 / 6) return p + (q - p) * 6 * tt;
    if (tt < 1 / 2) return q;
    if (tt < 2 / 3) return p + (q - p) * (2 / 3 - tt) * 6;
    return p;
  };

  const r = Math.round(channel(hh / 360 + 1 / 3) * 255);
  const g = Math.round(channel(hh / 360) * 255);
  const b = Math.round(channel(hh / 360 - 1 / 3) * 255);
  return `#${[r, g, b].map((n) => n.toString(16).padStart(2, '0')).join('')}`.toUpperCase();
}

/** 暖极与冷极的色相锚点。橙黄一带是暖，青蓝一带是冷。 */
export const WARM_POLE = 30;
export const COOL_POLE = 210;

/**
 * 把色相沿最短弧朝某个极点旋转固定角度。
 *
 * 为什么是「朝极点旋转」而不是「全体加固定角度」：后者能完美保持色相间距，
 * 但从蓝(210°)加 15° 会变成紫(225°)，那不叫变暖，只是换了个颜色。朝极点旋转
 * 保持了色相的相对顺序（所有颜色朝同一方向走），间距会略微收拢——这是变暖/变冷
 * 这个语义本身要求的代价，因为极端的暖和冷本来就是收敛到某个区域。
 *
 * 灰色（s≈0）不参与旋转：无彩色没有色相可言，转它只会凭空造出颜色。
 */
export function rotateTowardPole(hex: string, pole: number, degrees: number): string {
  const hsl = hexToHsl(hex);
  if (hsl.s < 0.04) return hex.toUpperCase();

  let delta = wrapHue(pole - hsl.h);
  if (delta > 180) delta -= 360; // 取最短弧，可能为负
  const move = Math.sign(delta) * Math.min(Math.abs(delta), degrees);
  return hslToHex({ ...hsl, h: hsl.h + move });
}

export interface ShiftResult {
  hex: string;
  /** 是否撞到 0/1 边界被截断。截断意味着这一档没有完整走完，明度结构被压缩了。 */
  clamped: boolean;
}

/**
 * 明度整体平移。所有颜色平移同一个量，明度的相对结构（谁亮谁暗、差多少）保持不变。
 * 撞到 0 或 1 时会被截断，此时结构就被压扁了——所以要把 clamped 报出去，
 * 让界面能提示「这个方向已经到头」，而不是让用户对着没变化的色块反复拖。
 */
export function shiftLightness(hex: string, delta: number): ShiftResult {
  const hsl = hexToHsl(hex);
  const raw = hsl.l + delta;
  const clamped = raw < 0 || raw > 1;
  return { hex: hslToHex({ ...hsl, l: clamp01(raw) }), clamped };
}

/**
 * 饱和度按倍数缩放（不是加减）。
 * 用乘法是因为饱和度的感知是比例性的：0.1→0.2 和 0.8→0.9 加的量一样，
 * 但前者是翻倍的剧变，后者几乎看不出来。
 */
export function scaleSaturation(hex: string, factor: number): ShiftResult {
  const hsl = hexToHsl(hex);
  const raw = hsl.s * factor;
  const clamped = raw > 1;
  return { hex: hslToHex({ ...hsl, s: clamp01(raw) }), clamped };
}
