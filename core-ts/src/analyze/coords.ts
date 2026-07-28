/**
 * 从像素直接算出色彩三轴的坐标。
 *
 * 调参盘有五个轴，其中色温、调性、饱和度三个**完全由色板决定**，是可计算的。
 * 让视觉模型用眼睛判断「这张算高饱和还是中饱和」不但慢，而且在几十张图之间没有一致的标尺——
 * 同一个模型两次看同一张图可能给出不同档位，那样画出来的分布图是假的。
 *
 * 形态和密度算不出来，那两个轴仍然要人／模型看图判断。
 */

import { chroma, hexToHsl } from '../drift/color.js';
import { extractPalette, type PaletteEntry } from './palette.js';
import { COOL_POLE, WARM_POLE } from '../drift/color.js';

export interface ColorCoords {
  /** 加权平均明度 0-1 */
  lightness: number;
  /** 加权平均彩度 0-1。用 chroma 而非 HSL saturation，理由见 color.ts 的说明。 */
  saturation: number;
  /** 冷暖投影 -1(极冷) .. +1(极暖) */
  warmth: number;
  /** 冷暖是否两极分化（同时存在强冷色和强暖色）→ 判为 mixed 而不是取中间值 */
  polarized: boolean;
  brightness_key: 'low_key' | 'mid_key' | 'high_key';
  saturation_level: 'desaturated' | 'low' | 'medium' | 'high' | 'hyper';
  temperature: 'cool' | 'neutral' | 'warm' | 'mixed';
}

/**
 * 彩度过低的颜色没有可信的色相，参与冷暖计算只会引入噪声。
 * 这道闸门必须用 chroma 把关：用 HSL 饱和度的话，#000001 这种视觉纯黑会以
 * s=1.0 的身份混进来，把整张图的冷暖判断带偏成它那 1/255 的蓝。
 */
const HUE_RELIABLE_CHROMA = 0.12;

/**
 * 把色相投影到冷暖轴上。
 * 暖极 30°、冷极 210° 正好相差 180°，所以 cos(h − 30°) 天然就是这条轴的投影：
 * 在暖极取 +1，在冷极取 −1，中间连续过渡。
 */
const warmthOf = (hue: number): number => Math.cos(((hue - WARM_POLE) * Math.PI) / 180);

/** 参与「最鲜艳的那一笔」评估的最低面积。低于此值的多半是压缩噪声或抗锯齿边缘。 */
const SIGNIFICANT_RATIO = 0.02;

/**
 * 纯面积加权会低估「小面积高彩度」的图。
 *
 * 实测反例：一张纯黑底 + 六块霓虹渐变卡片的图，黑色占七成面积，面积加权彩度算出来接近 0，
 * 于是被判成「近乎无彩」，聚类时和暗调实拍照片归到了一起——但那张图肉眼看极其鲜艳。
 * 这和 compile 里 paletteText 早就知道的事是同一件：占 0.4% 面积的铬黄可能是整张图的签名色。
 *
 * 所以整体彩度取「面积加权」和「最鲜艳的显著色」的混合。0.6/0.4 这个配比是拿这批图凑出来的，
 * 属于待标定参数——等用户给簇命名之后应该回来复核。
 */
const AREA_WEIGHT = 0.6;

export function colorCoords(palette: PaletteEntry[]): ColorCoords {
  const totalRatio = palette.reduce((s, c) => s + c.ratio, 0) || 1;
  let lightness = 0;
  let areaChroma = 0;
  let peakChroma = 0;
  let warmSum = 0;
  let warmWeight = 0;
  let maxWarm = -1;
  let minWarm = 1;

  for (const c of palette) {
    const { h, l } = hexToHsl(c.hex);
    const ch = chroma(c.hex);
    const w = c.ratio / totalRatio;
    lightness += l * w;
    areaChroma += ch * w;
    if (c.ratio >= SIGNIFICANT_RATIO) peakChroma = Math.max(peakChroma, ch);

    if (ch >= HUE_RELIABLE_CHROMA) {
      const warmth = warmthOf(h);
      // 用彩度再加权一次：越鲜艳的颜色对整体冷暖印象的贡献越大
      const ww = w * ch;
      warmSum += warmth * ww;
      warmWeight += ww;
      maxWarm = Math.max(maxWarm, warmth);
      minWarm = Math.min(minWarm, warmth);
    }
  }

  const warmth = warmWeight > 0 ? warmSum / warmWeight : 0;
  // 两端都够强才算冷暖对比，否则只是有个别杂色
  const polarized = warmWeight > 0 && maxWarm > 0.45 && minWarm < -0.45;
  const saturation = AREA_WEIGHT * areaChroma + (1 - AREA_WEIGHT) * peakChroma;

  return {
    lightness: round3(lightness),
    saturation: round3(saturation),
    warmth: round3(warmth),
    polarized,
    brightness_key: lightness < 0.35 ? 'low_key' : lightness > 0.65 ? 'high_key' : 'mid_key',
    // 阈值按 chroma 标定，与 HSL saturation 的档位不同——chroma 天然偏小
    saturation_level:
      saturation < 0.08 ? 'desaturated'
        : saturation < 0.2 ? 'low'
          : saturation < 0.38 ? 'medium'
            : saturation < 0.6 ? 'high' : 'hyper',
    temperature: polarized ? 'mixed' : warmth > 0.3 ? 'warm' : warmth < -0.3 ? 'cool' : 'neutral',
  };
}

export interface ImageCoords extends ColorCoords {
  file: string;
  palette: PaletteEntry[];
}

export function imageCoords(imagePath: string, max = 6): ImageCoords {
  const palette = extractPalette(imagePath, { max });
  return { file: imagePath, palette, ...colorCoords(palette) };
}

const round3 = (n: number): number => Math.round(n * 1000) / 1000;
export { COOL_POLE, WARM_POLE };
