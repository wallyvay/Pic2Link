# Pic2Link App Icon

## Design DNA

- 情感承诺：图片被安静、准确地送达，链接立即可用。
- 产品世界：一个常驻菜单栏的轻量传送口，不是照片编辑器或 AI 创作工具。
- 核心母题：图片框的右上角连续延伸为链环，把“图片 → 链接”合成一个符号。
- 颜色来源：深墨蓝代表可靠的后台工具，水青色代表正在建立的链接，暖白代表用户内容。
- 反目标：不使用星光、魔法感、金黑奢华、重复边框、独立上传箭头或额外链条徽章。

## 当前资产

- `AppIcon-transparent-master.png`：带透明外缘的最终母版。
- `AppIcon-chroma-master.png`：用于透明边缘处理的色键中间稿。
- `AppIcon-generated-master.png`：第一轮无透明外缘的生成母版，仅作设计过程留档。
- `icon-source-legacy.svg`：旧版黑金多符号图标源稿，仅作历史留档。
- App 内实际使用的 1024px 母版：`../Pic2Link/Resources/icon.png`。
- Asset Catalog 尺寸：`../Pic2Link/Assets.xcassets/AppIcon.appiconset/`。

## 最终生成提示词

```text
Use case: logo-brand
Asset type: final 1024 x 1024 macOS app icon master for Pic2Link, a menu bar utility that uploads a clipboard or dragged image and returns a shareable link
Primary request: create one original, memorable icon where a large photographic picture frame and a single chain-link / transfer opening are fused into one continuous symbol; the upper-right corner of the picture frame should naturally lift and morph into one clean link loop, expressing image-to-link in one glance
Scene/backdrop: a single deep ink-blue rounded-square macOS icon tile filling the square canvas, with no separate outer frame
Subject: one large centered warm off-white photo tile silhouette with a very simple mountain-and-sun cutout; its upper-right stroke becomes a restrained aqua link loop / upward transfer gesture
Style/medium: highly polished native macOS app icon, tactile precision-molded material, subtle dimensional lighting, crisp silhouette, restrained depth
Composition/framing: centered, bold, generous internal padding, readable at 16 px; one dominant fused mark and no secondary badges
Color palette: deep ink navy #0B2236, warm paper #F4F0E6, clear aqua #35C8C1
Constraints: no text, no letters, no watermark, no logos, no mockup device, no stars, no sparkles, no magic effects, no separate upload arrow, no separate chain badge, no double border, no gold, no excessive glow, no tiny details
```

生成方式：Codex 内置 `image_gen`；外缘通过纯色键与本地 Alpha 清理流程处理，并以 16、64、1024px 检查识别度和边缘质量。
