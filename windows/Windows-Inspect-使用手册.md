# Windows 系统巡检脚本 使用手册

> 版本：v14
> 更新日期：2026-08-18
> 脚本文件：`windows-inspect-v14.ps1`

---

## 一、脚本简介

`windows-inspect-v14.ps1` 是一个**纯 PowerShell**实现的 Windows 系统巡检工具，特点：

- **完全离线**：所有图表（仪表盘、环形图、柱状图）都用纯 SVG 渲染，无任何外部 JS/CSS 库依赖
- **单文件输出**：生成的报告是单个自包含 HTML 文件，双击即可在浏览器查看
- **14 个章节**：系统概览 / 硬件资产 / CPU / 内存 / 磁盘 / 网络 / 进程 / 服务 / 安全 / 事件 / 任务 / 启动项 / 总结
- **左侧导航**：报告内置 sticky 导航，14 章节一键跳转，滚动自动高亮当前章节
- **路径自适应**：HTML 默认输出到脚本所在目录，可放在任意位置运行

---

## 二、快速上手（推荐）

### 方法一：双击运行（最简单）

1. 确认脚本在桌面：`C:\Users\Pengfei\Desktop\windows-inspect-v14.ps1`
2. 双击脚本
3. 如果弹出 Windows Defender 提示，选择「更多信息」→「仍要运行」
4. 等待 10-30 秒（取决于系统数据量）
5. 报告会自动生成在脚本同目录并用浏览器打开

### 方法二：PowerShell 命令行运行

按 `Win + X` → 选择「终端 (管理员)」或「PowerShell」：

```powershell
# 切换到桌面（或任意脚本所在目录）
cd $env:USERPROFILE\Desktop

# 执行脚本
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows-inspect-v14.ps1
```

执行后会看到：

```
[1/3] Collecting Windows system data...
[2/3] Generating HTML report...
[3/3] Report generated: C:\Users\Pengfei\Desktop\win_system_inspection_yyyyMMdd_HHmmss.html
```

---

## 三、首次运行：解除执行策略限制

如果双击运行没反应，先在 **管理员 PowerShell** 中执行一次：

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

输入 `Y` 确认即可。这只影响当前用户，不会修改系统级策略。

---

## 四、报告输出位置（v14 新逻辑）

**报告自动输出到脚本所在目录**（`$PSScriptRoot`），而不是写死到固定路径。

示例：

| 脚本位置 | 报告输出位置 |
|----------|--------------|
| `C:\Users\Pengfei\Desktop\windows-inspect-v14.ps1` | `C:\Users\Pengfei\Desktop\win_system_inspection_*.html` |
| `D:\Tools\windows-inspect-v14.ps1` | `D:\Tools\win_system_inspection_*.html` |
| `\\server\share\windows-inspect-v14.ps1` | `\\server\share\win_system_inspection_*.html` |

文件命名格式：`win_system_inspection_yyyyMMdd_HHmmss.html`

### 自定义输出目录（可选）

编辑脚本，找到 `$outDir` 行（约第 26 行）：

```powershell
# 默认：脚本同目录
$outDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

# 改为桌面（硬编码）
$outDir = $env:USERPROFILE + '\Desktop'

# 改为指定目录
$outDir = 'D:\Reports\WindowsInspect'
```

---

## 五、创建桌面快捷方式（进阶）

1. 在桌面右键 → 新建 → 快捷方式
2. 输入对象位置：

   ```
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\Desktop\windows-inspect-v14.ps1"
   ```

3. 命名为「一键巡检」
4. 双击图标即可执行

可设为开机自启动：把快捷方式复制到 `shell:startup` 目录。

---

## 六、报告内容速览

打开 HTML 报告后，左侧导航目录提供 14 个章节：

| #  | 章节         | 内容                                       |
|----|--------------|--------------------------------------------|
| 01 | 系统概览     | CPU/内存/磁盘/运行时长 4 个仪表盘 + 9 张卡片 |
| 02 | 硬件资产     | 制造商/型号/序列号 + CPU/内存/显卡/主板/BIOS |
| 03 | CPU 信息     | 型号/厂商/核心数/主频/缓存/虚拟化          |
| 04 | 内存信息     | 物理内存 + 页面文件使用情况                 |
| 05 | 磁盘分区     | 5 个分区使用率 + 表格                       |
| 06 | 物理磁盘健康 | 健康状态/型号/固件版本（Smart 数据）       |
| 07 | 网络         | TCP 状态环形图 + 流量柱状图 + 网卡列表     |
| 08 | 进程监控     | CPU/Memory Top 10 表格                      |
| 09 | 关键服务     | 服务列表 + 状态徽章                         |
| 10 | 安全审计     | Defender/UAC/防火墙状态 + 补丁列表         |
| 11 | 事件日志     | 最近 8 条错误事件 + 错误计数卡片            |
| 12 | 计划任务     | 非微软任务列表                              |
| 13 | 启动项       | 注册表启动项                                |
| 14 | 巡检总结     | 健康分仪表盘 + 危险数统计                   |

### 顶部 4 个 KPI 卡

