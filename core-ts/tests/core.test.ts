import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { compile, compileAll, CompileError } from '../src/compile/index.js';
import { lintPrompt, lintSpec, hasError } from '../src/lint/rules.js';
import { runTransferTest } from '../src/eval/transferTest.js';
import { validateBrief, validateStyleSpec } from '../src/validate.js';
import type { Brief, StyleSpec } from '../src/types.js';

const FIXTURES = resolve(import.meta.dirname, '..', 'evals', 'fixtures');
const load = <T>(name: string): T => JSON.parse(readFileSync(resolve(FIXTURES, name), 'utf8')) as T;

const SPEC = 'red-pixel-newyear-poster.stylespec.json';
const SPEC_HERO = 'white-highkey-scale-hero.stylespec.json';
const BRIEF_TRANSFER = 'glucose-meter-wechat-cover.brief.json';
const BRIEF_EDIT = 'pixel-swap-edit.brief.json';

const ALL_SPECS = [SPEC, SPEC_HERO];

const spec = () => structuredClone(load<StyleSpec>(SPEC));
const specHero = () => structuredClone(load<StyleSpec>(SPEC_HERO));
const briefTransfer = () => structuredClone(load<Brief>(BRIEF_TRANSFER));
const briefEdit = () => structuredClone(load<Brief>(BRIEF_EDIT));

describe('schema 校验', () => {
  it.each(ALL_SPECS)('golden StyleSpec %s 通过校验', (name) => {
    const r = validateStyleSpec(load(name));
    expect(r.errors).toEqual([]);
    expect(r.ok).toBe(true);
  });

  it.each([BRIEF_TRANSFER, BRIEF_EDIT])('Brief %s 通过校验', (name) => {
    const r = validateBrief(load(name));
    expect(r.errors).toEqual([]);
    expect(r.ok).toBe(true);
  });

  it('negative_space.region 只接受位置枚举，拒绝自由文本', () => {
    const s = spec();
    // 「主图形与底部大字之间」这类描述会把原图元素带进提示词
    (s.composition.negative_space as { region: string }).region = '主图形与底部大字之间';
    expect(validateStyleSpec(s).ok).toBe(false);
  });
});

describe('lint：StyleSpec 级', () => {
  it.each(ALL_SPECS)('golden spec %s 无任何问题', (name) => {
    expect(lintSpec(load<StyleSpec>(name))).toEqual([]);
  });

  it('L1 抓出 style_dna 里的内容泄漏', () => {
    const s = spec();
    s.style_dna += '，画面中央是一匹奔马';
    const findings = lintSpec(s);
    expect(findings.some((f) => f.rule === 'L1' && f.level === 'error')).toBe(true);
    expect(findings.find((f) => f.rule === 'L1')?.message).toContain('奔马');
  });

  it('L1 同样检查英文版风格 DNA', () => {
    const s = spec();
    s.style_dna_en += ' with a running horse at the centre';
    expect(lintSpec(s).some((f) => f.rule === 'L1' && f.where === 'style_dna_en')).toBe(true);
  });

  it('L1 不对单字中文词误报', () => {
    const s = spec();
    s.content.keywords = ['马']; // 单字太容易误伤，应被跳过
    expect(lintSpec(s).filter((f) => f.rule === 'L1')).toEqual([]);
  });

  it('L2 抓出几何形态里混进的有机形态词', () => {
    const s = spec();
    expect(s.form_language.geometry).toBe('geometric_hard');
    s.style_dna += '，形体呈液态流动质感';
    const findings = lintSpec(s);
    expect(findings.some((f) => f.rule === 'L2' && f.level === 'warn')).toBe(true);
    expect(findings.find((f) => f.rule === 'L2')?.message).toContain('液态');
  });

  it('L2 抓出 geometry 与 edge 阵营矛盾', () => {
    const s = spec();
    s.form_language.edge = 'wavy'; // 几何形态配波浪边缘
    expect(lintSpec(s).some((f) => f.rule === 'L2' && f.where === 'form_language')).toBe(true);
  });
});

