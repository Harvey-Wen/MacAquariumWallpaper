# Task 2 report: 运动与交互模拟

实现 `OceanSimulation`：固定种子生成 29 只五种鱼，按物种区分尺寸、速度与转向；更新包含同类聚群、分离、稳定游动和软边缘力。点击按距离施加惊吓与背离冲量，悬停和拖动产生局部避让，波纹与水流均有数量和生命周期上限，resize 按屏幕比例迁移状态。

验证命令：`./scripts/test-simulation.sh`

输出：`SimulationTests: 6 passed`

测试覆盖物种数量与确定性、鱼体尺寸、点击近强远弱、涟漪/水流上限、拖动结束衰减、60 秒模拟有限且有界、resize 坐标缩放和 `OceanFrame` 快照。脚本固定使用可用的 macOS 15.5 SDK 与 macOS 14 arm64 目标。

局限：行为参数为首版视觉调校值；透明合成、实际鼠标采样节奏和鱼群观感仍需 App 集成后实机确认。

实现提交：`477bb9d feat: add deterministic fish simulation`
