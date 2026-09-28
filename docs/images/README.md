# README 效果图

[返回项目首页](../../README.md)

这些素材于 2026-09-28 使用应用源码版本 `339a0c6` 生成。发布准备只改动文档与展示素材，没有改动产品渲染逻辑。

| 文件 | 内容与来源 |
| --- | --- |
| `pond-rainy.png` | 1600 × 1000，当前 Metal 渲染器输出的雨天池塘 |
| `pond-sunny.png` | 相同渲染器的晴天场景 |
| `pond-snowy.png` | 相同渲染器的下雪与积雪场景 |
| `pond-overcast.png` | 相同渲染器的阴天场景 |
| `pond-cloudy.png` | 相同渲染器的多云场景 |
| `cursor-interaction.gif` | `pond-cursor-preview.gif` 的原始副本，晴天、脚本化鼠标路径、15 FPS、4 秒循环 |
| `drawing-editor.png` | 实际 AppKit 绘画窗口内容，使用临时示例名字和笔迹，未写入个人鱼库 |
| `fish-list.png` | 实际 AppKit 鱼列表内容，30 条默认鱼和 2 条测试手绘鱼 |

场景图使用 `zsh scripts/test-renderer.sh --preview` 生成；鱼列表图使用 `bash scripts/test-fish-list-window.sh` 生成。绘画图通过实例化实际 `FishDrawingWindowController`、发送测试绘画事件并导出原生视图生成，展示的是产品已有控件。所有图片均未进行重绘或添加虚构界面。

环境底图由 AI 工具生成并作为资源随应用打包；鱼、水波、雨雪、云影与浮叶由程序合成。这里的运行效果图与 [历史概念图](../concepts/README.md) 分开保存。

这些图片不包含个人桌面、个人鱼库或壁纸恢复文件。离屏渲染与原生视图图像不能证明系统菜单栏、桌面图标层级和所有 Space 的最终合成效果。
