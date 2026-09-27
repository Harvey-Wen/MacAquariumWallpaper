# 池塘

macOS 14+ 本地菜单栏应用：在主屏桌面显示固定俯视的自然池塘、约 30 条锦鲤、水波与落叶。使用原生 AppKit / Metal；运行时无需网络或音频。

## 运行

```bash
bash scripts/build.sh
open build/MacAquariumWallpaper.app
```

应用路径：`build/MacAquariumWallpaper.app`。启动后在菜单栏找到鱼形图标。菜单提供：

- **显示池塘**：显示或隐藏桌面场景。
- **暂停游动 / 继续游动**：冻结或恢复鱼、雨、水波和落叶。
- **鼠标互动**：开启后，点击露出的桌面池水会产生涟漪，附近锦鲤短暂散开后恢复游动。岸上点击不会产生水波。
- **天气 → 晴天 / 雨天**：切换天气。雨量随模拟时间渐变；暂停时可选择天气，恢复后继续过渡。
- **退出池塘**：关闭场景窗口和输入监听。

场景使用内置的 1600×1000 池塘底图，按主屏比例居中铺满；不同屏幕比例会裁切外围景物。锦鲤、水波和落叶由程序实时绘制。底图来源与处理方式见 [视觉素材说明](docs/concepts/README.md)。

## 桌面与权限

场景覆盖桌面壁纸，位于桌面图标和普通应用下方。窗口不抢焦点、不拦截鼠标；图标和应用继续接收输入。应用不修改系统壁纸设置。普通应用或系统界面中的点击会被过滤；输入监听或桌面几何不可用时停止相关互动。

应用只观察鼠标事件和公开窗口矩形，不监听键盘、不采集屏幕像素、不发送信息。启动不请求辅助功能或屏幕录制权限。首版仅渲染主屏；主屏尺寸变化后重新布局。休眠、锁屏停止绘制，唤醒尊重暂停状态；系统启用“减少动态效果”时静止显示。目标帧率为 30 FPS。

## 验证

```bash
bash scripts/test-simulation.sh
bash scripts/test-input.sh
zsh scripts/test-renderer.sh
bash scripts/test-desktop.sh
```

桌面测试会短暂创建覆盖层，检查层级、鼠标穿透、天气、暂停、恢复及壁纸设置。渲染测试在 `.build/render-validation/` 生成实际 Metal 帧；`zsh scripts/test-renderer.sh --preview` 还会生成动态预览。测试图不是用户壁纸截图。实测结果和未覆盖的人工操作见 [验收记录](docs/verification.md)。

诊断运行需先退出已有实例：

```bash
build/MacAquariumWallpaper.app/Contents/MacOS/MacAquariumWallpaper \
  --diagnostics "$PWD/build/runtime.json"
```

诊断文件只包含帧计数、鱼/落叶/水波数量、天气、输入计数及窗口属性。当前为本地 ad-hoc 签名构建，未公证或对外发布。
