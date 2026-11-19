# JoyHarness 品牌资源

参考同级 RcHarness 的深色底板、控制器和指令气泡。当前版以小尺寸辨识为优先：放大蓝红手柄、减少倾斜、拉开两只手柄的间隔，`>_` 完整露出并加粗；去掉内圈、细高光与叠层阴影。方向键用十字概括，体现操控语义，不是硬件按钮排布图。

- 左手柄：明亮青蓝 `#19C7E9`，大面积纯色。
- 右手柄：珊瑚红 `#FF6375`，大面积纯色。
- 背景：深靛色轻渐变 `#303552` → `#171A2D`。
- 气泡：明亮薰衣草紫 `#D6CDFF` → `#B6A8EF`，保持与背景的明暗分离。
- 指令符号：深靛 `#25263F`，32 单位笔画；手柄控件为统一墨色 `#18243A`。

16/32 pt 图标使用专门简化的源图，删除底部功能键、加减号和信号线。主体轮廓保持一致，缩小后减少细碎像素；64 px 以下的代表尺寸均做了实际尺寸检查。

## 文件

- `joyharness-icon.svg`：1024 × 1024 可编辑应用图标源稿。
- `joyharness-icon.png`：1024 × 1024 应用图标，底板外透明。
- `joyharness-icon-small.svg` / `.png`：从主 SVG 派生的小尺寸简化版。
- `JoyHarness.icns`：macOS 的 16–1024 px 十档图标，Finder、Dock 和关于页共用。
- `joyharness-mark.svg` / `.png`：单色透明标志，PNG 为 512 × 512。
- `preview.png`：主图标、单色标志、菜单栏和小尺寸效果。
- `color-comparison.png`：灰紫旧版与清晰新版，以及 96/64/32/16 px 实际尺寸对照。
- `archive/v1/`：原始双手柄图标与绘制脚本。
- `archive/v2-ice-blue/`：冰白气泡版 SVG 源稿。
- `archive/v3-muted-lavender/`：灰紫气泡版源稿和 PNG。

菜单栏由 `Sources/JoyHarness/BrandAssets.swift` 提供 18 pt 模板图像，保留双手柄、指令气泡和信号线，自动适配系统浅色、深色与选中状态。

## 重建

```bash
scripts/build_brand.sh
```

设计资源通过手工 SVG 绘制。重建需要 macOS Quick Look、ImageMagick、Swift 和 iconutil；普通应用构建直接使用已保存的资源，不依赖 ImageMagick。

`generate_icon.swift` 从 PNG 生成固定像素尺寸的十档 iconset，不依赖显示器的 Retina 缩放倍率。16/32 pt 的 1x 和 2x 均使用小尺寸源图；其余尺寸使用完整源图。主 SVG 中标记 `data-detail="large"` 的组在重建时从小尺寸源图移除。
