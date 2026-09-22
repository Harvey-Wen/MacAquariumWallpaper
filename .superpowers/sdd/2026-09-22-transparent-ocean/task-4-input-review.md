# Task 4 输入模块审查与修复

审查及修复范围：`Sources/DesktopInput.swift`、`Tests/InputTests.swift`。未修改 App 层。

## 已修复问题

1. **窗口信息异常时 fail closed。** `DesktopWindowSnapshot.parse` 现在把空 records、缺少必需字段、非法 bounds 判为不可用，清除当前手势，不再用空 blocker 集合误放行应用窗口点击。
2. **系统全屏宿主采用窄豁免。** 仅豁免目标机已实际确认的 `Dock`、layer 20、覆盖屏幕至少 95% 的持久透明宿主。其他近全屏系统表面使输入暂时不可用；普通系统面板和实际 Dock 仍作为 blocker。系统 owner 同时支持目标机实际返回的 `Control Centre` 拼写。
3. **公开事件目标 PID 二次过滤。** 即使透明 Dock 宿主被几何规则忽略，只要事件目标 PID 属于 Dock、WindowManager、Window Server、Control Centre/Center、Notification Centre/Center 或 SystemUIServer，该事件仍不会触发鱼群。事件没有有效 target PID 时，本次事件保守拒绝。
4. **监听失败可观察。** `DesktopInput` 新增 `available` 和 `status`。`available` 只表示全局 mouse monitor 已安装且当前 geometry 可靠，与用户 `enabled` 开关独立；monitor 返回 `nil` 时状态为“全局鼠标监听不可用”，不请求权限。事件目标缺失时状态会说明本次交互已忽略。

## 接口变化

- `DesktopInput.available: Bool`
- `DesktopInput.status: String`

现有 `enabled`、回调、计数和 `geometry.valid` 行为保留。

## 验证

`bash scripts/test-input.sh`

输出：`PASS: 25 input geometry and gesture checks`

新增覆盖：正常 Finder 桌面与已确认 Dock layer-20 宿主仍可用；空快照和损坏记录 fail closed；未知近全屏 system host 抑制输入；系统事件目标 PID 被拒绝；target PID 缺失时拒绝；monitor 缺失时 `available == false` 且有明确状态。

## Spec compliance

**代码与纯策略测试通过。** 只监听左键 down/drag/up，不监听键盘，不吞原事件，不主动请求权限；坐标、普通窗口/Finder 文件窗口、菜单/Dock、拖动起点、异常恢复和 monitor 清理均有明确路径。窗口信息或事件目标不可靠时选择停用交互，不影响透明渲染。

## Code quality

**通过。** 窗口解析、事件目标策略、可用状态和手势状态保持为独立小结构；错误路径统一 fail closed，root 可直接把 `available/status` 接入菜单和诊断信息。

## 实机边界

公开 `CGEvent.eventTargetUnixProcessID` 在缺失时会安全拒绝，但尚未在真实 Mission Control、Launchpad 与所有 Space 切换状态中确认其具体 PID 返回。当前修复不能替代设计要求的实机验收；验收时应确认正常桌面事件仍指向 Finder，系统界面事件指向被屏蔽的系统 PID。若系统版本返回不同 owner/PID，现有策略会优先拒绝无法判定的近全屏系统表面，而不会请求 AX 权限或把其当桌面放行。
