# Codex 额度小组件

一个常驻 Windows 任务栏空白区的小组件，实时显示：

- `5h`：Codex 5 小时窗口剩余额度
- `周`：Codex 周窗口剩余额度

它通过 Codex 官方本地 `app-server` 接口读取额度，不读取、不复制 `auth.json` 中的令牌。

## 安装

1. 确保 Codex 桌面端或 Codex CLI 已安装，并已使用 ChatGPT 账号登录。
2. 双击 `安装.cmd`。
3. 小组件会立即启动，并写入当前用户的 Windows“启动应用”；以后登录 Windows 时会自动启动。

默认固定在任务栏左侧天气组件的右边。直接拖动小组件可微调横向位置；右键可以立即刷新、重新固定到天气旁边、切换中文/English 或退出。语言和位置选择会自动保存。鼠标悬停会显示额度重置时间和最后更新时间，双击会立即刷新。

## 卸载

双击 `卸载.cmd`。

## 从源码构建

在 Windows PowerShell 中运行：

```powershell
.\build.ps1
```

构建结果位于 `dist`。项目使用 Windows 自带的 .NET Framework 4.x 编译器，不需要额外安装 .NET SDK。

## 故障排查

- 显示“额度暂不可用”：先打开 Codex 并确认已登录，然后右键选择“立即刷新”。
- 找不到 Codex：可将 `CODEX_EXE` 环境变量设置为 `codex.exe` 的完整路径。
- 百分比含义：界面显示的是“剩余”额度；官方接口返回的是“已用”额度，小组件进行了 `100 - usedPercent` 换算。
