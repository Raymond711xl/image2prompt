/**
 * 枚举值 → 提示词用词。
 * 这是把 StyleSpec 的离散字段翻译回自然语言的唯一出口——改词只改这里，
 * 所有适配器和快照测试同步生效。
 */

const cn = <T extends string>(m: Record<T, string>) => m;

export const SHOT_CN = cn({
  extreme_close_up: '微距特写',
  close_up: '特写',
  medium: '中景',
  wide: '全景',
  extreme_wide: '大远景',
});

export const ANGLE_CN = cn({
  eye_level: '平视',
  low_angle: '低角度仰拍',
  high_angle: '微俯视角',
  top_down: '正俯拍',
  dutch: '倾斜构图',
});

export const MEDIUM_CN = cn({
  photography: '摄影',
  '3d_render': '3D 渲染',
  vector_illustration: '矢量插画',
  raster_illustration: '插画',
  graphic_design: '平面设计',
  typography_poster: '排版海报',
  collage: '拼贴',
  mixed_media: '混合媒介',
  other: '',
});

export const MEDIUM_EN = cn({
  photography: 'photography',
  '3d_render': '3D render',
  vector_illustration: 'vector illustration',
  raster_illustration: 'illustration',
  graphic_design: 'graphic design',
  typography_poster: 'typographic poster',
  collage: 'collage',
  mixed_media: 'mixed media',
  other: '',
});

export const LIGHT_DIR_CN = cn({
  front: '正面光',
  side: '侧光',
  back: '逆光',
  top: '顶光',
  bottom: '底光',
  ambient: '环境漫射光',
  mixed: '混合光源',
});

export const LIGHT_QUALITY_CN = cn({ soft: '柔和', hard: '硬朗', mixed: '软硬结合' });

export const LIGHT_CONTRAST_CN = cn({
  flat: '几乎无明暗对比',
  low: '低光比',
  medium: '中等光比',
  high: '强明暗对比',
  dramatic: '戏剧性光比',
});

export const SATURATION_CN = cn({
  desaturated: '近乎无彩',
  low: '低饱和',
  medium: '中等饱和',
  high: '高饱和',
  hyper: '极高饱和撞色',
});

export const TEMPERATURE_CN = cn({ cool: '冷色调', neutral: '中性色调', warm: '暖色调', mixed: '冷暖对比色调' });

export const COLOR_CONTRAST_CN = cn({
  flat: '低对比平淡',
  low: '低对比',
  medium: '中对比',
  high: '高对比',
  extreme: '极致高对比',
});

export const BRIGHTNESS_CN = cn({ low_key: '暗调', mid_key: '中间调', high_key: '亮调' });

export const DENSITY_CN = cn({
  sparse: '画面元素极少、大量呼吸空间',
  low: '低密度、克制',
  medium: '中等密度',
  high: '高密度排布',
  saturated: '满版高密度',
});

export const FINISH_CN = cn({
  matte: '哑光',
  glossy: '光泽',
  metallic: '金属',
  chrome: '镀铬镜面',
  glass: '玻璃',
  fabric: '织物',
  paper: '纸质',
  wood: '木质',
  stone: '石材',
  liquid: '液体',
  translucent: '半透明',
  rubber: '橡胶',
  ceramic: '陶瓷',
});

export const TEXTURE_CN = cn({
  grain: '胶片颗粒',
  noise: '噪点肌理',
  paper_grain: '纸纹',
  halftone: '半调网点',
  glitch: '故障纹理',
  scanline: '扫描线',
  risograph: '孔版印刷质感',
  none: '',
});

export const TYPEFACE_CN = cn({
  grotesque_sans: '中性无衬线体',
  geometric_sans: '几何无衬线体',
  humanist_sans: '人文无衬线体',
  serif: '衬线体',
  slab_serif: '粗衬线体',
  display: '装饰标题体',
  script: '手写体',
  calligraphy: '书法体',
  mono: '等宽体',
  none: '',
});

export const WEIGHT_CONTRAST_CN = cn({
  none: '',
  low: '字重层级平缓',
  medium: '字重层级明确',
  extreme: '字重反差极大',
});

export const STROKE_WEIGHT_CN = cn({
  hairline: '发丝级细线',
  thin: '细线条',
  medium: '中等线宽',
  bold: '粗线条',
  ultra_bold: '超粗线条',
  none: '',
});

export const ALIGNMENT_CN = cn({
  grid: '严格网格对齐',
  centered: '居中排版',
  left: '左对齐',
  right: '右对齐',
  justified: '两端对齐',
  free_scatter: '自由错落排版',
  none: '',
});

export const POSITION_CN: Record<string, string> = {
  center: '画面中央',
  left: '画面左侧',
  right: '画面右侧',
  top: '画面上方',
  bottom: '画面下方',
  top_left: '画面左上',
  top_right: '画面右上',
  bottom_left: '画面左下',
  bottom_right: '画面右下',
  lower_third: '画面下三分之一处',
  upper_third: '画面上三分之一处',
  none: '',
};

