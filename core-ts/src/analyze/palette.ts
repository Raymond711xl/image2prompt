/**
 * 从像素里算色板，而不是让视觉模型用眼睛估 hex。
 *
 * 视觉模型判断「这是低饱和冷调」很可靠，但让它报出 #E8E3D8 这种具体色值就是在编——
 * 它没有取色器。而色板恰恰是调参盘里唯一能所见即所得的部分，色值不准，
 * 色彩轴的实时预览就是假的。所以 hex 和占比由程序算，色彩的性质判断交给模型。
 *
 * 依赖 macOS 自带的 sips 做解码和缩放（本产品就是 Mac App，这个依赖是合理的）。
 * 缩到 64×64 后颜色统计已经足够稳定，而且顺带把 JPEG 的块噪声平均掉了。
 */

import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join as pathJoin } from 'node:path';
import { hexToHsl, hslToHex } from '../drift/color.js';

export interface PaletteEntry {
  hex: string;
  /** 该色簇占全图像素的比例 */
  ratio: number;
  role: 'base' | 'secondary' | 'accent';
}

interface Rgb { r: number; g: number; b: number }

/** 解析 sips 产出的未压缩 BMP。只需支持 24/32 位无压缩这一种情况。 */
function parseBmp(buf: Buffer): { width: number; height: number; pixels: Rgb[] } {
  if (buf.readUInt16LE(0) !== 0x4d42) throw new Error('不是 BMP 文件');
  const dataOffset = buf.readUInt32LE(10);
  const width = buf.readInt32LE(18);
  const height = Math.abs(buf.readInt32LE(22));
  const bpp = buf.readUInt16LE(28);
  if (bpp !== 24 && bpp !== 32) throw new Error(`不支持 ${bpp} 位 BMP`);

  const bytesPerPx = bpp / 8;
  const rowSize = Math.ceil((width * bytesPerPx) / 4) * 4;
  const pixels: Rgb[] = [];
  for (let y = 0; y < height; y++) {
    const rowStart = dataOffset + y * rowSize;
    for (let x = 0; x < width; x++) {
      const p = rowStart + x * bytesPerPx;
      // BMP 按 BGR 存
      pixels.push({ r: buf[p + 2], g: buf[p + 1], b: buf[p] });
    }
  }
  return { width, height, pixels };
}

const toHex = ({ r, g, b }: Rgb): string =>
  `#${[r, g, b].map((n) => Math.round(n).toString(16).padStart(2, '0')).join('')}`.toUpperCase();

/**
 * 色彩距离用 HSL 而不是 RGB。
 * RGB 距离里深红和深蓝可能比深红和亮红更近，聚出来的簇不符合人眼对「同一个颜色」的判断。
 * 色相加权更重，因为色相是区分颜色的主要维度；低饱和时色相不可靠，所以按饱和度衰减它的权重。
 */
function hslDistance(a: Rgb, b: Rgb): number {
  const ha = hexToHsl(toHex(a));
  const hb = hexToHsl(toHex(b));
  let dh = Math.abs(ha.h - hb.h);
  if (dh > 180) dh = 360 - dh;
  const satWeight = Math.min(ha.s, hb.s);
  return (dh / 180) * satWeight * 2 + Math.abs(ha.s - hb.s) + Math.abs(ha.l - hb.l) * 1.5;
}

/** 简单的贪心聚类：按出现频次从高到低吸附。图只有 4096 个像素，不值得上 k-means。 */
function cluster(pixels: Rgb[], threshold: number): Array<{ color: Rgb; count: number }> {
  const buckets = new Map<string, { sum: Rgb; count: number }>();
  for (const p of pixels) {
    // 先按 16 级量化粗分桶，把 JPEG 噪声合并掉
    const key = `${p.r >> 4},${p.g >> 4},${p.b >> 4}`;
    const b = buckets.get(key);
    if (b) {
      b.sum.r += p.r; b.sum.g += p.g; b.sum.b += p.b; b.count++;
    } else {
      buckets.set(key, { sum: { ...p }, count: 1 });
    }
  }

  const coarse = [...buckets.values()]
    .map((b) => ({ color: { r: b.sum.r / b.count, g: b.sum.g / b.count, b: b.sum.b / b.count }, count: b.count }))
    .sort((a, b) => b.count - a.count);

  const merged: Array<{ color: Rgb; count: number }> = [];
  for (const c of coarse) {
    const near = merged.find((m) => hslDistance(m.color, c.color) < threshold);
    if (near) {
      const total = near.count + c.count;
      near.color = {
        r: (near.color.r * near.count + c.color.r * c.count) / total,
        g: (near.color.g * near.count + c.color.g * c.count) / total,
        b: (near.color.b * near.count + c.color.b * c.count) / total,
      };
      near.count = total;
    } else {
      merged.push({ ...c, color: { ...c.color } });
    }
  }
  return merged.sort((a, b) => b.count - a.count);
}

export interface ExtractOptions {
  /** 最多返回几个色。默认 5——超过这个数写进提示词只会稀释权重。 */
  max?: number;
  /** 聚类合并阈值。调大出的色更少更概括，调小更细。 */
  threshold?: number;
}

/**
 * 提取色板。
 *
 * accent 的判定不看面积看饱和度：「低明度墨绿 + 高明度米白 + 一点铬黄」里的铬黄
 * 可能只占 0.4% 面积却是这张图的签名色，按面积排它会被直接丢掉。
 */
export function extractPalette(imagePath: string, opts: ExtractOptions = {}): PaletteEntry[] {
  const max = opts.max ?? 5;
  const dir = mkdtempSync(pathJoin(tmpdir(), 'i2p-palette-'));
  const bmpPath = pathJoin(dir, 'out.bmp');
  try {
    execFileSync('sips', ['-s', 'format', 'bmp', '-z', '64', '64', imagePath, '--out', bmpPath], {
      stdio: 'ignore',
    });
    const { pixels } = parseBmp(readFileSync(bmpPath));
    const total = pixels.length;
    const clusters = cluster(pixels, opts.threshold ?? 0.28).slice(0, max);

    return clusters.map((c, i) => {
      const hex = hslToHex(hexToHsl(toHex(c.color)));
      const hsl = hexToHsl(hex);
      const ratio = Math.round((c.count / total) * 1000) / 1000;
      // 面积最大的是主色；其余里高饱和的算点缀色，低饱和的算辅色
      const role: PaletteEntry['role'] = i === 0
        ? 'base'
        : hsl.s > 0.5 && ratio < 0.25 ? 'accent' : 'secondary';
      return { hex, ratio, role };
    });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}