- **CPU 使用率**（实时）
- **内存使用率**（实时）
- **磁盘最大占用**（5 个分区中最高的）
- **系统运行时长**（自上次开机）

### 巡检总结页（最底部）

- **健康分**：0-100 分制，75+ = 良好，50-74 = 警告，< 50 = 危险
- **正常 / 警告 / 危险** 三色徽章，统计各模块异常数量

---

## 七、功能特性

### v14（2026-08-18）

- HTML 默认输出到脚本所在目录（`$PSScriptRoot`），不再写死到工作目录
- 脚本可放在任意位置运行，报告自动输出到同目录

### v13（2026-08-18）

#### 1. 左侧导航目录

- 240px 宽 sticky 导航
- 顶部标题 + 副标题「14 个章节 · 点击跳转」
- 每个章节含：序号、图标、标题
- 当前章节自动高亮（蓝紫渐变背景 + 白字）
- 响应式：窄屏自动收起为顶部静态

#### 2. GPU 类型识别

- 详情表新增「类型」列，独显/核显徽章
- 自动识别：
  - **独显**（VRAM ≥ 1 GB）
  - **核显**（VRAM < 1 GB 或名称含 Radeon Graphics / UHD / Iris / Vega）
- 过滤虚拟显示适配器（Todesk、GameViewer、VMware、VirtualBox 等）

#### 3. 其他改进

- 物理磁盘 Smart 健康状态
- 网络 TCP 连接状态分布
- 进程/服务/事件日志 Top 列表
- 完全离线（无 CDN、无 JS 库）

### v12（之前）

- 14 章节完整巡检
- 纯 SVG 图表（无外部依赖）

---

## 八、常见问题

### Q1：双击没反应？

检查执行策略：

```powershell
Get-ExecutionPolicy -List
```

如显示 `Restricted`，执行：

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### Q2：报告生成失败？

- 检查是否禁用脚本：在 PowerShell 执行 `Get-ExecutionPolicy`
- 手动指定输出路径：编辑脚本中的 `$outDir` 变量
- 查看终端错误信息，把报错发给开发者

### Q3：报告文件很大？

正常情况 100-150 KB（包含所有 SVG 图表）。如果异常大（比如 > 500 KB），说明进程或事件数据异常多，可在脚本中调整 `$topN` 参数。

### Q4：报告打不开？

- 浏览器版本要求：Chrome 90+ / Edge 90+ / Firefox 88+
- 用记事本/VSCode 也能打开 HTML 源码
- 报告是单文件，可直接拷贝到其他机器查看

### Q5：需要管理员权限吗？

脚本不需要管理员权限即可读取大部分信息（CPU、内存、磁盘、网络、进程、服务）。如需读取防火墙详细规则或某些安全信息，需以管理员身份运行。

### Q6：报告没出现在桌面？

v14 起报告输出到脚本同目录。检查脚本实际所在位置：

```powershell
(Get-Item "$env:USERPROFILE\Desktop\windows-inspect-v14.ps1").DirectoryName
```

---

## 九、版本历史

| 版本 | 日期       | 改动 |
|------|------------|------|
| v14  | 2026-08-18 | HTML 默认输出到脚本所在目录（`$PSScriptRoot`） |
| v13  | 2026-08-18 | 左侧导航目录 + GPU 类型识别（独显/核显） + 过滤虚拟适配器 |
| v12  | -          | 14 章节完整巡检 + 纯 SVG 图表 |

---

## 十、技术细节（给开发者）

### 收集的数据源

| 数据           | API / WMI 类                          |
|----------------|---------------------------------------|
| CPU            | `Win32_Processor`                     |
| 内存           | `Win32_OperatingSystem` + CIM         |
| 磁盘           | `Win32_LogicalDisk` + `MSFT_PhysicalDisk` |
| 网络           | `Win32_TCPConnection` + `NetAdapterStatistics` |
| 进程           | `Get-Process`                         |
| 服务           | `Get-Service`                         |
| 事件日志       | `Get-WinEvent`                        |
| 计划任务       | `Get-ScheduledTask`                   |
| 启动项         | 注册表 `Run` / `RunOnce`              |
| 健康状态       | `MSFT_StorageReliabilityCounter`      |

### 自定义输出

脚本中关键常量：

```powershell
$now       = Get-Date                                    # 当前时间
$stamp     = $now.ToString('yyyyMMdd_HHmmss')            # 文件名时间戳
$outDir    = if ($PSScriptRoot) { $PSScriptRoot }         # 输出目录（脚本同目录）
              else { (Get-Location).Path }
```

如需修改报告标题，编辑 `Windows 系统巡检报告` 字样（约第 990 行）。

### 配色变量（CSS Custom Properties）

```css
:root {
  --accent: #6366F1;      /* 主色调 蓝紫 */
  --success: #10B981;     /* 绿色 */
  --warn: #F59E0B;        /* 橙色 */
  --danger: #EF4444;      /* 红色 */
  --info: #3B82F6;        /* 蓝色 */
}
```

---

**问题反馈**：把终端报错截图发给脚本作者。