describe('compile：编译产物', () => {
  it('两个模型都产出文生图和垫图风格参考', () => {
    for (const p of compileAll(spec(), briefTransfer())) {
      expect(p.text2img).toBeTruthy();
      expect(p.img2img_style_ref).toBeTruthy();
    }
  });

  it('平面媒介不编出光影描述', () => {
    const p = compile(spec(), briefTransfer(), 'jimeng');
    expect(p.text2img).toContain('纯平面无光影模拟');
    expect(p.text2img).not.toContain('环境漫射光');
  });

  it('非平面媒介照常编出光影描述', () => {
    const p = compile(specHero(), briefTransfer(), 'jimeng');
    expect(p.text2img).toContain('大面积柔光箱顶部漫射光');
    expect(p.text2img).not.toContain('纯平面无光影模拟');
  });

  it('签名点缀色即使只占 0.4% 也保留', () => {
    const s = specHero();
    expect(s.palette.find((c) => c.role === 'accent')!.ratio).toBeLessThan(0.01);
    const p = compile(s, briefTransfer(), 'jimeng');
    expect(p.text2img).toContain('低饱和薄荷绿');
    expect(p.text2img).toContain('小面积点缀'); // 极小占比不写百分数
  });

  it('低占比的主色/辅色仍按面积过滤', () => {
    const s = spec();
    s.palette.push({ hex: '#123456', ratio: 0.01, role: 'secondary', name_cn: '可忽略的深蓝' });
    const p = compile(s, briefTransfer(), 'jimeng');
    expect(p.text2img).not.toContain('可忽略的深蓝');
  });

  it('visual_flow 不进入编译产物（动线依附原图元素，换主体不成立）', () => {
    const s = spec();
    s.composition.visual_flow = '顶部大字入画然后落到底部大字收尾';
    for (const p of compileAll(s, briefTransfer())) {
      expect(p.text2img).not.toContain('底部大字');
    }
  });

  it('geometry 已隐含的 edge 不重复输出', () => {
    const p = compile(spec(), briefTransfer(), 'jimeng');
    expect(p.text2img).toContain('平直边缘');
    expect(p.text2img).not.toContain('边缘平直'); // EDGE_CN.straight，与 geometry 描述重复
  });

  it('画幅比例只写进 notes，不写进即梦提示词', () => {
    const p = compile(spec(), briefTransfer(), 'jimeng');
    expect(p.aspect_ratio).toBe('16:9');
    expect(p.notes.some((n) => n.includes('16:9'))).toBe(true);
  });

  it('禁止项转成正向表述', () => {
    const p = compile(spec(), briefTransfer(), 'jimeng');
    expect(p.text2img).toContain('纯色极简背景'); // must_avoid: 杂物
    expect(p.text2img).not.toContain('没有杂物');
  });

  it('转不成正向的禁止项落到 notes，不硬编否定句', () => {
    const b = briefTransfer();
    b.must_avoid = ['某种说不清的东西'];
    const p = compile(spec(), b, 'jimeng');
    expect(p.text2img).not.toContain('某种说不清的东西');
    expect(p.notes.some((n) => n.includes('负向词'))).toBe(true);
  });

  it('render_text_in_image 为 false 时文案不进提示词', () => {
    const p = compile(spec(), briefTransfer(), 'jimeng');
    expect(p.text2img).not.toContain('血糖管理新方式');
    expect(p.notes.some((n) => n.includes('可编辑图层'))).toBe(true);
  });

  it('render_text_in_image 为 true 时文案写进提示词', () => {
    const b = briefTransfer();
    b.render_text_in_image = true;
    const p = compile(spec(), b, 'jimeng');
    expect(p.text2img).toContain('血糖管理新方式');
  });

  it('参考槽协议点明每张图各参考什么', () => {
    const b = briefTransfer();
    b.refs = { style: 'a.json', composition: 'b.json', subject: 'c.json' };
    const p = compile(spec(), b, 'gpt-image');
    expect(p.ref_protocol).toContain('只参考视觉风格');
    expect(p.ref_protocol).toContain('只参考构图');
    expect(p.ref_protocol).toContain('只参考主体外观');
  });
});

describe('compile：边界控制四纪律', () => {
  it('提供 edit 块时产出四部件齐全的编辑指令', () => {
    const p = compile(spec(), briefEdit(), 'gpt-image');
    expect(p.parts.edit).not.toBeNull();
    expect(p.parts.edit!.scope).toContain('仅编辑');
    expect(p.parts.edit!.protect).toContain('保持与原图完全一致');
    expect(p.parts.edit!.replace).toContain('替换为');
    expect(p.parts.edit!.noAddNoRemove).toContain('不新增');
    expect(lintPrompt(spec(), briefEdit(), p).filter((f) => f.rule === 'L3')).toEqual([]);
  });

  it('无 edit 块时不产出编辑指令，只给提示', () => {
    const p = compile(spec(), briefTransfer(), 'gpt-image');
    expect(p.img2img_edit).toBeNull();
    expect(p.parts.edit).toBeNull();
    expect(p.notes.some((n) => n.includes('edit 块'))).toBe(true);
  });

  it('纪律三：替换目标含扫射性量词时编译期失败', () => {
    const b = briefEdit();
    b.edit!.replace = [{ target: '所有黑色图形', new_content: '血糖仪剪影' }];
    expect(() => compile(spec(), b, 'gpt-image')).toThrow(CompileError);
    expect(() => compile(spec(), b, 'gpt-image')).toThrow(/量词/);
  });

  it('纪律二：保护项没写原有内容时编译期失败', () => {
    const b = briefEdit();
    b.edit!.protect = [{ element: '顶部标题', original_content: '' }];
    expect(() => compile(spec(), b, 'gpt-image')).toThrow(/original_content|锚死/);
  });

  it('纪律一：范围锚点用概念词而非视觉锚点时编译期失败', () => {
    const b = briefEdit();
    b.edit!.scope_anchor = '我们的那块区域';
    expect(() => compile(spec(), b, 'gpt-image')).toThrow(/视觉锚点/);
  });

  it('缺融合要求时不失败，但给出提示', () => {
    const b = briefEdit();
    b.edit!.merge_requirements = null;
    const p = compile(spec(), b, 'gpt-image');
    expect(p.img2img_edit).toBeTruthy();
    expect(p.notes.some((n) => n.includes('merge_requirements'))).toBe(true);
  });
});

