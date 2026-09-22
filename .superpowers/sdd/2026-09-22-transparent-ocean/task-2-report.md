# Task 2 report: 运动与交互模拟

实现 `OceanSimulation`：固定种子生成 29 只五种鱼，按物种区分尺寸、速度与转向；更新包含松散群游、按鱼身分离、稳定游动和按制动距离提前介入的软边缘力。银鱼保留群游倾向，彩色鱼弱化同类凝聚以避免长期重叠成团。点击按距离施加惊吓与背离冲量并限制交互速度，悬停和拖动产生局部避让，波纹与水流均有数量和生命周期上限，resize 按屏幕比例迁移状态。

验证命令：`./scripts/test-simulation.sh`

输出：`SimulationTests: 9 passed`

测试覆盖物种数量与确定性、鱼体尺寸、点击近强远弱、连续精确点击后的有限速度、涟漪/水流上限、拖动结束衰减、30/5 FPS 等时长一致、0.5 秒更新不丢时间、受扰鱼软转向避开硬边界、60 秒模拟有限且有界、累计摆尾相位折返、resize 坐标缩放和 `OceanFrame` 快照。脚本固定使用可用的 macOS 15.5 SDK 与 macOS 14 arm64 目标。

局限：行为参数为首版视觉调校值；透明合成、实际鼠标采样节奏和鱼群观感仍需 App 集成后实机确认。

实现提交：

- `477bb9d feat: add deterministic fish simulation`
- `e6a1697 fix: stabilize fish motion across interactions`
