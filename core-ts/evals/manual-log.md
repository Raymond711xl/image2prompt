# 人工评测记录

自动测试只能证明「提示词按规则编对了」，证明不了「生成结果像不像」。
这份记录负责后者：把 `i2p compile` 的产出贴到即梦 / 豆包 / GPT Image 网页，人工判断。

判断维度（逐项打 ✓ / ✗，✗ 要写清是哪个词把模型带偏的）：

| 维度 | 问题 |
|---|---|
| 风格保真 | 色彩关系、材质、光线、密度是否和参考图同一气质 |
| 形态正确 | 几何 / 有机有没有搞反（最常见的翻车点） |
| 内容洁净 | 有没有把参考图的具体物件、文字、品牌带出来 |
| 构图可用 | 主体占比、留白位置、文案安全区是否可直接用 |
| 编辑边界 | 垫图编辑有没有溢出到未点名的元素 |

改词重跑后，把有效的教训写回对应的 adapter 或 vocab 注释——skill 的修正是复利的。

---

## 待跑

以下组合已编译完成、自动检查全绿，等人工贴到平台验证：

| # | StyleSpec | Brief | 模型 | 状态 |
|---|---|---|---|---|
| 1 | `red-pixel-newyear-poster` | `glucose-meter-wechat-cover` | 即梦 | 待跑 |
| 2 | `red-pixel-newyear-poster` | `glucose-meter-wechat-cover` | GPT Image 2 文生图 | 待跑 |
| 3 | `red-pixel-newyear-poster` | `pixel-swap-edit` | GPT Image 2 垫图编辑 | 待跑 |
| 4 | `white-highkey-scale-hero` | `glucose-meter-wechat-cover` | 即梦 | 待跑 |
| 5 | `white-highkey-scale-hero` | `glucose-meter-wechat-cover` | GPT Image 2 文生图 | 待跑 |

第 3 条是边界控制四纪律的实战检验：只换中央图形，顶部/底部大字、两侧竖排小字、
底色都必须纹丝不动。编辑模型的「主题一致化」倾向就是在这种场景下暴露的。

---

## 已跑

（尚无）
