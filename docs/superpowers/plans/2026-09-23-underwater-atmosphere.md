# 水下环境感增强 Implementation Plan

**Goal:** 保留原壁纸可见，隐藏鱼群后仍呈现水面、下射光和缓慢形变的背景焦散。

**Architecture:** 沿用 Metal 预乘透明合成，在现有水效通道中用一个覆盖视口的环境绘制替代七块局部亮纹。环境由独立时间相位驱动；鱼使用同一光纹与水色，不依赖鱼数量来开启水效。

**Tech Stack:** Swift、AppKit、Metal；现有本地构建脚本，无新增依赖。

## Global Constraints

- 保留系统原壁纸，不读取或重绘背景像素；光纹是透明光照模拟，不是真实背景折射。
- 用户已确认淡水色层，空白区域可半透明；关闭所有内容时 RGBA 仍为零。
- 沿用水纹强度 0.25 / 0.45 / 0.75；默认 30 FPS。
- 不改窗口层级、输入、模拟行为或增加其他生物、海床、控制项。
- GPU 时间使用 Double 计算后分别折返相位，避免长期运行精度和周期跳变。

## Task 1: 环境、鱼身受光与渲染回归

**Files:** Resources/Ocean.metal、Sources/OceanRenderer.swift、Sources/OceanTypes.swift、Tests/RenderTests.swift。

**Interfaces:** 保持 OceanFrame 的字段不变；.empty 改为 waterStrength: 0，表示真正空场景。水效使用现有 EffectUniforms.viewport.zw 两个相位，环境函数在着色器中共享；FishUniforms.kind.yzw 传递同样相位和强度。

- [ ] 先保留基线渲染测试结果，再用无鱼且 waterStrength: 0.45 的画面复现水效消失：

```swift
var waterOnly = OceanFrame.empty
waterOnly.waterStrength = 0.45
let pixels = try renderer.renderRGBA(frame: waterOnly, width: 640, height: 400)
precondition(stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 })
```

- [ ] 将背景水效改为与鱼数量无关的全视口绘制，保持气泡数量和交互上限；空场景水强度为零：

```swift
if frame.waterStrength > 0 {
    effect(at: frame.size * 0.5, radius: 1, type: 0,
           strength: min(frame.waterStrength, 1))
}
```

- [ ] 在 effectVertex 的 type == 0 分支直接以四角覆盖视口；effectFragment 生成顶部透视波纹、下射光、形变网状焦散与深度渐变水色，预乘 alpha 输出。所有周期项只通过 sin/cos 消费独立相位。
- [ ] 让 fishFragment 使用同一屏幕空间光纹与水雾；强度为零时维持既有鱼身渲染，避免破坏独立鱼动画测试。
- [ ] 回归无鱼水效、关闭归零、强度变化、背景可见、预乘 alpha、鱼动画、前后遮挡及第 7 天/周期边界连续性。
- [ ] 输出无鱼/含鱼、深色/浅色/复杂测试背景样张，并生成至少 10 秒动态预览人工检查；视觉不足则只调节环境参数和光纹。
- [ ] 运行 `zsh scripts/test-renderer.sh`，通过后提交本模块。

## Task 2: 桌面集成与交付

**Files:** README.md、docs/verification.md、task_plan.md、progress.md、findings.md。

- [ ] 执行 `bash scripts/test-simulation.sh`、`bash scripts/test-input.sh`、`bash scripts/test-desktop.sh` 和 `bash scripts/build.sh`。
- [ ] 独立审查修改的渲染逻辑与验收证据；修复真实缺陷并重跑对应检查。
- [ ] 将已验证提交快进到原工作目录；退出原应用实例、构建并启动新版，检查诊断中的持续帧计数、29 只鱼、输入和窗口属性。
- [ ] 更新说明：默认存在淡水色层，取消“无鱼处完全透明”的旧描述；真实背景折射仍不支持。说明新测试数据与未覆盖人工场景，不把历史性能数值当作本次测量。
- [ ] 提交交付文档，提供应用路径和效果预览。

## 自查

所有视觉项由 Task 1 覆盖，系统行为与交付由 Task 2 覆盖；未增加外部依赖和系统权限。现有渲染脚本使用 zsh，不能以 bash 运行，其余脚本沿用原解释器。
