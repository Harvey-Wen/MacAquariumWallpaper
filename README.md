# 透明海洋

macOS 14+ 本地菜单栏应用：在现有壁纸上叠加游鱼、水纹和气泡。使用原生 AppKit / Metal，无第三方运行时、网络请求或在线服务。

## 运行

```bash
bash scripts/build.sh
open build/MacAquariumWallpaper.app
```

本地应用：`build/MacAquariumWallpaper.app`。启动后在菜单栏找到鱼形图标。

- **显示海洋**：开关整层效果，原壁纸继续由系统显示。
- **暂停游动 / 继续游动**：冻结或恢复鱼群，保留当前画面。
- **鼠标互动**：开启后，在露出的桌面点击会产生涟漪并惊散附近鱼儿；按住左键拖动会拨动水流，鱼群避让后逐渐恢复。
- **水纹强度**：轻柔、标准、明显三个级别。
- **退出透明海洋**：关闭全部特效窗口和输入监听。

初始包含 18 条银蓝群游鱼、4 条小丑鱼、3 条蓝吊鱼、3 条蝶鱼、1 只蝠鲼。不同种类有独立轮廓、花纹、摆尾和鳍部动画；鱼身为程序化立体网格。

## 桌面与权限

应用不设置系统壁纸，也不读取或重绘壁纸图片。没有生物和特效的地方完全透明；水纹是透明亮纹与涟漪，不是对壁纸像素进行真实折射。

窗口位于壁纸上方、桌面图标与普通应用下方，由 macOS 自然合成。窗口不抢焦点、不拦截鼠标；桌面图标仍可点击、拖动和框选。普通应用区域中的操作会被交互过滤。半透明系统窗口可以像透出原壁纸一样透出海洋效果。

仅观察鼠标事件和公开窗口矩形，不监听键盘、不采集屏幕像素、不发送信息。启动不请求辅助功能或屏幕录制权限。若输入监听或桌面几何不可用，停止相关鼠标互动，鱼群仍可自然游动。

首版仅渲染主屏，主屏尺寸变化后自动重新布局。休眠、锁屏停止绘制；唤醒尊重已有暂停状态。系统启用“减少动态效果”时静止显示。默认 30 FPS；没有自动添加登录项或修改系统设置。

## 验证

```bash
bash scripts/test-simulation.sh
bash scripts/test-input.sh
bash scripts/test-renderer.sh
bash scripts/test-desktop.sh
```

最后一项会短暂创建真实桌面覆盖层，以检查窗口层级、透明设置、暂停/关闭/恢复及系统壁纸配置。渲染测试会在 `.build/render-validation/` 生成透明及深浅底合成样张。

可选人工验证窗口：

```bash
bash scripts/build-fixture.sh
open build/DesktopFixture.app
```

它仅用于测试普通窗口点击和系统全屏，结束后点击“结束验证”。不随海洋应用打包。

诊断运行（先退出已有海洋实例）：

```bash
build/MacAquariumWallpaper.app/Contents/MacOS/MacAquariumWallpaper \
  --diagnostics "$PWD/build/runtime.json"
```

诊断文件只包含帧计数、模拟数量、输入计数和窗口属性，不包含屏幕内容或键盘输入。验证结果与未覆盖的环境记录于 [验收记录](docs/verification.md)。

当前为本地 ad-hoc 签名构建，未公证或对外发布。构建脚本优先采用本机现有 macOS 15.5 SDK，避免默认 SDK 与 Swift 编译器版本不匹配；没有该 SDK 时使用系统默认 SDK。

视觉与交互参考：[Chase Lean 的原视频](https://x.com/chaseleantj/status/2100663203076128908) 与 [Desktop Habitats](https://github.com/chaseleantj/desktop-habitats)。此实现独立编写，未运行参考项目安装器，也未复制其整缸背景。