export const NEGATIVE_REGION_CN: Record<string, string> = {
  top: '画面上部',
  bottom: '画面下部',
  left: '画面左侧',
  right: '画面右侧',
  center: '画面中央',
  middle_band: '画面中部横向带状区域',
  top_left: '画面左上',
  top_right: '画面右上',
  bottom_left: '画面左下',
  bottom_right: '画面右下',
  upper_third: '画面上三分之一',
  lower_third: '画面下三分之一',
  surrounding: '主体四周',
  none: '',
};

export const SAFE_AREA_CN: Record<string, string> = {
  top_third: '画面上方三分之一',
  bottom_third: '画面下方三分之一',
  left_half: '画面左半部',
  right_half: '画面右半部',
  center: '画面中央',
  upper_left: '画面左上区域',
  upper_right: '画面右上区域',
  lower_left: '画面左下区域',
  lower_right: '画面右下区域',
  none: '',
};

export const PURPOSE_CN: Record<string, string> = {
  web_hero: '网页 Hero 主视觉',
  poster: '海报',
  wechat_cover: '微信公众号头图',
  xhs_cover: '小红书封面',
  banner: '横幅 banner',
  background: '背景图',
  ppt: 'PPT 配图',
  social_card: '社交卡片',
};

/**
 * 形态语言 → 可执行的形态描述。
 *
 * 这是 references/design-styles.md「形态词避坑」的代码化：几何圆角和有机液态是两种气质，
 * 单写「液态/流动/膨胀」会被生图模型理解成有机波浪泡泡形态。所以几何类形态必须
 * 主动带上排除句，不能只说想要什么。
 */
export const GEOMETRY_CN: Record<string, string> = {
  geometric_hard: '严格几何形态，平直边缘、锐利转角',
  geometric_rounded: '几何形态配大半径圆角，平直边缘、饱满但硬朗，不要波浪形有机曲线',
  organic_fluid: '有机流动形态，连续曲率、液态感轮廓',
  organic_irregular: '有机不规则形态，手绘感边缘',
  angular_sharp: '尖锐棱角形态，硬边切割',
  mixed: '几何与有机形态混用',
  none: '',
};

export const EDGE_CN: Record<string, string> = {
  straight: '边缘平直',
  large_radius_rounded: '大半径圆角',
  small_radius_rounded: '小半径圆角',
  wavy: '波浪起伏边缘',
  irregular: '不规则边缘',
  none: '',
};

/**
 * geometry 的描述里已经含了哪些 edge 的信息。
 * 命中的 edge 不再重复输出——否则会编出「平直边缘、锐利转角，边缘平直」这种自我重复。
 */
export const EDGE_IMPLIED_BY: Record<string, string[]> = {
  geometric_hard: ['straight'],
  geometric_rounded: ['large_radius_rounded', 'straight'],
  organic_fluid: ['wavy'],
  organic_irregular: ['irregular'],
  angular_sharp: ['straight'],
  mixed: [],
  none: ['none'],
};

/** 光影描述无意义的媒介：纯平面设计不模拟光源，写进提示词只会把模型推向渲染感。 */
export const FLAT_MEDIA = ['graphic_design', 'typography_poster', 'vector_illustration', 'collage'];

/** 判定某个形态枚举属于「几何」还是「有机」阵营，供 lint L2 使用。 */
export const GEOMETRY_CAMP: Record<string, 'geometric' | 'organic' | 'neutral'> = {
  geometric_hard: 'geometric',
  geometric_rounded: 'geometric',
  angular_sharp: 'geometric',
  organic_fluid: 'organic',
  organic_irregular: 'organic',
  mixed: 'neutral',
  none: 'neutral',
};

export const EDGE_CAMP: Record<string, 'geometric' | 'organic' | 'neutral'> = {
  straight: 'geometric',
  large_radius_rounded: 'geometric',
  small_radius_rounded: 'geometric',
  wavy: 'organic',
  irregular: 'organic',
  none: 'neutral',
};

/**
 * 禁止项 → 正向表述。
 * 模型对否定词不敏感，「没有杂物」不如「纯色极简背景」。查不到映射的不硬编，
 * 转而落到 notes 建议填平台负向词框——编出一句模型听不懂的否定句是净损失。
 */
export const POSITIVE_REWRITE: Array<{ match: RegExp; positive: string }> = [
  { match: /杂物|杂乱|凌乱/, positive: '纯色极简背景，画面整洁' },
  { match: /人物|人像|真人/, positive: '画面仅有产品与环境' },
  { match: /文字|字体|标题/, positive: '纯画面构图，无排版元素' },
  { match: /logo|标志|品牌/i, positive: '产品表面素净无标识' },
  { match: /阴影|投影/, positive: '均匀布光，接触面轻柔过渡' },
  { match: /反光|高光过曝/, positive: '哑光表面，柔光箱漫射打光' },
  { match: /模糊|虚化/, positive: '全画面清晰锐利，大景深' },
  { match: /饱和|艳丽|花哨/, positive: '低饱和克制配色' },
  { match: /渐变/, positive: '纯色平涂色块' },
  { match: /手|手部/, positive: '产品独立呈现，无肢体入镜' },
];
