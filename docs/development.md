# 开发与验证

[返回首页](../README.md) · [使用指南](usage.md) · [参与贡献](../CONTRIBUTING.md)

## 构建方式

项目直接使用系统 Swift 编译器构建，没有 Swift Package Manager、CocoaPods 或其他包管理依赖，也不需要生成 Xcode 工程。

```bash
bash scripts/build.sh
codesign --verify --strict build/MacAquariumWallpaper.app
```

脚本按当前机器架构编译，最低部署版本为 macOS 14，使用 Swift 5 语言模式和优化构建。它优先使用已安装的 macOS 15.5 Command Line Tools SDK，否则使用 `xcrun` 选择的 SDK；编译器和 SDK 需要相互兼容。Metal 源码与环境图随 `.app` 打包，构建后进行本地 ad-hoc 签名。

本次验证环境：Apple M4 Max、macOS 15.7.4、Swift 6.1.2、macOS 15.5 SDK。部分验证脚本明确指定 arm64，Intel Mac 的测试兼容性尚未验证。

如果出现 SDK 与 Swift 版本不匹配，先检查 `xcode-select -p`、`xcrun swiftc --version` 和 `xcrun --sdk macosx --show-sdk-path`，使用同套开发工具提供的编译器与 SDK。

## 目录与职责

| 路径 | 职责 |
| --- | --- |
| `Sources/App.swift` | 应用入口与菜单栏操作 |
| `Sources/DesktopController.swift` | 桌面窗口、显示生命周期、场景与后台导出协调 |
| `Sources/DesktopBackdrop.swift` | 系统背景接管、恢复记录、目录独占与恢复确认 |
| `Sources/DesktopInput.swift` | 桌面鼠标观察、窗口遮挡过滤与几何缓存 |
| `Sources/OceanSimulation.swift` | 鱼群、水波、天气、落叶的模拟状态 |
| `Sources/OceanRenderer.swift` | Metal 渲染、纹理与粒子缓存、图像导出 |
| `Sources/FishMesh.swift` / `Sources/PondGeometry.swift` | 鱼形几何与池水区域 |
| `Sources/FishDrawing.swift` / `Sources/FishDrawingWindow.swift` | 手绘鱼数据、持久化与绘画窗口 |
| `Sources/FishListWindow.swift` | 外观预览、改名与删除 |
| `Sources/PerformanceMetrics.swift` / `Sources/OceanTypes.swift` | 有界性能统计与共享类型 |
| `Resources/` | 应用信息、Metal 着色器与池塘环境图 |
| `Tests/` / `scripts/` | 独立测试程序及构建、验证入口 |
| `docs/` | 使用说明、素材与历史设计/验收记录 |

## 运行测试

在项目根目录运行。原生窗口和 GPU 检查需要具有图形会话、可用 Metal 设备的 Mac，不应将无显示环境的结果当成桌面验收。建议顺序执行，避免多个窗口或 GPU 基准互相干扰。

基础检查：

```bash
bash scripts/test-simulation.sh
bash scripts/test-input.sh
bash scripts/test-drawing.sh
bash scripts/test-drawing-window.sh
bash scripts/test-fish-list-window.sh
zsh scripts/test-renderer.sh
```

专项检查：

| 命令 | 覆盖范围 |
| --- | --- |
| `zsh scripts/test-custom-fish-renderer.sh` | 手绘纹理与鱼体渲染 |
| `bash scripts/test-custom-fish-desktop.sh` | 新增、删除、重启与桌面集成 |
| `bash scripts/test-desktop.sh` | 窗口层级、穿透、暂停、恢复与异步背景 |
| `bash scripts/test-desktop.sh --weather-only` | 天气切换与残留粒子生命周期 |
| `bash scripts/test-backdrop.sh` | 所有权、跨进程竞争、崩溃、迟到与失败 |
| `zsh scripts/test-async-renderer.sh` | 异步 PNG 导出、并发与主线程响应 |
| `bash scripts/test-canvas-cache.sh` | 缓存画布与历史版本的像素一致性 |
| `bash scripts/test-diagnostics.sh` | 诊断结构、有界统计与慢帧记录 |
| `bash scripts/test-performance.sh` | 离屏读回、导出、模拟和画布耗时 |
| `bash scripts/test-display-performance.sh --baseline` | 历史版本正常显示基线 |
| `bash scripts/test-display-performance.sh` | 当前版本正常显示与资源测量 |

画布与显示基线测试会从 Git 读取历史源码。请使用完整克隆，保留提交历史；下载 ZIP 或浅克隆不足以运行所有历史对比测试。

普通桌面、天气和鱼群集成测试默认使用临时数据目录与模拟壁纸接口，不写个人鱼库、不更改真实壁纸。桌面测试会短暂创建覆盖层，原生窗口检查会打开独立测试窗口。

### 真实壁纸验收

仅在需要检查实际系统背景操作时执行：

```bash
bash scripts/test-desktop.sh --real-wallpaper
```

这项测试会操作真实壁纸。先正常退出应用；已有实例运行时会被独占保护拒绝。若原恢复信息缺失，应先由用户指定可信原图，不能靠测试推断。不要把纯模拟测试通过等同于所有 Space、动态壁纸和多显示器组合都已通过实机验收。

## 生成效果预览

```bash
zsh scripts/test-renderer.sh --preview
bash scripts/test-fish-list-window.sh
```

实际 Metal 帧和动态 GIF 写入 `.build/render-validation/`；列表图写入 `.build/fish-list-validation/`。预览采用确定的测试场景及脚本化鼠标路径，不是录制用户屏幕。测试会包含高负载、残留粒子和特殊比例样张，首页只选取代表正常效果的图片。

独立绘画窗口可通过以下命令打开，不写生产鱼库：

```bash
bash scripts/test-drawing-window.sh --fixture
open .build/DrawingEditorFixture.app
```

该夹具的保存结果位于 `.build/drawing-validation/`。

## 运行诊断

先从菜单正常退出已有实例，再运行：

```bash
build/MacAquariumWallpaper.app/Contents/MacOS/MacAquariumWallpaper \
  --diagnostics "$PWD/build/runtime.json"
```

诊断包括场景和输入计数、背景所有权与恢复状态、最近 300 个样本的 CPU/GPU 耗时、帧间隔、长帧及导出统计。正常显示 GPU 与离屏 GPU 分开统计；后台导出总时长与主线程提交时长分开统计，同时记录 Metal 分配、目标重建和雨雪上传分配。

性能结果需要注明设备、分辨率、场景、采样数量及是否有其他实例运行。离屏读回耗时、正常显示帧耗时、Metal 分配量、进程 RSS 和电池耗电量不能相互替代。已有数据与限制见[优化验收记录](optimization-acceptance-2026-09-28.md)。

历史设计和验收文件用于记录当时的状态；当前使用方式以首页和使用指南为准。
