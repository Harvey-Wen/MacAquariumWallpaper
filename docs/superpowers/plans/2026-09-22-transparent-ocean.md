# Transparent Ocean Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development to implement the bounded simulation/rendering tasks alongside desktop integration. Steps use checkbox syntax for tracking.

**Goal:** 在现有 macOS 壁纸上运行可点击惊散、拖动扰动的透明海洋鱼群。

**Architecture:** AppKit 主屏透明窗口和 Metal 渲染；纯 Swift 模拟维护鱼群与涟漪；只读鼠标监听输入并排除普通应用区域。每个模块独立验证再提交。

**Tech Stack:** Swift 5、AppKit、MetalKit、Metal Shading Language、CoreGraphics。macOS 14+，无第三方依赖。

## Global Constraints

- 不设置系统壁纸，不绘制背景底色，不拦截鼠标，不监听键盘，不主动请求辅助功能或录屏权限。
- 初始 29 只、五种鱼；主屏 30 FPS；暂停冻结、关闭隐藏、退出清理。
- 普通应用、Dock、菜单区域的输入不触发鱼群交互；真实系统合成不采用窗口矩形裁剪。
- 此次确认同时授权建立 CodeGraph 索引。

## Task 1: 数据接口与桌面骨架

Files: `Sources/OceanTypes.swift`, `Sources/App.swift`, `Sources/DesktopController.swift`, `Resources/Info.plist`, `scripts/build.sh`.

- [ ] 定义统一点坐标（主屏左下原点）、五种 FishSpecies、FishState、Ripple、CurrentStroke 和 OceanFrame。
- [ ] 使用 NSWindow 无边框桌面层、clear 背景、鼠标穿透、禁止 key/main；失败时保持桌面透明。
- [ ] 构建签名本地 app，验证窗口属性和原壁纸未改变；提交。

接口：`OceanFrame(size: SIMD2<Float>, time: Float, fish: [FishState], ripples: [Ripple], currents: [CurrentStroke], waterStrength: Float)`；`OceanSimulation(size:seed:)`，`update(deltaTime:)`、`pointerMoved(to:)`、`click(at:)`、`drag(to:)`、`endDrag()`、`resize(to:)`、`frame(waterStrength:)`。

## Task 2: 运动与交互模拟

Files: `Sources/OceanSimulation.swift`, `Tests/SimulationTests.swift`, `scripts/test-simulation.sh`.

- [ ] 先测试 29 只五种鱼、点击近强远弱、拖动结束可衰减、长时间有界且有限、resize 坐标正确。
- [ ] 以速度/加速度、同类群游分离和软边缘力实现游动，受惊衰减后回到正常速度；波纹/水流设上限。
- [ ] 运行纯 Swift 测试通过；提交。

## Task 3: 原生鱼群与水纹渲染

Files: `Sources/OceanRenderer.swift`, `Sources/FishMesh.swift`, `Resources/Ocean.metal`, `Tests/RenderTests.swift`, `scripts/test-renderer.sh`.

- [ ] 透明 MTKView / CAMetalLayer + 清屏 RGBA(0,0,0,0)，预乘 alpha 混合；加载随 app 打包的 shader 源码。
- [ ] 绘制五种程序化立体鱼（鱼体、尾鳍、胸鳍、眼睛），按 time/phase/speed 摆尾，蝠鲼使用起伏翼面。
- [ ] 绘制低 alpha 焦散和扩散涟漪、拖动尾流、气泡；无沙地、整屏蓝色或背景图。
- [ ] 离屏透明像素与彩色底图合成验证；检查实际样张，迭代后提交。

接口：`OceanRenderer(view: MTKView, shaderURL: URL) throws`，可写 `frame: OceanFrame`，`draw(in:)`，离屏导出方法供测试调用。不在渲染器中读取真实桌面输入。

## Task 4: 桌面输入和生命周期

Files: `Sources/DesktopInput.swift`, `Sources/DesktopController.swift`, `Sources/App.swift`, `Tests/InputTests.swift`, `scripts/test-input.sh`.

- [ ] 只监听 leftMouseDown/Dragged/Up；坐标来自事件，悬停位置轮询。只允许从桌面开始的拖动。
- [ ] 用 CG 窗口矩形排除普通窗口、Finder 文件窗口，屏幕 visibleFrame 排除 Dock/菜单基础区域，处理事件位置和跨屏退出；测试正负坐标与过滤。
- [ ] 菜单提供开启、暂停、交互、水纹强度、退出；休眠/唤醒、主屏变化、减少动态效果正确恢复。
- [ ] 真实运行检查桌面层级和输入；提交。

## Task 5: 交付验收

Files: `README.md`, `docs/verification.md`, planning files.

- [ ] 构建和测试运行完成；实机观察透明效果、鱼种、菜单、点击、拖动、普通应用避让。
- [ ] 记录帧率/CPU/内存、持续运行、已验证与未覆盖的系统场景。
- [ ] 用户可直接打开本地 app，交付使用方式；更新 CodeGraph 和 Git。
