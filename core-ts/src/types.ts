/** StyleSpec v0.1 / Brief v0.1 的 TypeScript 镜像。权威定义在 schema/*.json，此处只为编译期便利。 */

export type AdType =
  | 'hero_shot' | 'lifestyle' | 'mood_poster' | 'background' | 'promo_banner' | 'concept' | 'other';

export type Medium =
  | 'photography' | '3d_render' | 'vector_illustration' | 'raster_illustration'
  | 'graphic_design' | 'typography_poster' | 'collage' | 'mixed_media' | 'other';

export type Geometry =
  | 'geometric_hard' | 'geometric_rounded' | 'organic_fluid' | 'organic_irregular'
  | 'angular_sharp' | 'mixed' | 'none';

export type Edge =
  | 'straight' | 'large_radius_rounded' | 'small_radius_rounded' | 'wavy' | 'irregular' | 'none';

export interface StyleFamily {
  name: string;
  name_en: string;
  confidence: number;
  evidence: string;
  role?: 'primary' | 'borrowed';
}

export interface StyleSpec {
  schema_version: '0.1';
  source: {
    path?: string | null;
    url?: string | null;
    analyzed_at: string;
    analyzer: string;
    temporary?: boolean;
  };
  ad_type: AdType;
  medium: Medium;
  medium_detail?: string;
  style_family: StyleFamily[];
  /** 内容层隔离区。本块内容禁止出现在 style_dna 中。 */
  content: {
    subject: string;
    scene: string;
    brand_marks: string[];
    on_image_text: Array<{ text: string; position: string; role?: string }>;
    keywords: string[];
  };
  composition: {
    shot: 'extreme_close_up' | 'close_up' | 'medium' | 'wide' | 'extreme_wide';
    angle: 'eye_level' | 'low_angle' | 'high_angle' | 'top_down' | 'dutch';
    aspect_ratio: string;
    subject_position: string;
    subject_coverage: number;
    negative_space: { region: string; ratio: number; note?: string };
    grid?: string;
    density: 'sparse' | 'low' | 'medium' | 'high' | 'saturated';
    bleed?: boolean;
    layers?: number;
    symmetry?: 'symmetric' | 'asymmetric_balanced' | 'asymmetric_dynamic';
    visual_flow?: string;
  };
  palette: Array<{ hex: string; ratio: number; role: 'base' | 'secondary' | 'accent'; name_cn?: string }>;
  color: {
    saturation: 'desaturated' | 'low' | 'medium' | 'high' | 'hyper';
    temperature: 'cool' | 'neutral' | 'warm' | 'mixed';
    contrast: 'flat' | 'low' | 'medium' | 'high' | 'extreme';
    harmony?: string;
    brightness_key?: 'low_key' | 'mid_key' | 'high_key';
  };
  lighting: {
    direction: 'front' | 'side' | 'back' | 'top' | 'bottom' | 'ambient' | 'mixed';
    quality: 'soft' | 'hard' | 'mixed';
    contrast: 'flat' | 'low' | 'medium' | 'high' | 'dramatic';
    sources?: string[];
    time_of_day?: string | null;
    note?: string;
  };
  material: {
    surfaces: Array<{ where: string; finish: string; detail?: string }>;
    texture_overlay?: string[];
  };
  form_language: {
    geometry: Geometry;
    edge: Edge;
    corner_radius_note?: string;
    stroke_weight?: string;
    repetition?: string;
    gap_rule?: string;
  };
  typography: {
    present: boolean;
    typeface_class?: string;
    weight_contrast?: string;
    size_hierarchy?: string[];
    alignment?: string;
    case?: string;
    safe_area?: string;
    note?: string;
  };
  mood: string[];
  use_cases?: string[];
  style_dna: string;
  style_dna_en?: string | null;
  content_leakage?: Array<{ field: string; phrase: string; severity: 'low' | 'medium' | 'high' }>;
  confidence: { overall: number; uncertain_fields: string[] };
  notes?: string;
}

export interface EditIntent {
  scope_anchor: string;
  protect: Array<{ element: string; original_content: string }>;
  replace: Array<{ target: string; new_content: string }>;
  merge_requirements?: string | null;
}

export interface Brief {
  schema_version: '0.1';
  purpose: string;
  aspect_ratio: string;
  subject: string;
  subject_detail?: string;
  action?: string | null;
  scene?: string | null;
  copy?: { title?: string | null; subtitle?: string | null; body?: string | null };
  copy_safe_area?: string;
  render_text_in_image?: boolean;
  must_keep?: string[];
  must_avoid?: string[];
  refs?: { style?: string | null; composition?: string | null; subject?: string | null };
  edit?: EditIntent;
  quality_words?: string[];
  variants?: number;
  notes?: string;
}

export type ModelId = 'jimeng' | 'gpt-image';

/** 垫图编辑指令的四个部件。任一为空即拒绝产出——缺失在编译期失败，而不是事后扫字符串。 */
export interface EditParts {
  scope: string;
  protect: string;
  replace: string;
  noAddNoRemove: string;
}

export interface CompiledPrompt {
  model: ModelId;
  aspect_ratio: string;
  /** 文生图 */
  text2img: string | null;
  /** 垫图局部编辑（受边界四纪律约束）。仅在 brief.edit 存在时产出。 */
  img2img_edit: string | null;
  /** 垫图风格参考：上传原图 + 点名要保持的形态特征。形态这类只可意会的特征，让模型看一眼原图比纯文字准。 */
  img2img_style_ref: string | null;
  /** 参考槽协议：明确告诉模型从哪张图参考什么，避免多图互相污染。 */
  ref_protocol: string | null;
  notes: string[];
  /** 供 lint L3 检查的结构化部件 */
  parts: { edit: EditParts | null };
}