describe('lint：编译产物级', () => {
  it('golden 组合只剩一条 L4 提醒（来自 Brief 自带的「无任何标识」）', () => {
    const s = spec();
    const b = briefTransfer();
    const findings = compileAll(s, b).flatMap((p) => lintPrompt(s, b, p));
    expect(hasError(findings)).toBe(false);
    expect(findings.map((f) => f.rule)).toEqual(['L4']);
  });

  it('L4 抓出即梦版的否定式表述', () => {
    const s = spec();
    const b = briefTransfer();
    b.subject_detail = '机身干净，没有任何标识';
    const p = compile(s, b, 'jimeng');
    expect(lintPrompt(s, b, p).some((f) => f.rule === 'L4')).toBe(true);
  });

  it('L4 放行形态避坑的排除句（实测必要例外）', () => {
    const s = spec();
    s.form_language.geometry = 'geometric_rounded';
    s.form_language.edge = 'large_radius_rounded';
    const b = briefTransfer();
    b.must_avoid = [];
    b.subject_detail = '机身圆润';
    const p = compile(s, b, 'jimeng');
    expect(p.text2img).toContain('不要波浪形有机曲线');
    expect(lintPrompt(s, b, p).filter((f) => f.rule === 'L4')).toEqual([]);
  });

  it('L5 抓出堆砌的画质词', () => {
    const s = spec();
    s.mood = ['8K细节', '超写实', '商业广告级画质'];
    const b = briefTransfer();
    const p = compile(s, b, 'jimeng');
    const f = lintPrompt(s, b, p).find((x) => x.rule === 'L5');
    expect(f?.level).toBe('warn');
    expect(f?.message).toContain('3 个');
  });

  it('L6 抓出漏进提示词的原图品牌名', () => {
    const s = spec();
    s.content.brand_marks = ['京东健康'];
    s.composition.grid = '京东健康标准版式，四边贴边满宽单栏';
    const b = briefTransfer();
    const findings = compileAll(s, b).flatMap((p) => lintPrompt(s, b, p));
    expect(findings.some((f) => f.rule === 'L6' && f.level === 'error')).toBe(true);
  });

  it('L6 放行 Brief 显式 must_keep 的品牌', () => {
    const s = spec();
    s.content.brand_marks = ['京东健康'];
    s.composition.grid = '京东健康标准版式，四边贴边满宽单栏';
    const b = briefTransfer();
    b.must_keep = ['京东健康'];
    const findings = compileAll(s, b).flatMap((p) => lintPrompt(s, b, p));
    expect(findings.filter((f) => f.rule === 'L6')).toEqual([]);
  });
});

describe('风格迁移测试', () => {
  it.each(ALL_SPECS)('golden spec %s 通过：换三个不相关主体都不带出原图内容', (name) => {
    const r = runTransferTest(load<StyleSpec>(name));
    expect(r.compiledLeaks).toEqual([]);
    expect(r.dnaFindings).toEqual([]);
    expect(r.passed).toBe(true);
  });

  it('抓出藏在自由文本字段里的泄漏（L1 查不到的那一类）', () => {
    const s = spec();
    // material.surfaces[].where 会被编进提示词，写成原图的具体物件就会跟着换主体一起跑出来
    s.material.surfaces = [{ where: '奔马剪影', finish: 'matte', detail: '纯平涂' }];
    const r = runTransferTest(s);
    expect(r.passed).toBe(false);
    expect(r.compiledLeaks.some((l) => l.term === '奔马')).toBe(true);
    expect(r.dnaFindings).toEqual([]); // style_dna 本身是干净的，只有编译产物泄漏
  });
});

describe('编译产物快照', () => {
  it('跨主体：新年海报风格 → 血糖仪微信头图', () => {
    expect(compileAll(spec(), briefTransfer())).toMatchSnapshot();
  });

  it('局部编辑：只换中央像素图形', () => {
    expect(compile(spec(), briefEdit(), 'gpt-image')).toMatchSnapshot();
  });

  it('跨主体：高调白渲染风格 → 血糖仪微信头图', () => {
    expect(compileAll(specHero(), briefTransfer())).toMatchSnapshot();
  });
});
