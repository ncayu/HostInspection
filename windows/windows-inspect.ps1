# ============================================================
# Windows Inspection Script v14 (Pure PowerShell, fully offline)
# - All icons inline (SVG)
# - All charts inline (pure SVG, no JS library)
# - Single self-contained HTML report
# ============================================================
# Changelog:
#   v14 (2026-08-18)
#     - HTML 默认输出到脚本所在目录（不再写死到工作目录）
#     - 使用 $PSScriptRoot 自动检测脚本位置
#   v13 (2026-08-18)
#     - 左侧固定导航目录（sticky），含 14 章节 + 编号 + 图标
#     - 滚动时自动高亮当前章节（IntersectionObserver）
#     - GPU 详情表新增「类型」列，独显/核显徽章
#     - 过滤虚拟显示适配器（Todesk / GameViewer/ VMware 等）
#     - 概要显卡卡片同时显示独显 + 核显
#   v12 (previous)
#     - 14 章节完整巡检（系统/硬件/CPU/内存/磁盘/网络/进程/服务/安全/事件/任务/启动项/总结）
#     - 纯 SVG 图表（无外部依赖），自包含 HTML
# ============================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference   = 'SilentlyContinue'

# ---- Output path ----
$now    = Get-Date
$stamp  = $now.ToString('yyyyMMdd_HHmmss')
# Output to the same directory as the script (current dir when invoked via powershell -File)
$outDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$report = Join-Path $outDir ("win_system_inspection_{0}.html" -f $stamp)

Write-Host "[1/3] Collecting Windows system data..." -ForegroundColor Cyan

# ============================================================
# Data Collection
# ============================================================

# --- OS / System ---
$os     = Get-CimInstance Win32_OperatingSystem
$cs     = Get-CimInstance Win32_ComputerSystem
$cpu    = Get-CimInstance Win32_Processor | Select-Object -First 1
$bios   = Get-CimInstance Win32_BIOS
$board  = Get-CimInstance Win32_BaseBoard
$tzInfo = [System.TimeZoneInfo]::Local
$boot   = $os.LastBootUpTime
$up     = (Get-Date) - $boot

# --- CPU ---
$cpuUsage  = [int](Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
if (-not $cpuUsage -or $cpuUsage -lt 0) { $cpuUsage = 0 }
$cpuLoad   = if ($cpu.LoadPercentage) { [int]$cpu.LoadPercentage } else { $cpuUsage }
$cpuL2     = if ($cpu.L2CacheSize) { [math]::Round($cpu.L2CacheSize / 1024, 1) } else { 0 }
$cpuL3     = if ($cpu.L3CacheSize) { [math]::Round($cpu.L3CacheSize / 1024, 1) } else { 0 }
$cpuClock  = if ($cpu.MaxClockSpeed) { [math]::Round($cpu.MaxClockSpeed / 1000, 2) } else { 0 }

# --- Memory ---
$memTotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
$memFreeGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
$memUsedGB  = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
$memPct     = if ($os.TotalVisibleMemorySize -gt 0) { [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100, 1) } else { 0 }

# Virtual memory: derive from PageFile to avoid 0GB bug
$pageFile = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
$vmTotalGB = 0; $vmUsedGB = 0; $vmFreeGB = 0; $vmPct = 0
if ($pageFile) {
    $vmTotalGB = [math]::Round($pageFile.AllocatedBaseSize / 1024, 1)
    $vmUsedGB  = [math]::Round($pageFile.CurrentUsage / 1024, 1)
    if ($vmTotalGB -gt 0) {
        $vmPct    = [math]::Round($vmUsedGB / $vmTotalGB * 100, 1)
        $vmFreeGB = [math]::Round($vmTotalGB - $vmUsedGB, 1)
    }
}

# --- Logical disks ---
$disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
$diskRows = @()
$diskMaxPct = 0
foreach ($d in $disks) {
    $total = [math]::Round($d.Size / 1GB, 1)
    $free  = [math]::Round($d.FreeSpace / 1GB, 1)
    $used  = [math]::Round(($d.Size - $d.FreeSpace) / 1GB, 1)
    $pct   = if ($d.Size -gt 0) { [math]::Round(($d.Size - $d.FreeSpace) / $d.Size * 100, 0) } else { 0 }
    if ($pct -gt $diskMaxPct) { $diskMaxPct = $pct }
    $diskRows += [PSCustomObject]@{
        Dev  = $d.DeviceID; Total = $total; Used = $used; Free = $free
        Pct  = $pct;        FS    = $d.FileSystem; Name = $d.VolumeName
    }
}

# --- Physical disk health ---
$physDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue

# --- Network adapters (real + stats) ---
$adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
$netRows = @()
foreach ($a in $adapters) {
    $ip = Get-NetIPAddress -InterfaceAlias $a.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
    $stats = Get-NetAdapterStatistics -Name $a.Name -ErrorAction SilentlyContinue
    $netRows += [PSCustomObject]@{
        Name    = $a.Name
        Desc    = $a.InterfaceDescription
        IP      = if ($ip) { $ip.IPAddress } else { 'N/A' }
        Speed   = if ($a.LinkSpeed) { [math]::Round($a.LinkSpeed / 1GB, 1) } else { 0 }
        Sent    = if ($stats) { [math]::Round($stats.BytesSent / 1MB, 0) } else { 0 }
        Recv    = if ($stats) { [math]::Round($stats.BytesReceived / 1MB, 0) } else { 0 }
    }
}

# --- Network connections (TCP states) ---
$tcpAll = Get-NetTCPConnection -ErrorAction SilentlyContinue
$tcpStats = @{
    Established = @($tcpAll | Where-Object State -eq 'Established').Count
    Listen     = @($tcpAll | Where-Object State -eq 'Listen').Count
    TimeWait   = @($tcpAll | Where-Object State -eq 'TimeWait').Count
    CloseWait  = @($tcpAll | Where-Object State -eq 'CloseWait').Count
}

# --- Listening ports (top 30) ---
$listenRows = @()
$listening = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Select-Object -First 30
foreach ($c in $listening) {
    $procName = ''
    try { $procName = (Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue).ProcessName } catch {}
    $listenRows += [PSCustomObject]@{
        Proto = 'TCP'; Addr = $c.LocalAddress; Port = $c.LocalPort
        Proc  = $procName; PID = $c.OwningProcess
    }
}

# --- Processes (top 10 mem + cpu) ---
$procs = Get-Process -ErrorAction SilentlyContinue
$procTotal = @($procs).Count
$topMem = $procs | Sort-Object WorkingSet64 -Descending | Select-Object -First 10
$maxMem = ($topMem | Select-Object -First 1).WorkingSet64
if (-not $maxMem -or $maxMem -lt 1) { $maxMem = 1 }
$procMemRows = @()
foreach ($p in $topMem) {
    $barPct = [math]::Round($p.WorkingSet64 / $maxMem * 100, 0)
    $procMemRows += [PSCustomObject]@{
        PID = $p.Id; Name = $p.ProcessName
        Mem = [math]::Round($p.WorkingSet64 / 1MB, 1); Bar = $barPct
    }
}

$topCpu = $procs | Where-Object { $_.CPU -gt 0 } | Sort-Object CPU -Descending | Select-Object -First 10
$maxCpu = ($topCpu | Select-Object -First 1).CPU
if (-not $maxCpu -or $maxCpu -lt 1) { $maxCpu = 1 }
$procCpuRows = @()
foreach ($p in $topCpu) {
    $barPct = [math]::Round($p.CPU / $maxCpu * 100, 0)
    $procCpuRows += [PSCustomObject]@{
        PID = $p.Id; Name = $p.ProcessName
        Cpu = [math]::Round($p.CPU, 1); Bar = $barPct
    }
}

# --- Services ---
$svcNames = @('WinRM','Spooler','wuauserv','BITS','TermService','LanmanServer',
              'LanmanWorkstation','MpsSvc','WinDefend','Audiosrv','Dnscache',
              'Dhcp','EventLog','PlugPlay','Schedule','Winmgmt','RpcSs',
              'SamSs','WSearch','ProfSvc','Themes','BFE','iphlpsvc','wercplsupport')
$svcRows = @()
$svcRunning = 0; $svcStopped = 0
foreach ($s in $svcNames) {
    $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
    if ($svc) {
        $st = "$($svc.Status)"
        if ($st -eq 'Running') { $svcRunning++ } else { $svcStopped++ }
        $svcRows += [PSCustomObject]@{
            Name = $s; Status = $st; StartType = "$($svc.StartType)"; Display = $svc.DisplayName
        }
    }
}

# --- Firewall ---
$fwProfiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue

# --- Defender ---
$defender = Get-MpComputerStatus -ErrorAction SilentlyContinue

# --- BitLocker ---
$blVolumes = Get-BitLockerVolume -ErrorAction SilentlyContinue

# --- Hotfixes ---
$hotfixes = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending
$lastHot = $hotfixes | Select-Object -First 1
$hotCount = @($hotfixes).Count

# --- Local users ---
$localUsers = Get-LocalUser -ErrorAction SilentlyContinue

# --- Logged-on users ---
$loggedOnRaw = query user 2>$null
$loggedOnRows = @()
if ($loggedOnRaw) {
    foreach ($line in ($loggedOnRaw | Select-Object -Skip 1)) {
        $parts = ($line -replace '^>','') -split '\s+'
        if ($parts.Count -ge 5) {
            $loggedOnRows += [PSCustomObject]@{
                User = $parts[0]; Session = $parts[1]; State = $parts[2]
                LoginTime = "$($parts[3]) $($parts[4])"
            }
        }
    }
}

# --- GPU ---
$gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue

# --- TPM ---
$tpm = Get-Tpm -ErrorAction SilentlyContinue

# --- Power plan ---
$powerPlanRaw = powercfg /getactivescheme 2>$null
$powerPlan = if ($powerPlanRaw -match '\((.+?)\)') { $matches[1] } else { 'N/A' }

# --- UAC ---
$uacReg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -ErrorAction SilentlyContinue

# --- Scheduled tasks ---
$tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' }
$taskTotal = @($tasks).Count
$taskRunning = @($tasks | Where-Object State -eq 'Running').Count
$taskReady   = @($tasks | Where-Object State -eq 'Ready').Count
$taskDisabled= @($tasks | Where-Object State -eq 'Disabled').Count

# --- Startup programs ---
$startupRaw = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue | Select-Object -First 20
$startupCount = @($startupRaw).Count

# --- Recent event log summary ---
$evtSystem   = Get-EventLog -LogName System -Newest 200 -EntryType Error,Warning -ErrorAction SilentlyContinue
$evtApp      = Get-EventLog -LogName Application -Newest 200 -EntryType Error,Warning -ErrorAction SilentlyContinue
$sysErrors   = @($evtSystem | Where-Object EntryType -eq 'Error').Count
$sysWarnings = @($evtSystem | Where-Object EntryType -eq 'Warning').Count
$appErrors   = @($evtApp | Where-Object EntryType -eq 'Error').Count
$appWarnings = @($evtApp | Where-Object EntryType -eq 'Warning').Count

# Recent critical events (top 10)
$recentEvents = @()
$evtAll = Get-EventLog -LogName System -Newest 50 -EntryType Error -ErrorAction SilentlyContinue
foreach ($e in ($evtAll | Select-Object -First 10)) {
    $firstLine = ($e.Message -split "`n")[0]
    $msg = if ($firstLine.Length -gt 80) { $firstLine.Substring(0, 80) + '...' } else { $firstLine }
    $recentEvents += [PSCustomObject]@{
        Time = $e.TimeGenerated.ToString('MM-dd HH:mm')
        Source = $e.Source
        Msg = $msg
    }
}

# --- System restore ---
$restoreEnabled = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name DisableSR -ErrorAction SilentlyContinue).DisableSR
$restoreEnabled = if ($restoreEnabled -eq 1) { 'Disabled' } else { 'Enabled' }

# --- Display info ---
$display = Get-CimInstance Win32_DesktopMonitor -ErrorAction SilentlyContinue | Select-Object -First 1

Write-Host "[2/3] Generating HTML report..." -ForegroundColor Cyan

# ============================================================
# Status thresholds
# ============================================================
$cpuCard = if ($cpuLoad -ge 90) { 'critical' } elseif ($cpuLoad -ge 75) { 'warning' } else { 'ok' }
$memCard = if ($memPct -ge 90) { 'critical' } elseif ($memPct -ge 75) { 'warning' } else { 'ok' }
$diskCard= if ($diskMaxPct -ge 90) { 'critical' } elseif ($diskMaxPct -ge 80) { 'warning' } else { 'ok' }

# Health score (calibrated, event log errors don't dominate)
$ok = 0; $warn = 0; $crit = 0
if ($cpuCard -eq 'ok') { $ok++ } elseif ($cpuCard -eq 'warning') { $warn++ } else { $crit++ }
if ($memCard -eq 'ok') { $ok++ } elseif ($memCard -eq 'warning') { $warn++ } else { $crit++ }
if ($diskCard -eq 'ok') { $ok++ } elseif ($diskCard -eq 'warning') { $warn++ } else { $crit++ }
if ($fwProfiles) { foreach ($f in $fwProfiles) { if ($f.Enabled) { $ok++ } else { $crit++ } } }
if ($defender) { if ($defender.RealTimeProtectionEnabled) { $ok++ } else { $crit++ } }
if ($blVolumes) { foreach ($v in $blVolumes) { if ($v.ProtectionStatus -eq 'On') { $ok++ } else { $warn++ } } }

$eventPenalty = 0
if ($sysErrors -gt 100) { $eventPenalty += 8 }
elseif ($sysErrors -gt 30) { $eventPenalty += 4 }
elseif ($sysErrors -gt 10) { $eventPenalty += 2 }
if ($appErrors -gt 100) { $eventPenalty += 4 }
elseif ($appErrors -gt 30) { $eventPenalty += 2 }

$healthScore = 100 - ($warn * 3) - ($crit * 10) - $eventPenalty
if ($healthScore -lt 0) { $healthScore = 0 }
$healthColor = if ($healthScore -ge 80) { '#10B981' } elseif ($healthScore -ge 60) { '#F59E0B' } else { '#EF4444' }
$healthLabel = if ($healthScore -ge 80) { '系统健康' } elseif ($healthScore -ge 60) { '需要注意' } else { '需要处理' }

# ============================================================
# SVG Icon Helper (returns inline SVG markup)
# ============================================================
$script:icons = @{
    'win'    = '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M3 5.5L10.5 4v8H3V5.5zM3 12.5h7.5v8L3 19V12.5zM11.5 4L21 2.5v9.5h-9.5V4zM11.5 12.5H21V22l-9.5-1.5v-8z"/></svg>'
    'cpu'    = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="4" width="16" height="16" rx="2"/><rect x="9" y="9" width="6" height="6"/><line x1="9" y1="2" x2="9" y2="4"/><line x1="15" y1="2" x2="15" y2="4"/><line x1="9" y1="20" x2="9" y2="22"/><line x1="15" y1="20" x2="15" y2="22"/><line x1="20" y1="9" x2="22" y2="9"/><line x1="20" y1="14" x2="22" y2="14"/><line x1="2" y1="9" x2="4" y2="9"/><line x1="2" y1="14" x2="4" y2="14"/></svg>'
    'mem'    = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="6" width="20" height="12" rx="2"/><line x1="7" y1="10" x2="7" y2="14"/><line x1="11" y1="10" x2="11" y2="14"/><line x1="15" y1="10" x2="15" y2="14"/></svg>'
    'hdd'    = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="22" y1="12" x2="2" y2="12"/><path d="M5.45 5.11L2 12v6a2 2 0 002 2h16a2 2 0 002-2v-6l-3.45-6.89A2 2 0 0016.76 4H7.24a2 2 0 00-1.79 1.11z"/><line x1="6" y1="16" x2="6.01" y2="16"/><line x1="10" y1="16" x2="10.01" y2="16"/></svg>'
    'clock'  = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>'
    'net'    = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="2" width="6" height="6"/><rect x="16" y="16" width="6" height="6"/><rect x="2" y="16" width="6" height="6"/><path d="M5 16v-3a1 1 0 011-1h12a1 1 0 011 1v3M12 12V8"/></svg>'
    'tasks'  = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 11 12 14 22 4"/><path d="M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11"/></svg>'
    'cogs'   = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 01-2.83 2.83l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-4 0v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83-2.83l.06-.06a1.65 1.65 0 00.33-1.82 1.65 1.65 0 00-1.51-1H3a2 2 0 010-4h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 012.83-2.83l.06.06a1.65 1.65 0 001.82.33H9a1.65 1.65 0 001-1.51V3a2 2 0 014 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 2.83l-.06.06a1.65 1.65 0 00-.33 1.82V9a1.65 1.65 0 001.51 1H21a2 2 0 010 4h-.09a1.65 1.65 0 00-1.51 1z"/></svg>'
    'shield' = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>'
    'list'   = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></svg>'
    'rocket' = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4.5 16.5c-1.5 1.26-2 5-2 5s3.74-.5 5-2c.71-.84.7-2.13-.09-2.91a2.18 2.18 0 00-2.91-.09z"/><path d="M12 15l-3-3a22 22 0 012-3.95A12.88 12.88 0 0122 2c0 2.72-.78 7.5-6 11a22.35 22.35 0 01-4 2z"/><path d="M9 12H4s.55-3.03 2-4c1.62-1.08 5 0 5 0"/><path d="M12 15v5s3.03-.55 4-2c1.08-1.62 0-5 0-5"/></svg>'
    'desktop'= '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="3" width="20" height="14" rx="2" ry="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/></svg>'
    'tag'    = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20.59 13.41l-7.17 7.17a2 2 0 01-2.83 0L2 12V2h10l8.59 8.59a2 2 0 010 2.82z"/><line x1="7" y1="7" x2="7.01" y2="7"/></svg>'
    'code'   = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg>'
    'link'   = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10 13a5 5 0 007.54.54l3-3a5 5 0 00-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 00-7.54-.54l-3 3a5 5 0 007.07 7.07l1.71-1.71"/></svg>'
    'flag'   = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"/><line x1="4" y1="22" x2="4" y2="15"/></svg>'
    'check'  = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>'
    'x'      = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>'
    'warn'   = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>'
    'info'   = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>'
    'moon'   = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1111.21 3 7 7 0 0021 12.79z"/></svg>'
    'sun'    = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>'
    'tv'     = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="7" width="20" height="15" rx="2" ry="2"/><polyline points="17 2 12 7 7 2"/></svg>'
    'plug'   = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 2v6M15 2v6M5 8h14v3a7 7 0 01-14 0V8zM12 18v4"/></svg>'
    'door'   = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 20h20M4 20V8a2 2 0 012-2h12a2 2 0 012 2v12M14 12h.01"/></svg>'
    'fire'   = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8.5 14.5A2.5 2.5 0 0011 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 11-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 002.5 2.5z"/></svg>'
    'bolt'   = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>'
    'lock'   = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0110 0v4"/></svg>'
    'users'  = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 00-3-3.87M16 3.13a4 4 0 010 7.75"/></svg>'
    'user'   = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 00-4-4H8a4 4 0 00-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>'
    'play'   = '<svg viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>'
    'heart'  = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20.84 4.61a5.5 5.5 0 00-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 00-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 000-7.78z"/></svg>'
    'cube'   = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 16V8a2 2 0 00-1-1.73l-7-4a2 2 0 00-2 0l-7 4A2 2 0 003 8v8a2 2 0 001 1.73l7 4a2 2 0 002 0l7-4A2 2 0 0021 16z"/><polyline points="3.27 6.96 12 12.01 20.73 6.96"/><line x1="12" y1="22.08" x2="12" y2="12"/></svg>'
    'globe'  = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 014 10 15.3 15.3 0 01-4 10 15.3 15.3 0 01-4-10 15.3 15.3 0 014-10z"/></svg>'
    'power'  = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18.36 6.64a9 9 0 11-12.73 0M12 2v10"/></svg>'
    'history'= '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 4v6h6M23 20v-6h-6"/><path d="M20.49 9A9 9 0 005.64 5.64L1 10m22 4l-4.64 4.36A9 9 0 013.51 15"/></svg>'
    'microchip' = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="4" width="16" height="16" rx="2"/><rect x="9" y="9" width="6" height="6"/><line x1="9" y1="2" x2="9" y2="4"/><line x1="15" y1="2" x2="15" y2="4"/><line x1="9" y1="20" x2="9" y2="22"/><line x1="15" y1="20" x2="15" y2="22"/><line x1="20" y1="9" x2="22" y2="9"/><line x1="20" y1="14" x2="22" y2="14"/><line x1="2" y1="9" x2="4" y2="9"/><line x1="2" y1="14" x2="4" y2="14"/></svg>'
    'server' = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="2" width="20" height="8" rx="2" ry="2"/><rect x="2" y="14" width="20" height="8" rx="2" ry="2"/><line x1="6" y1="6" x2="6.01" y2="6"/><line x1="6" y1="18" x2="6.01" y2="18"/></svg>'
    'expand' = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 3 21 3 21 9"/><polyline points="9 21 3 21 3 15"/><line x1="21" y1="3" x2="14" y2="10"/><line x1="3" y1="21" x2="10" y2="14"/></svg>'
}

# Function to render icon
function Get-Icon([string]$name, [string]$size = '18') {
    if ($script:icons.ContainsKey($name)) {
        return '<span class="icon icon-' + $size + '">' + $script:icons[$name] + '</span>'
    }
    return ''
}

# ============================================================
# SVG Chart Helpers (all pure SVG, no JS)
# ============================================================

# Generate donut/pie chart with multiple segments
function Get-Donut([int]$cx, [int]$cy, [int]$r, [int]$stroke, [array]$segments, [string]$title) {
    $sb = New-Object System.Text.StringBuilder
    $circ = 2 * [math]::PI * $r
    $total = 0
    foreach ($s in $segments) { $total += $s.Value }
    if ($total -eq 0) { $total = 1 }

    [void]$sb.Append("<div class='chart-card'>")
    [void]$sb.Append("<div class='chart-title'>$title</div>")
    [void]$sb.Append("<svg viewBox='0 0 200 200' class='donut-svg'>")

    $offset = 0
    foreach ($s in $segments) {
        $frac = $s.Value / $total
        $dash = $frac * $circ
        [void]$sb.Append("<circle cx='$cx' cy='$cy' r='$r' fill='none' stroke='$($s.Color)' stroke-width='$stroke' ")
        [void]$sb.Append("stroke-dasharray='$([math]::Round($dash,2)) $($circ - [math]::Round($dash,2))' ")
        [void]$sb.Append("stroke-dashoffset='-$([math]::Round($offset,2))' transform='rotate(-90 $cx $cy)'/>")
        $offset += $dash
    }
    [void]$sb.Append("<text x='$cx' y='$cy' text-anchor='middle' dominant-baseline='central' class='donut-total'>$total</text>")
    [void]$sb.Append("<text x='$cx' y='$($cy+22)' text-anchor='middle' class='donut-sub'>总数</text>")
    [void]$sb.Append("</svg>")

    [void]$sb.Append("<div class='legend'>")
    foreach ($s in $segments) {
        [void]$sb.Append("<div class='legend-item'><span class='legend-dot' style='background:$($s.Color);'></span>$($s.Name) <strong>$($s.Value)</strong></div>")
    }
    [void]$sb.Append("</div>")
    [void]$sb.Append("</div>")
    return $sb.ToString()
}

# Generate horizontal bar chart
function Get-HBar([array]$items, [string]$title, [string]$unit) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<div class='chart-card'>")
    [void]$sb.Append("<div class='chart-title'>$title</div>")

    $maxVal = 0
    foreach ($i in $items) { if ($i.Value -gt $maxVal) { $maxVal = $i.Value } }
    if ($maxVal -eq 0) { $maxVal = 1 }

    foreach ($i in $items) {
        $pct = [math]::Round(($i.Value / $maxVal) * 100, 0)
        $labelEsc = $i.Name -replace "'", "&#39;" -replace '"', '&quot;'
        [void]$sb.Append("<div class='hbar-row'>")
        [void]$sb.Append("<div class='hbar-label'>$labelEsc</div>")
        [void]$sb.Append("<div class='hbar-track'><div class='hbar-fill' style='width:$pct%;background:$($i.Color);'></div></div>")
        [void]$sb.Append("<div class='hbar-val'>$($i.Value) $unit</div>")
        [void]$sb.Append("</div>")
    }
    [void]$sb.Append("</div>")
    return $sb.ToString()
}

# Generate vertical bar chart (network traffic)
function Get-VBar([array]$items, [string]$title) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<div class='chart-card'>")
    [void]$sb.Append("<div class='chart-title'>$title</div>")

    $maxVal = 0
    foreach ($i in $items) { if ($i.Value -gt $maxVal) { $maxVal = $i.Value } }
    if ($maxVal -eq 0) { $maxVal = 1 }

    [void]$sb.Append("<div class='vbar-chart'>")
    foreach ($i in $items) {
        $pct = [math]::Round(($i.Value / $maxVal) * 100, 0)
        if ($pct -lt 4) { $pct = 4 }
        $labelEsc = $i.Name -replace "'", "&#39;"
        [void]$sb.Append("<div class='vbar-item'>")
        [void]$sb.Append("<div class='vbar-value'>$($i.Value)</div>")
        [void]$sb.Append("<div class='vbar-bar' style='height:$pct%;background:$($i.Color);' title='$labelEsc $($i.Value)'></div>")
        [void]$sb.Append("<div class='vbar-label'>$labelEsc</div>")
        [void]$sb.Append("</div>")
    }
    [void]$sb.Append("</div>")
    [void]$sb.Append("</div>")
    return $sb.ToString()
}

# Generate gauge chart (single value)
function Get-Gauge([int]$value, [string]$name, [string]$color) {
    $r = 60
    $circ = 2 * [math]::PI * $r
    $frac = $value / 100
    $dash = $frac * $circ * 0.75  # 270 degree gauge (3/4 circle)
    $gap = $circ - $dash
    $offset = $circ * 0.875  # rotate start

    $colorClass = 'ok'
    if ($value -ge 75) { $colorClass = 'warn' }
    if ($value -ge 90) { $colorClass = 'crit' }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<div class='gauge-card gauge-$colorClass'>")
    [void]$sb.Append("<svg viewBox='0 0 160 160' class='gauge-svg'>")
    [void]$sb.Append("<circle cx='80' cy='80' r='$r' fill='none' stroke='var(--rule2)' stroke-width='12' ")
    [void]$sb.Append("stroke-dasharray='$circ' transform='rotate(135 80 80)'/>")
    [void]$sb.Append("<circle cx='80' cy='80' r='$r' fill='none' stroke='$color' stroke-width='12' stroke-linecap='round' ")
    [void]$sb.Append("stroke-dasharray='$([math]::Round($dash,2)) $gap' transform='rotate(135 80 80)'/>")
    [void]$sb.Append("<text x='80' y='75' text-anchor='middle' class='gauge-val'>$value</text>")
    [void]$sb.Append("<text x='80' y='98' text-anchor='middle' class='gauge-pct'>%</text>")
    [void]$sb.Append("</svg>")
    [void]$sb.Append("<div class='gauge-name'>$name</div>")
    [void]$sb.Append("</div>")
    return $sb.ToString()
}

# Generate metric card (single big number)
function Get-Metric([int]$value, [string]$label, [string]$unit, [string]$color) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<div class='gauge-card'>")
    [void]$sb.Append("<svg viewBox='0 0 160 160' class='gauge-svg' style='opacity:0.85'>")
    [void]$sb.Append("<circle cx='80' cy='80' r='62' fill='none' stroke='$color' stroke-width='2' stroke-dasharray='3 4' opacity='0.4'/>")
    [void]$sb.Append("<circle cx='80' cy='80' r='50' fill='none' stroke='$color' stroke-width='2' opacity='0.3'/>")
    [void]$sb.Append("<text x='80' y='78' text-anchor='middle' class='gauge-val' style='font-size:1.9rem;fill:$color;'>$value</text>")
    if ($unit) {
        [void]$sb.Append("<text x='80' y='105' text-anchor='middle' class='gauge-pct'>$unit</text>")
    }
    [void]$sb.Append("</svg>")
    [void]$sb.Append("<div class='gauge-name'>$label</div>")
    [void]$sb.Append("</div>")
    return $sb.ToString()
}

# ============================================================
# HTML Output
# ============================================================
$sb = New-Object System.Text.StringBuilder

function Add($text) { [void]$sb.AppendLine($text) }

# --- DOCTYPE / Head ---
Add '<!DOCTYPE html>'
Add '<html lang="zh-CN" data-theme="default">'
Add '<head>'
Add '  <meta charset="UTF-8">'
Add '  <meta name="viewport" content="width=device-width,initial-scale=1.0">'
Add ('  <title>Windows 巡检报告 - ' + $now.ToString('yyyy-MM-dd HH:mm') + '</title>')
Add '  <style>'

# CSS Variables
Add @'
:root {
  --bg: #F4F6FB; --bg2: #FFFFFF; --bg3: #F9FAFC;
  --ink: #1F2937; --ink2: #4B5563; --muted: #9CA3AF;
  --rule: #E5E7EB; --rule2: #F3F4F6;
  --accent: #6366F1; --accent2: #8B5CF6; --accent3: #EC4899;
  --success: #10B981; --warn: #F59E0B; --danger: #EF4444; --info: #3B82F6;
  --grad-accent: linear-gradient(135deg,#6366F1 0%,#8B5CF6 50%,#EC4899 100%);
  --grad-card: linear-gradient(135deg,rgba(99,102,241,0.08),rgba(139,92,246,0.05));
  --shadow-sm: 0 1px 3px rgba(0,0,0,0.04),0 1px 2px rgba(0,0,0,0.06);
  --shadow-md: 0 4px 12px rgba(99,102,241,0.08),0 2px 4px rgba(0,0,0,0.04);
  --shadow-lg: 0 12px 32px rgba(99,102,241,0.12),0 4px 8px rgba(0,0,0,0.06);
  --radius: 14px;
}
[data-theme="dark"] {
  --bg: #0B1020; --bg2: #151B2E; --bg3: #1E2640;
  --ink: #E5E7EB; --ink2: #CBD5E1; --muted: #94A3B8;
  --rule: #1F2A44; --rule2: #18213A;
  --accent: #818CF8; --accent2: #A78BFA; --accent3: #F472B6;
  --shadow-sm: 0 1px 3px rgba(0,0,0,0.4),0 1px 2px rgba(0,0,0,0.5);
  --shadow-md: 0 4px 12px rgba(0,0,0,0.4),0 2px 4px rgba(0,0,0,0.3);
  --shadow-lg: 0 12px 32px rgba(0,0,0,0.5),0 4px 8px rgba(0,0,0,0.4);
}
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif;
  background: var(--bg); color: var(--ink);
  font-size: 14px; line-height: 1.6;
  background-image:
    radial-gradient(circle at 15% 10%, rgba(99,102,241,0.08) 0%, transparent 35%),
    radial-gradient(circle at 85% 90%, rgba(236,72,153,0.06) 0%, transparent 35%);
  min-height: 100vh;
}
.wrap { max-width: 1380px; margin: 0 auto; padding: 24px; display: grid; grid-template-columns: 240px 1fr; gap: 24px; align-items: start; }
.wrap > .main { min-width: 0; }
.nav {
  position: sticky; top: 24px;
  background: linear-gradient(180deg, #ffffff 0%, #F5F3FF 100%);
  border: 1px solid var(--rule);
  border-radius: 16px; padding: 18px 14px;
  max-height: calc(100vh - 48px); overflow-y: auto;
  box-shadow: 0 4px 16px rgba(99,102,241,0.08);
}
.nav-header {
  padding: 4px 8px 14px; border-bottom: 1px solid var(--rule);
  margin-bottom: 12px;
}
.nav-header-title {
  font-size: 0.95rem; font-weight: 700; color: var(--ink);
  display: flex; align-items: center; gap: 8px; margin-bottom: 2px;
}
.nav-header-title svg { width: 18px; height: 18px; color: var(--accent); }
.nav-header-sub {
  font-size: 0.72rem; color: var(--muted); letter-spacing: 0.3px;
  padding-left: 26px;
}
.nav ul { list-style: none; padding: 0; margin: 0; }
.nav li { margin: 2px 0; }
.nav li a {
  display: flex; align-items: center; gap: 10px;
  padding: 9px 12px; border-radius: 10px;
  font-size: 0.85rem; color: var(--ink2);
  text-decoration: none; transition: all 0.15s;
  position: relative;
}
.nav li a:hover {
  background: rgba(99,102,241,0.08); color: var(--ink);
}
.nav li a.active {
  background: linear-gradient(135deg, #6366F1, #8B5CF6);
  color: #fff; font-weight: 600;
  box-shadow: 0 4px 12px rgba(99,102,241,0.3);
}
.nav li a .nav-num {
  width: 20px; height: 20px; border-radius: 6px;
  background: var(--bg3); color: var(--muted);
  font-size: 0.7rem; font-weight: 600;
  display: inline-flex; align-items: center; justify-content: center;
  flex-shrink: 0; font-variant-numeric: tabular-nums;
  transition: all 0.15s;
}
.nav li a.active .nav-num {
  background: rgba(255,255,255,0.25); color: #fff;
}
.nav li a:hover .nav-num { background: var(--accent); color: #fff; }
.nav li a .nav-icon {
  width: 16px; height: 16px; flex-shrink: 0;
  display: inline-flex; align-items: center; justify-content: center;
  opacity: 0.65; color: currentColor;
}
.nav li a .nav-icon svg { width: 16px; height: 16px; display: block; }
.nav li a.active .nav-icon { opacity: 1; }
.nav-footer {
  margin-top: 14px; padding-top: 12px;
  border-top: 1px solid var(--rule);
  text-align: center; font-size: 0.7rem; color: var(--muted);
}
.nav-footer-badge {
  display: inline-block; padding: 3px 10px;
  border-radius: 999px;
  background: linear-gradient(135deg, #6366F1, #8B5CF6);
  color: #fff; font-weight: 600; font-size: 0.68rem;
  letter-spacing: 0.3px;
}
.sec { scroll-margin-top: 16px; }
.icon { display: inline-flex; align-items: center; justify-content: center; vertical-align: middle; }
.icon svg { width: 100%; height: 100%; display: block; }
.icon-18 { width: 18px; height: 18px; }
.icon-20 { width: 20px; height: 20px; }
.icon-24 { width: 24px; height: 24px; }
.icon-28 { width: 28px; height: 28px; }
'@

# Header
Add @'
.hdr {
  background: var(--bg2); border-radius: 18px; padding: 28px 32px;
  margin-bottom: 24px; box-shadow: var(--shadow-md);
  display: flex; justify-content: space-between; align-items: center;
  flex-wrap: wrap; gap: 16px; position: relative; overflow: hidden;
  border: 1px solid var(--rule);
}
.hdr::before {
  content: ''; position: absolute; top: 0; left: 0; right: 0; height: 4px;
  background: var(--grad-accent);
}
.hdr-title { display: flex; align-items: center; gap: 14px; }
.hdr-icon {
  width: 52px; height: 52px; border-radius: 14px;
  background: var(--grad-accent); color: #fff;
  display: flex; align-items: center; justify-content: center;
  box-shadow: var(--shadow-md);
}
.hdr-icon svg { width: 28px; height: 28px; color: #fff; }
.hdr h1 {
  font-size: 1.6rem; margin: 0; font-weight: 700;
  background: var(--grad-accent); -webkit-background-clip: text;
  -webkit-text-fill-color: transparent; background-clip: text;
}
.hdr-sub { font-size: 0.85rem; color: var(--muted); margin-top: 4px; }
.hdr-meta { display: flex; gap: 12px; flex-wrap: wrap; }
.meta-pill {
  background: var(--bg3); border: 1px solid var(--rule); border-radius: 999px;
  padding: 6px 14px; font-size: 0.8rem; color: var(--ink2);
  display: flex; align-items: center; gap: 6px;
}
.meta-pill .icon-14 { width: 14px; height: 14px; color: var(--accent); }
.icon-14 { width: 14px; height: 14px; }
'@

# KPI grid
Add @'
.kpi-row { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin-bottom: 24px; }
.kpi {
  background: var(--bg2); border-radius: var(--radius); padding: 20px;
  border: 1px solid var(--rule); box-shadow: var(--shadow-sm);
  position: relative; overflow: hidden;
}
.kpi::before {
  content: ''; position: absolute; top: 0; left: 0; right: 0; height: 3px;
  background: var(--accent);
}
.kpi.ok::before { background: var(--success); }
.kpi.warn::before { background: var(--warn); }
.kpi.crit::before { background: var(--danger); }
.kpi-label { font-size: 0.78rem; color: var(--muted); text-transform: uppercase; letter-spacing: 0.6px; margin-bottom: 8px; display: flex; align-items: center; gap: 6px; }
.kpi-label .icon { color: var(--accent); }
.kpi-value { font-size: 1.8rem; font-weight: 700; color: var(--ink); line-height: 1.1; }
.kpi-unit { font-size: 0.9rem; color: var(--muted); margin-left: 4px; font-weight: 400; }
.kpi-bar { height: 6px; background: var(--rule2); border-radius: 3px; margin-top: 12px; overflow: hidden; }
.kpi-bar-fill { height: 100%; background: var(--grad-accent); border-radius: 3px; transition: width 1s ease; }
.kpi.ok .kpi-bar-fill { background: var(--success); }
.kpi.warn .kpi-bar-fill { background: var(--warn); }
.kpi.crit .kpi-bar-fill { background: var(--danger); }
'@

# Sections
Add @'
.sec {
  background: var(--bg2); border-radius: var(--radius); padding: 22px 24px;
  margin-bottom: 18px; box-shadow: var(--shadow-sm);
  border: 1px solid var(--rule); position: relative; overflow: hidden;
}
.sec-title {
  font-size: 1.1rem; font-weight: 700; margin: 0 0 16px;
  display: flex; align-items: center; gap: 10px;
  padding-bottom: 12px; border-bottom: 1px solid var(--rule2);
  line-height: 1.3;
}
.sec-title .icon-24 {
  width: 32px; height: 32px; border-radius: 10px;
  background: var(--grad-card); color: var(--accent);
  padding: 6px; box-sizing: border-box; flex-shrink: 0;
}
.sec-title .badge {
  margin-left: auto; font-size: 0.72rem; padding: 4px 10px; border-radius: 999px;
  background: var(--bg3); color: var(--muted); font-weight: 500;
}
.sec h3 {
  margin: 10px 0 8px; font-size: 0.92rem; font-weight: 600;
  color: var(--ink2); display: flex; align-items: center; gap: 6px;
}
.sec h3:first-child { margin-top: 0; }
'@

# Cards grid
Add @'
.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; }
.cards-2 { grid-template-columns: repeat(2, 1fr); }
.cards-3 { grid-template-columns: repeat(3, 1fr); }
.cards-4 { grid-template-columns: repeat(4, 1fr); }
.card {
  background: var(--bg3); border: 1px solid var(--rule);
  border-radius: 12px; padding: 12px 14px;
  position: relative; overflow: hidden;
  min-height: 64px; display: flex; flex-direction: column; justify-content: center;
}
.card::before {
  content: ''; position: absolute; left: 0; top: 0; bottom: 0; width: 3px;
  background: var(--accent); opacity: 0.6;
}
.card-label { font-size: 0.72rem; color: var(--muted); text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 5px; display: flex; align-items: center; gap: 6px; line-height: 1.3; }
.card-label .icon { color: var(--accent); }
.icon-12 { width: 12px; height: 12px; }
.card-value { font-size: 0.95rem; font-weight: 600; color: var(--ink); word-break: break-word; line-height: 1.4; }
.card-sub { font-size: 0.75rem; color: var(--muted); margin-top: 4px; line-height: 1.4; }
'@

# Tables
Add @'
.tbl { width: 100%; border-collapse: separate; border-spacing: 0; margin-top: 4px; font-size: 0.85rem; table-layout: fixed; }
.tbl th {
  background: var(--bg3); padding: 7px 10px; text-align: left;
  font-weight: 600; color: var(--ink2); border-bottom: 2px solid var(--rule);
  font-size: 0.78rem; text-transform: uppercase; letter-spacing: 0.5px;
  white-space: nowrap;
}
.tbl td { padding: 5px 10px; border-bottom: 1px solid var(--rule2); color: var(--ink); vertical-align: middle; line-height: 1.4; }
.tbl tr:hover td { background: var(--bg3); }
.tbl tr:last-child td { border-bottom: none; }
.tbl td.tbl-num, .tbl th.tbl-num { text-align: right; font-variant-numeric: tabular-nums; }
.tbl td.tbl-center, .tbl th.tbl-center { text-align: center; }
.tbl td.tbl-mono { font-family: 'JetBrains Mono','Cascadia Code',Consolas,monospace; font-size: 0.8rem; color: var(--accent); }
.tbl td .code { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 100%; display: inline-block; }

/* Collapsible details/summary */
details.collapse {
  border: 1px solid var(--rule);
  border-radius: 10px;
  background: var(--bg3);
  margin-top: 10px;
  overflow: hidden;
}
details.collapse > summary {
  list-style: none;
  cursor: pointer;
  padding: 10px 14px;
  font-size: 0.92rem;
  font-weight: 600;
  color: var(--ink2);
  display: flex;
  align-items: center;
  gap: 8px;
  user-select: none;
  background: var(--bg3);
  transition: background 0.15s;
}
details.collapse > summary::-webkit-details-marker { display: none; }
details.collapse > summary::before {
  content: '';
  display: inline-block;
  width: 0; height: 0;
  border-left: 5px solid var(--ink2);
  border-top: 4px solid transparent;
  border-bottom: 4px solid transparent;
  margin-right: 4px;
  transition: transform 0.2s;
}
details.collapse[open] > summary::before {
  transform: rotate(90deg);
}
details.collapse > summary:hover { background: var(--rule2); }
details.collapse > summary .count-pill {
  margin-left: auto;
  background: var(--bg2);
  border: 1px solid var(--rule);
  color: var(--muted);
  padding: 2px 10px;
  border-radius: 999px;
  font-size: 0.72rem;
  font-weight: 500;
}
details.collapse > .collapse-body {
  background: var(--bg2);
  padding: 10px;
  border-top: 1px solid var(--rule);
}
.code {
  background: var(--bg3); padding: 2px 6px; border-radius: 4px;
  font-family: 'JetBrains Mono','Cascadia Code',Consolas,monospace;
  font-size: 0.8rem; color: var(--accent);
}
'@

# Badges
Add @'
.badge {
  display: inline-flex; align-items: center; gap: 4px;
  padding: 3px 9px; border-radius: 999px; font-size: 0.72rem;
  font-weight: 600; white-space: nowrap;
}
.badge .icon-12 { width: 11px; height: 11px; }
.badge-ok   { background: rgba(16,185,129,0.12); color: var(--success); }
.badge-warn { background: rgba(245,158,11,0.12); color: var(--warn); }
.badge-err  { background: rgba(239,68,68,0.12); color: var(--danger); }
.badge-info { background: rgba(59,130,246,0.12); color: var(--info); }
.badge-mute { background: var(--bg3); color: var(--muted); }
'@

# Gauges
Add @'
.gauges { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin-bottom: 18px; }
.gauge-card {
  background: var(--bg3); border: 1px solid var(--rule);
  border-radius: 12px; padding: 14px;
  display: flex; flex-direction: column; align-items: center; gap: 8px;
}
.gauge-svg { width: 140px; height: 140px; }
.gauge-val { font-size: 1.5rem; font-weight: 700; fill: var(--ink); font-family: -apple-system, "Segoe UI", sans-serif; }
.gauge-pct { font-size: 0.8rem; fill: var(--muted); font-family: -apple-system, "Segoe UI", sans-serif; }
.gauge-name { font-size: 0.82rem; color: var(--ink2); font-weight: 600; }
.gauge-card.gauge-ok .gauge-name { color: var(--success); }
.gauge-card.gauge-warn .gauge-name { color: var(--warn); }
.gauge-card.gauge-crit .gauge-name { color: var(--danger); }
'@

# Charts (donut, hbar, vbar)
Add @'
.charts-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-bottom: 18px; }
.chart-card {
  background: var(--bg3); border: 1px solid var(--rule);
  border-radius: 12px; padding: 16px;
}
.chart-title {
  font-size: 0.9rem; font-weight: 600; color: var(--ink2);
  margin-bottom: 12px; text-align: center;
}
.donut-svg { width: 180px; height: 180px; display: block; margin: 0 auto; }
.donut-total { font-size: 1.5rem; font-weight: 700; fill: var(--ink); font-family: -apple-system, "Segoe UI", sans-serif; }
.donut-sub { font-size: 0.7rem; fill: var(--muted); font-family: -apple-system, "Segoe UI", sans-serif; }
.legend { display: flex; flex-direction: column; gap: 4px; margin-top: 12px; }
.legend-item { font-size: 0.78rem; color: var(--ink2); display: flex; align-items: center; gap: 6px; }
.legend-item strong { color: var(--ink); margin-left: auto; }
.legend-dot { width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0; }
.hbar-row { display: grid; grid-template-columns: 100px 1fr 70px; gap: 8px; align-items: center; margin-bottom: 8px; }
.hbar-label { font-size: 0.78rem; color: var(--ink2); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.hbar-track { height: 16px; background: var(--bg2); border-radius: 4px; overflow: hidden; border: 1px solid var(--rule); }
.hbar-fill { height: 100%; border-radius: 4px; transition: width 0.8s ease; min-width: 4px; }
.hbar-val { font-size: 0.78rem; color: var(--ink); font-weight: 600; text-align: right; }
.vbar-chart { display: flex; align-items: flex-end; justify-content: space-around; gap: 8px; height: 180px; padding: 10px 0; border-bottom: 1px solid var(--rule); }
.vbar-item { display: flex; flex-direction: column; align-items: center; gap: 4px; flex: 1; max-width: 60px; }
.vbar-value { font-size: 0.75rem; color: var(--ink); font-weight: 600; }
.vbar-bar { width: 100%; border-radius: 4px 4px 0 0; transition: height 0.8s ease; min-height: 4px; }
.vbar-label { font-size: 0.68rem; color: var(--muted); text-align: center; word-break: break-all; line-height: 1.2; max-height: 36px; overflow: hidden; }
'@

# Process rank
Add @'
.rank {
  display: inline-flex; align-items: center; justify-content: center;
  width: 24px; height: 24px; border-radius: 8px; font-size: 0.74rem;
  font-weight: 700; background: var(--bg3); color: var(--ink2);
}
.rank-1 { background: linear-gradient(135deg,#FBBF24,#F59E0B); color: #fff; }
.rank-2 { background: linear-gradient(135deg,#A78BFA,#8B5CF6); color: #fff; }
.rank-3 { background: linear-gradient(135deg,#60A5FA,#3B82F6); color: #fff; }
.proc-bar { display: flex; align-items: center; gap: 6px; }
.proc-bar-track { flex: 1; min-width: 50px; max-width: 100px; height: 6px; background: var(--rule2); border-radius: 3px; overflow: hidden; }
.proc-bar-fill { height: 100%; background: var(--grad-accent); border-radius: 3px; transition: width 0.8s; }
.proc-bar-val { font-size: 0.74rem; font-weight: 600; min-width: 36px; text-align: right; color: var(--ink2); }
'@

# Event log timeline
Add @'
.evt-list { display: flex; flex-direction: column; gap: 8px; max-height: 320px; overflow-y: auto; padding-right: 4px; }
.evt {
  display: flex; align-items: flex-start; gap: 10px; padding: 10px 12px;
  background: var(--bg3); border-radius: 10px; border-left: 3px solid var(--danger);
}
.evt .ts {
  background: var(--bg2); padding: 2px 8px; border-radius: 6px;
  font-family: monospace; font-size: 0.75rem; color: var(--ink2);
  border: 1px solid var(--rule); white-space: nowrap;
}
.evt .src { font-weight: 600; color: var(--ink); font-size: 0.85rem; }
.evt .msg { font-size: 0.78rem; color: var(--muted); margin-top: 2px; word-break: break-word; }
'@

# Theme toggle
Add @'
.theme-btn {
  position: fixed; bottom: 24px; right: 24px;
  width: 46px; height: 46px; border-radius: 50%;
  background: var(--grad-accent); color: #fff; border: none; cursor: pointer;
  box-shadow: var(--shadow-md); z-index: 100;
}
.theme-btn svg { width: 20px; height: 20px; color: #fff; }
'@

# Responsive
Add @'
@media (max-width: 900px) {
  .kpi-row, .gauges { grid-template-columns: repeat(2, 1fr); }
  .cards-3, .cards-4 { grid-template-columns: repeat(2, 1fr); }
  .charts-2 { grid-template-columns: 1fr; }
}
@media (max-width: 600px) {
  .kpi-row, .gauges { grid-template-columns: 1fr; }
  .cards-2, .cards-3, .cards-4 { grid-template-columns: 1fr; }
  .hdr { padding: 18px; }
  .wrap { padding: 14px; grid-template-columns: 1fr; gap: 16px; }
  .nav { position: static; max-height: 240px; }
}
'@

Add '  </style>'
Add '</head>'
Add '<body>'
Add '<div class="wrap">'
Add '  <nav class="nav" id="sideNav">'
Add '    <div class="nav-header">'
Add "      <div class='nav-header-title'>" + ($script:icons['list']) + "导航目录</div>"
Add "      <div class='nav-header-sub'>14 个章节 · 点击跳转</div>"
Add '    </div>'
Add '    <ul>'

# Define section navigation mapping
$sections = @(
    @{ id='overview';      icon='rocket';    title='系统概览' },
    @{ id='hardware';      icon='microchip'; title='硬件资产' },
    @{ id='cpu';           icon='cpu';       title='CPU 信息' },
    @{ id='memory';        icon='mem';       title='内存信息' },
    @{ id='disks';         icon='hdd';       title='磁盘分区' },
    @{ id='disk-health';   icon='heart';     title='物理磁盘健康' },
    @{ id='network';       icon='net';       title='网络' },
    @{ id='processes';     icon='tasks';     title='进程监控' },
    @{ id='services';      icon='cogs';      title='关键服务' },
    @{ id='security';      icon='shield';    title='安全审计' },
    @{ id='events';        icon='list';      title='事件日志摘要' },
    @{ id='tasks';         icon='tasks';     title='计划任务' },
    @{ id='startup';       icon='play';      title='启动项' },
    @{ id='summary';       icon='flag';      title='巡检总结' }
)
$navIdx = 0
foreach ($s in $sections) {
    $navIdx++
    Add ("      <li><a href=`"#sec_$($s.id)`"><span class='nav-num'>$navIdx</span><span class='icon nav-icon'>" + ($script:icons[$s.icon]) + "</span>$($s.title)</a></li>")
}
Add '    </ul>'
Add '    <div class="nav-footer">'
Add '      <span class="nav-footer-badge">14 模块</span>'
Add '      <div style="margin-top:8px;font-size:0.7rem;">实时 · 离线 · 自包含</div>'
Add '    </div>'
Add '  </nav>'
Add '  <div class="main">'

# --- HEADER ---
Add '<div class="hdr">'
Add '  <div class="hdr-title">'
Add ('    <div class="hdr-icon">' + $script:icons['win'] + '</div>')
Add '    <div>'
Add '      <h1>Windows 系统巡检报告</h1>'
Add "      <div class='hdr-sub'>Windows System Inspection Report · $($env:COMPUTERNAME)</div>"
Add '    </div>'
Add '  </div>'
Add '  <div class="hdr-meta">'
$cpuShort = if ($cpu.Name) { ($cpu.Name -split ' ')[0..1] -join ' ' } else { 'CPU' }
Add ("    <div class='meta-pill'><span class='icon icon-14'>" + $script:icons['clock'] + "</span>$($now.ToString('yyyy-MM-dd HH:mm:ss'))</div>")
Add ("    <div class='meta-pill'><span class='icon icon-14'>" + $script:icons['cpu'] + "</span>$cpuShort</div>")
Add ("    <div class='meta-pill'><span class='icon icon-14'>" + $script:icons['desktop'] + "</span>$($os.Caption -replace 'Microsoft ','')</div>")
Add ("    <div class='meta-pill'><span class='icon icon-14'>" + $script:icons['globe'] + "</span>$($tzInfo.DisplayName)</div>")
Add '  </div>'
Add '</div>'

# --- KPI Row ---
Add '<div class="kpi-row">'

# CPU KPI
Add "  <div class='kpi $cpuCard'>"
Add ("    <div class='kpi-label'><span class='icon icon-14'>" + $script:icons['cpu'] + "</span>CPU 使用率</div>")
Add "    <div class='kpi-value'>$cpuLoad<span class='kpi-unit'>%</span></div>"
Add "    <div class='kpi-bar'><div class='kpi-bar-fill' style='width:${cpuLoad}%'></div></div>"
Add "  </div>"

# Memory KPI
Add "  <div class='kpi $memCard'>"
Add ("    <div class='kpi-label'><span class='icon icon-14'>" + $script:icons['mem'] + "</span>内存使用率</div>")
Add "    <div class='kpi-value'>$memPct<span class='kpi-unit'>%</span></div>"
Add "    <div class='kpi-bar'><div class='kpi-bar-fill' style='width:${memPct}%'></div></div>"
Add "  </div>"

# Disk KPI
Add "  <div class='kpi $diskCard'>"
Add ("    <div class='kpi-label'><span class='icon icon-14'>" + $script:icons['hdd'] + "</span>磁盘最大占用</div>")
Add "    <div class='kpi-value'>$diskMaxPct<span class='kpi-unit'>%</span></div>"
Add "    <div class='kpi-bar'><div class='kpi-bar-fill' style='width:${diskMaxPct}%'></div></div>"
Add "  </div>"

# Uptime KPI
Add "  <div class='kpi ok'>"
Add ("    <div class='kpi-label'><span class='icon icon-14'>" + $script:icons['clock'] + "</span>系统运行时长</div>")
Add "    <div class='kpi-value'>$([int]$up.TotalDays)<span class='kpi-unit'>天</span></div>"
Add "    <div class='card-sub'>启动于 $($boot.ToString('yyyy-MM-dd HH:mm'))</div>"
Add "  </div>"

Add '</div>'

# --- SYSTEM OVERVIEW ---
Add '<div class="sec" id="sec_overview">'
Add ('  <h2 class="sec-title">' + (Get-Icon 'rocket' 24) + '系统概览<span class="badge">' + $env:COMPUTERNAME + '</span></h2>')

# 4 gauges
Add '  <div class="gauges">'
Add (Get-Gauge $cpuLoad 'CPU 使用率' 'var(--accent)')
Add (Get-Gauge $memPct '内存使用率' 'var(--accent2)')
Add (Get-Gauge $diskMaxPct '磁盘最大占用' 'var(--warn)')
$netTotal = $tcpStats.Established + $tcpStats.Listen + $tcpStats.TimeWait + $tcpStats.CloseWait
Add (Get-Metric $netTotal '端口连接数' '个 TCP' 'var(--success)')
Add '  </div>'

Add '  <div class="cards cards-4">'

# System cards
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'desktop' 12) + "主机名</div><div class='card-value'>$($env:COMPUTERNAME)</div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'win' 12) + "操作系统</div><div class='card-value'>$($os.Caption)</div><div class='card-sub'>版本 $($os.Version) · Build $($os.BuildNumber)</div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'code' 12) + "系统架构</div><div class='card-value'>$($env:PROCESSOR_ARCHITECTURE)</div><div class='card-sub'>$procTotal 个进程运行中</div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'power' 12) + "启动时间</div><div class='card-value'>$($boot.ToString('MM-dd HH:mm'))</div><div class='card-sub'>已运行 $([int]$up.TotalDays)d $([int]$up.Hours)h $([int]$up.Minutes)m</div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'server' 12) + "制造商</div><div class='card-value'>$($cs.Manufacturer)</div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'tag' 12) + "设备型号</div><div class='card-value'>$($cs.Model)</div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'code' 12) + "序列号</div><div class='card-value'>$($bios.SerialNumber)</div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'globe' 12) + "域名/工作组</div><div class='card-value'>$($cs.Domain)</div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'globe' 12) + "时区</div><div class='card-value'>$($tzInfo.DisplayName)</div><div class='card-sub'>UTC$($tzInfo.BaseUtcOffset.ToString('hh\:mm'))</div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'history' 12) + "系统还原</div><div class='card-value'>$restoreEnabled</div></div>")
$uacStatus = if ($uacReg -and $uacReg.EnableLUA -eq 1) { '已启用' } else { '已禁用' }
$uacBadge  = if ($uacReg -and $uacReg.EnableLUA -eq 1) { 'badge-ok' } else { 'badge-warn' }
$uacIcon = if ($uacReg -and $uacReg.EnableLUA -eq 1) { 'check' } else { 'warn' }
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'shield' 12) + "UAC 用户账户控制</div><div class='card-value'><span class='badge $uacBadge'><span class='icon icon-12'>" + $script:icons[$uacIcon] + "</span>$uacStatus</span></div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'bolt' 12) + "电源计划</div><div class='card-value'>$powerPlan</div></div>")

Add '  </div>'
Add '</div>'

# --- ASSET / HARDWARE ---
Add '<div class="sec" id="sec_hardware">'
Add ("  <h2 class='sec-title'>" + (Get-Icon 'microchip' 24) + "硬件资产</h2>")
Add '  <div class="cards cards-2">'
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'cpu' 12) + "CPU 处理器</div><div class='card-value'>$($cpu.Name)</div><div class='card-sub'>$($cpu.Manufacturer) · $($cpu.NumberOfCores) 核 / $($cpu.NumberOfLogicalProcessors) 线程 · $($cpuClock) GHz</div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'mem' 12) + "总内存</div><div class='card-value'>$memTotalGB GB</div><div class='card-sub'>已用 $memUsedGB GB / 剩余 $memFreeGB GB</div></div>")
# Pick primary GPU: prefer discrete (>= 1 GB VRAM), fallback to integrated (iGPU/APU)
$MIN_VRAM = 1073741824  # 1 GB
$gpuDiscrete = $null
$gpuIntegrated = $null
if ($gpus) {
    foreach ($g in $gpus) {
        $nameLower = if ($g.Name) { $g.Name.ToLower() } else { '' }
        $isVirtual = $false
        foreach ($v in @('virtual', 'todesk', 'gameviewer', 'vmware', 'virtualbox', 'hyper-v', 'microsoft basic', 'remote desktop', 'miracast')) {
            if ($nameLower.Contains($v)) { $isVirtual = $true; break }
        }
        if ($isVirtual) { continue }

        $vram = if ($g.AdapterRAM -and $g.AdapterRAM -gt 0) { $g.AdapterRAM } else { 0 }
        $looksIntegrated = ($vram -lt $MIN_VRAM) -or ($nameLower.Contains('radeon(tm) graphics')) -or ($nameLower.Contains('radeon graphics')) -or ($nameLower.Contains('uhd')) -or ($nameLower.Contains('iris')) -or ($nameLower.Contains('vega')) -or ($nameLower.Contains('integrated'))

        if ($looksIntegrated) {
            if (-not $gpuIntegrated) { $gpuIntegrated = $g }
        } else {
            if (-not $gpuDiscrete) { $gpuDiscrete = $g }
        }
    }
}
if ($gpuDiscrete) { $gpuPrimary = $gpuDiscrete }
elseif ($gpuIntegrated) { $gpuPrimary = $gpuIntegrated }
elseif ($gpus -and @($gpus).Count -gt 0) { $gpuPrimary = $gpus[0] }
else { $gpuPrimary = $null }
$gpuName = if ($gpuPrimary) { $gpuPrimary.Name } else { 'N/A' }
$gpuVram = if ($gpuPrimary -and $gpuPrimary.AdapterRAM -and $gpuPrimary.AdapterRAM -gt 0) { [math]::Round($gpuPrimary.AdapterRAM / 1GB, 1) } else { 0 }
$gpuDisplay = $gpuName
if ($gpuDiscrete -and $gpuIntegrated) {
    # Show both: 独显 + 核显
    $gpuDisplay = "$($gpuDiscrete.Name) <span style='color:var(--muted);font-size:0.75rem;'>+ $($gpuIntegrated.Name)</span>"
} elseif ($gpuIntegrated -and -not $gpuDiscrete) {
    $gpuDisplay = $gpuIntegrated.Name
}
if ($gpuPrimary -and $gpuVram -gt 0) {
    Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'tv' 12) + "显卡 GPU</div><div class='card-value'>$gpuDisplay</div><div class='card-sub'>显存 $gpuVram GB</div></div>")
} elseif ($gpuPrimary) {
    Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'tv' 12) + "显卡 GPU</div><div class='card-value'>$gpuDisplay</div><div class='card-sub'>共享系统内存</div></div>")
} else {
    Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'tv' 12) + "显卡 GPU</div><div class='card-value'>N/A</div></div>")
}
$res = if ($display) { "$($display.ScreenWidth)x$($display.ScreenHeight)" } else { 'N/A' }
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'expand' 12) + "显示器</div><div class='card-value'>$res</div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'server' 12) + "主板</div><div class='card-value'>$($board.Manufacturer) $($board.Product)</div><div class='card-sub'>v$($board.Version)</div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'microchip' 12) + "BIOS</div><div class='card-value'>$($bios.SMBIOSBIOSVersion)</div><div class='card-sub'>$($bios.Manufacturer) · 发布 $($bios.ReleaseDate.ToString('yyyy-MM-dd'))</div></div>")
Add '  </div>'

if ($gpus -and $gpus.Count -gt 0) {
    # Filter out virtual display adapters (Todesk, GameViewer, VirtualBox, VMware, RDP, etc.) - keep all real GPUs including iGPU
    $gpusReal = @()
    foreach ($g in $gpus) {
        $nameLower = if ($g.Name) { $g.Name.ToLower() } else { '' }
        $isVirtual = $false
        foreach ($v in @('virtual', 'todesk', 'gameviewer', 'vmware', 'virtualbox', 'hyper-v', 'microsoft basic', 'remote desktop', 'miracast')) {
            if ($nameLower.Contains($v)) { $isVirtual = $true; break }
        }
        if (-not $isVirtual) { $gpusReal += $g }
    }
    if ($gpusReal.Count -gt 0) {
        Add ('  <h3 style="margin-top:12px;font-size:0.95rem;color:var(--ink2);"><span class="icon icon-14">' + $script:icons['tv'] + '</span> GPU 详情</h3>')
        Add ("  <table class='tbl'><colgroup><col style='width:28%'><col style='width:10%'><col style='width:22%'><col style='width:12%'><col style='width:18%'><col style='width:10%'></colgroup><thead><tr><th>名称</th><th>类型</th><th>驱动版本</th><th>显存</th><th>当前分辨率</th><th>刷新率</th></tr></thead><tbody>")
        foreach ($g in $gpusReal) {
            $vram = if ($g.AdapterRAM -and $g.AdapterRAM -gt 0) { [math]::Round($g.AdapterRAM / 1GB, 1) } else { 0 }
            $resG = "$($g.CurrentHorizontalResolution)×$($g.CurrentVerticalResolution)"
            $hzG  = "$($g.CurrentRefreshRate) Hz"

            # Determine GPU type: integrated if VRAM < 1GB or name matches iGPU patterns
            $nameLower = $g.Name.ToLower()
            $isIntegrated = ($vram -lt 1) -or ($nameLower.Contains('radeon(tm) graphics')) -or ($nameLower.Contains('radeon graphics')) -or ($nameLower.Contains('uhd')) -or ($nameLower.Contains('iris')) -or ($nameLower.Contains('vega')) -or ($nameLower.Contains('integrated'))
            if ($isIntegrated) {
                $vramDisplay = '共享系统内存'
                $typeBadge = "<span class='badge badge-info'>核显</span>"
            } else {
                $vramDisplay = "$vram GB"
                $typeBadge = "<span class='badge badge-ok'>独显</span>"
            }
            if ($resG -eq '×') { $resG = 'N/A' }
            if ($hzG -eq ' Hz') { $hzG = 'N/A' }
            Add "    <tr><td>$($g.Name)</td><td>$typeBadge</td><td><span class='code'>$($g.DriverVersion)</span></td><td>$vramDisplay</td><td>$resG</td><td>$hzG</td></tr>"
        }
        Add '  </tbody></table>'
    }
}
Add '</div>'

# --- CPU Detail ---
Add '<div class="sec" id="sec_cpu">'
Add ("  <h2 class='sec-title'>" + (Get-Icon 'cpu' 24) + "CPU 信息</h2>")
Add '  <div class="cards cards-3">'
Add "    <div class='card'><div class='card-label'>型号</div><div class='card-value'>$($cpu.Name)</div></div>"
Add "    <div class='card'><div class='card-label'>厂商</div><div class='card-value'>$($cpu.Manufacturer)</div></div>"
Add "    <div class='card'><div class='card-label'>物理核心</div><div class='card-value'>$($cpu.NumberOfCores)</div></div>"
Add "    <div class='card'><div class='card-label'>逻辑处理器</div><div class='card-value'>$($cpu.NumberOfLogicalProcessors)</div></div>"
Add "    <div class='card'><div class='card-label'>主频</div><div class='card-value'>$cpuClock GHz</div></div>"
Add "    <div class='card'><div class='card-label'>L2 缓存</div><div class='card-value'>$cpuL2 MB</div></div>"
Add "    <div class='card'><div class='card-label'>L3 缓存</div><div class='card-value'>$cpuL3 MB</div></div>"
Add "    <div class='card'><div class='card-label'>虚拟化</div><div class='card-value'>$($cpu.VirtualizationFirmwareEnabled)</div></div>"
Add '  </div>'
Add '</div>'

# --- Memory ---
Add '<div class="sec" id="sec_memory">'
Add ("  <h2 class='sec-title'>" + (Get-Icon 'mem' 24) + "内存信息</h2>")
Add '  <div class="cards cards-2">'

# Physical memory card with gauge
Add "    <div class='card'>"
Add ("      <div class='card-label'>" + (Get-Icon 'mem' 12) + "物理内存</div>")
Add "      <div style='display:flex;align-items:center;gap:16px;margin-top:8px;'>"
Add (Get-Gauge ([int]$memPct) '内存使用率' 'var(--accent)')
Add "        <div style='flex:1;'>"
Add "          <div style='font-size:1.4rem;font-weight:700;'>$memUsedGB <span style='font-size:0.85rem;color:var(--muted);'>/ $memTotalGB GB</span></div>"
Add "          <div class='card-sub'>剩余 $memFreeGB GB</div>"
Add "        </div>"
Add "      </div>"
Add "    </div>"

# Virtual memory card
Add "    <div class='card'>"
Add ("      <div class='card-label'>" + (Get-Icon 'cogs' 12) + "虚拟内存 (页面文件)</div>")
if ($vmTotalGB -gt 0) {
    Add "      <div style='display:flex;align-items:center;gap:16px;margin-top:8px;'>"
    Add (Get-Gauge ([int]$vmPct) '页面文件' 'var(--accent2)')
    Add "        <div style='flex:1;'>"
    Add "          <div style='font-size:1.4rem;font-weight:700;'>$vmUsedGB <span style='font-size:0.85rem;color:var(--muted);'>/ $vmTotalGB GB</span></div>"
    Add "          <div class='card-sub'>剩余 $vmFreeGB GB</div>"
    Add "        </div>"
    Add "      </div>"
} else {
    Add "      <div class='card-value'>未配置页面文件</div>"
}
Add "    </div>"
Add '  </div>'
Add '</div>'

# --- STORAGE / DISK ---
Add '<div class="sec" id="sec_disks">'
Add ("  <h2 class='sec-title'>" + (Get-Icon 'hdd' 24) + "磁盘分区</h2>")
Add ("  <table class='tbl'><colgroup><col style='width:10%'><col style='width:11%'><col style='width:11%'><col style='width:11%'><col style='width:22%'><col style='width:12%'><col style='width:13%'><col style='width:10%'></colgroup><thead><tr><th>驱动器</th><th>总大小</th><th>已用</th><th>可用</th><th>使用率</th><th>文件系统</th><th>卷标</th><th>状态</th></tr></thead><tbody>")
foreach ($d in $diskRows) {
    $dBadge = if ($d.Pct -ge 90) { 'badge-err' } elseif ($d.Pct -ge 80) { 'badge-warn' } else { 'badge-ok' }
    $dLabel = if ($d.Pct -ge 90) { '危险' } elseif ($d.Pct -ge 80) { '警告' } else { '正常' }
    $dIcon  = if ($d.Pct -ge 90) { 'x' } else { 'check' }
    $barColor = if ($d.Pct -ge 90) { 'var(--danger)' } elseif ($d.Pct -ge 80) { 'var(--warn)' } else { 'var(--success)' }
    Add "    <tr>"
    Add "      <td><strong>$($d.Dev)</strong></td>"
    Add "      <td>$($d.Total) GB</td>"
    Add "      <td>$($d.Used) GB</td>"
    Add "      <td>$($d.Free) GB</td>"
    Add "      <td><div class='proc-bar'><div class='proc-bar-track'><div class='proc-bar-fill' style='width:$($d.Pct)%;background:$barColor;'></div></div><span class='proc-bar-val'>$($d.Pct)%</span></div></td>"
    Add "      <td>$($d.FS)</td>"
    Add "      <td>$($d.Name)</td>"
    Add ("      <td><span class='badge $dBadge'><span class='icon icon-12'>" + $script:icons[$dIcon] + "</span>$dLabel</span></td>")
    Add "    </tr>"
}
Add '  </tbody></table>'
Add '</div>'

# --- Physical Disk Health ---
if ($physDisks) {
    Add '<div class="sec" id="sec_disk-health">'
    Add ("  <h2 class='sec-title'>" + (Get-Icon 'heart' 24) + "物理磁盘健康</h2>")
    Add '  <div class="cards cards-2">'
    foreach ($pd in $physDisks) {
        $hBadge = if ($pd.HealthStatus -eq 'Healthy') { 'badge-ok' } else { 'badge-err' }
        $hIcon  = if ($pd.HealthStatus -eq 'Healthy') { 'check' } else { 'x' }
        $pdSize = if ($pd.Size) { [math]::Round($pd.Size / 1GB, 0) } else { 0 }
        Add "    <div class='card'>"
        Add ("      <div class='card-label'>" + (Get-Icon 'hdd' 12) + "$($pd.FriendlyName)</div>")
        Add "      <div class='card-value'>$($pd.MediaType) · $($pd.BusType) · $pdSize GB</div>"
        Add "      <div style='margin-top:8px;display:flex;gap:8px;flex-wrap:wrap;'>"
        Add ("        <span class='badge $hBadge'><span class='icon icon-12'>" + $script:icons[$hIcon] + "</span> $($pd.HealthStatus)</span>")
        Add "        <span class='badge badge-mute'>运行: $($pd.OperationalStatus)</span>"
        Add "      </div>"
        Add "    </div>"
    }
    Add '  </div>'
    Add '</div>'
}

# --- NETWORK ---
Add '<div class="sec" id="sec_network">'
Add ("  <h2 class='sec-title'>" + (Get-Icon 'net' 24) + "网络</h2>")

# Charts: donut (TCP states) + hbar (event sources)
$tcpSegments = @(
    @{Name='Established'; Value=$tcpStats.Established; Color='var(--success)'},
    @{Name='Listen'; Value=$tcpStats.Listen; Color='var(--accent)'},
    @{Name='TimeWait'; Value=$tcpStats.TimeWait; Color='var(--warn)'},
    @{Name='CloseWait'; Value=$tcpStats.CloseWait; Color='var(--danger)'}
)
Add '  <div class="charts-2">'
Add (Get-Donut 100 100 70 28 $tcpSegments 'TCP 连接状态分布')

# Network traffic vbar
$netVbars = @()
foreach ($n in $netRows) {
    $sentVal = [int]$n.Sent
    $recvVal = [int]$n.Recv
    if ($sentVal -gt 0) { $netVbars += @{Name=$n.Name + '↑'; Value=$sentVal; Color='var(--accent)'} }
    if ($recvVal -gt 0) { $netVbars += @{Name=$n.Name + '↓'; Value=$recvVal; Color='var(--accent2)'} }
}
if ($netVbars.Count -gt 0) {
    Add (Get-VBar $netVbars '网络接口流量 (MB)')
} else {
    Add "  <div class='chart-card'><div class='chart-title'>网络接口流量 (MB)</div><div style='display:flex;align-items:center;justify-content:center;height:200px;color:var(--muted);font-size:0.85rem;'>暂无流量数据</div></div>"
}
Add '  </div>'

# Connection state summary
$totalConn = $tcpStats.Established + $tcpStats.Listen + $tcpStats.TimeWait + $tcpStats.CloseWait
Add '  <div class="cards cards-4" style="margin-bottom:16px;">'
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'link' 12) + "已建立连接</div><div class='card-value' style='color:var(--success);'>$($tcpStats.Established)</div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'plug' 12) + "监听中</div><div class='card-value' style='color:var(--accent);'>$($tcpStats.Listen)</div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'clock' 12) + "TIME-WAIT</div><div class='card-value' style='color:var(--warn);'>$($tcpStats.TimeWait)</div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'warn' 12) + "CLOSE-WAIT</div><div class='card-value' style='color:var(--danger);'>$($tcpStats.CloseWait)</div></div>")
Add '  </div>'

# Network interfaces
if ($netRows.Count -gt 0) {
    Add ('  <h3 style="margin-top:8px;font-size:0.95rem;color:var(--ink2);"><span class="icon icon-14">' + $script:icons['plug'] + '</span> 网络接口</h3>')
    Add ("  <table class='tbl'><colgroup><col style='width:24%'><col style='width:22%'><col style='width:14%'><col style='width:20%'><col style='width:20%'></colgroup><thead><tr><th>接口</th><th>IP 地址</th><th>链路速度</th><th>已发送</th><th>已接收</th></tr></thead><tbody>")
    foreach ($n in $netRows) {
        $sp = if ($n.Speed -gt 0) { "$($n.Speed) Gbps" } else { 'N/A' }
        Add "    <tr><td><strong>$($n.Name)</strong><div class='card-sub'>$($n.Desc)</div></td><td><span class='code'>$($n.IP)</span></td><td>$sp</td><td>$($n.Sent) MB</td><td>$($n.Recv) MB</td></tr>"
    }
    Add '  </tbody></table>'
}

# Listening ports (collapsible)
if ($listenRows.Count -gt 0) {
    $listenCount = $listenRows.Count
    Add ('  <h3 style="margin-top:12px;font-size:0.95rem;color:var(--ink2);"><span class="icon icon-14">' + $script:icons['door'] + '</span> 监听端口</h3>')
    Add "  <details class='collapse'>"
    Add "    <summary><span>Top $listenCount 条监听端口</span><span class='count-pill'>点击展开 / 收起</span></summary>"
    Add "    <div class='collapse-body'>"
    Add ("      <table class='tbl'><colgroup><col style='width:10%'><col style='width:28%'><col style='width:14%'><col style='width:32%'><col style='width:16%'></colgroup><thead><tr><th>协议</th><th>监听地址</th><th>端口</th><th>进程</th><th>PID</th></tr></thead><tbody>")
    foreach ($p in $listenRows) {
        Add "        <tr><td><span class='badge' style='background:rgba(99,102,241,0.12);color:var(--accent);'>$($p.Proto)</span></td><td><span class='code'>$($p.Addr)</span></td><td><strong>$($p.Port)</strong></td><td>$($p.Proc)</td><td><span class='code'>$($p.PID)</span></td></tr>"
    }
    Add '      </tbody></table>'
    Add '    </div>'
    Add '  </details>'
}
Add '</div>'

# --- PROCESSES ---
Add '<div class="sec" id="sec_processes">'
Add ("  <h2 class='sec-title'>" + (Get-Icon 'tasks' 24) + "进程监控<span class='badge'>$procTotal 个进程</span></h2>")

Add '  <div style="display:grid;grid-template-columns:1fr 1fr;gap:14px;">'

# Top memory
Add '    <div>'
Add ("      <h3 style='font-size:0.95rem;color:var(--ink2);margin:0 0 6px;'><span class='icon icon-14'>" + $script:icons['mem'] + "</span> 内存占用 Top 10</h3>")
Add ("      <table class='tbl'><colgroup><col style='width:8%'><col style='width:30%'><col style='width:12%'><col style='width:14%'><col style='width:36%'></colgroup><thead><tr><th>#</th><th>进程</th><th>PID</th><th>内存</th><th>占比</th></tr></thead><tbody>")
$i = 0
foreach ($p in $procMemRows) {
    $i++
    $rk = if ($i -le 3) { "rank-$i" } else { '' }
    Add "      <tr><td><span class='rank $rk'>$i</span></td><td>$($p.Name)</td><td><span class='code'>$($p.PID)</span></td><td><strong>$($p.Mem)</strong> MB</td><td><div class='proc-bar'><div class='proc-bar-track'><div class='proc-bar-fill' style='width:$($p.Bar)%'></div></div><span class='proc-bar-val'>$($p.Bar)%</span></div></td></tr>"
}
Add '      </tbody></table>'
Add '    </div>'

# Top CPU
Add '    <div>'
Add ("      <h3 style='font-size:0.95rem;color:var(--ink2);margin:0 0 6px;'><span class='icon icon-14'>" + $script:icons['bolt'] + "</span> CPU 占用 Top 10</h3>")
Add ("      <table class='tbl'><colgroup><col style='width:8%'><col style='width:30%'><col style='width:12%'><col style='width:14%'><col style='width:36%'></colgroup><thead><tr><th>#</th><th>进程</th><th>PID</th><th>CPU时间</th><th>占比</th></tr></thead><tbody>")
$i = 0
foreach ($p in $procCpuRows) {
    $i++
    $rk = if ($i -le 3) { "rank-$i" } else { '' }
    Add "      <tr><td><span class='rank $rk'>$i</span></td><td>$($p.Name)</td><td><span class='code'>$($p.PID)</span></td><td><strong>$($p.Cpu)</strong> s</td><td><div class='proc-bar'><div class='proc-bar-track'><div class='proc-bar-fill' style='width:$($p.Bar)%'></div></div><span class='proc-bar-val'>$($p.Bar)%</span></div></td></tr>"
}
Add '      </tbody></table>'
Add '    </div>'
Add '  </div>'
Add '</div>'

# --- SERVICES ---
Add '<div class="sec" id="sec_services">'
Add ("  <h2 class='sec-title'>" + (Get-Icon 'cogs' 24) + "关键服务<span class='badge'>$($svcRows.Count) 个 · $svcRunning 运行</span></h2>")

Add '  <div class="cards cards-4" style="margin-bottom:16px;">'
Add "    <div class='card'><div class='card-label'>运行中</div><div class='card-value' style='color:var(--success);'>$svcRunning</div></div>"
Add "    <div class='card'><div class='card-label'>已停止</div><div class='card-value' style='color:var(--warn);'>$svcStopped</div></div>"
Add "    <div class='card'><div class='card-label'>总数</div><div class='card-value'>$($svcRows.Count)</div></div>"
Add "    <div class='card'><div class='card-label'>自动启动</div><div class='card-value'>$(@($svcRows | Where-Object StartType -eq 'Automatic').Count)</div></div>"
Add '  </div>'

Add ("  <table class='tbl'><colgroup><col style='width:14%'><col style='width:42%'><col style='width:22%'><col style='width:22%'></colgroup><thead><tr><th>服务名</th><th>显示名</th><th>状态</th><th>启动类型</th></tr></thead><tbody>")
foreach ($s in $svcRows) {
    $stBadge = if ($s.Status -eq 'Running') { 'badge-ok' } else { 'badge-warn' }
    $stIcon = if ($s.Status -eq 'Running') { 'check' } else { 'warn' }
    $stLabel = if ($s.Status -eq 'Running') { '运行中' } else { '已停止' }
    $ssBadge = if ($s.StartType -eq 'Automatic') { 'badge-ok' } elseif ($s.StartType -eq 'Manual') { 'badge-info' } else { 'badge-mute' }
    Add ("    <tr><td><span class='code'>$($s.Name)</span></td><td>$($s.Display)</td><td><span class='badge $stBadge'><span class='icon icon-12'>" + $script:icons[$stIcon] + "</span>$stLabel</span></td><td><span class='badge $ssBadge'>$($s.StartType)</span></td></tr>")
}
Add '  </tbody></table>'
Add '</div>'

# --- SECURITY ---
Add '<div class="sec" id="sec_security">'
Add ("  <h2 class='sec-title'>" + (Get-Icon 'shield' 24) + "安全审计</h2>")

# Firewall
if ($fwProfiles) {
    Add ('  <h3 style="font-size:0.95rem;color:var(--ink2);margin:0 0 6px;"><span class="icon icon-14">' + $script:icons['shield'] + '</span> 防火墙</h3>')
    Add '  <div class="cards cards-3" style="margin-bottom:18px;">'
    foreach ($f in $fwProfiles) {
        $onBadge = if ($f.Enabled) { 'badge-ok' } else { 'badge-err' }
        $onIcon = if ($f.Enabled) { 'check' } else { 'x' }
        $onLabel = if ($f.Enabled) { '已启用' } else { '已禁用' }
        Add "    <div class='card'>"
        Add "      <div class='card-label'>$($f.Name) 配置文件</div>"
        Add ("      <div class='card-value'><span class='badge $onBadge'><span class='icon icon-12'>" + $script:icons[$onIcon] + "</span>$onLabel</span></div>")
        Add "      <div class='card-sub'>入站: $($f.DefaultInboundAction) · 出站: $($f.DefaultOutboundAction)</div>"
        Add "    </div>"
    }
    Add '  </div>'
}

# Defender
if ($defender) {
    Add ('  <h3 style="font-size:0.95rem;color:var(--ink2);margin:0 0 6px;"><span class="icon icon-14">' + $script:icons['shield'] + '</span> Windows Defender</h3>')
    Add '  <div class="cards cards-4" style="margin-bottom:18px;">'
    $rtBadge = if ($defender.RealTimeProtectionEnabled) { 'badge-ok' } else { 'badge-err' }
    $rtIcon = if ($defender.RealTimeProtectionEnabled) { 'check' } else { 'x' }
    $rtLabel = if ($defender.RealTimeProtectionEnabled) { '已启用' } else { '已禁用' }
    Add ("    <div class='card'><div class='card-label'>实时保护</div><div class='card-value'><span class='badge $rtBadge'><span class='icon icon-12'>" + $script:icons[$rtIcon] + "</span>$rtLabel</span></div></div>")
    Add "    <div class='card'><div class='card-label'>病毒库版本</div><div class='card-value'><span class='code'>$($defender.AntivirusSignatureVersion)</span></div><div class='card-sub'>$($defender.AntivirusSignatureLastUpdated.ToString('yyyy-MM-dd HH:mm'))</div></div>"
    Add "    <div class='card'><div class='card-label'>上次扫描</div><div class='card-value' style='font-size:0.85rem;'>$($defender.LastQuickScanEndTime.ToString('MM-dd HH:mm'))</div></div>"
    Add "    <div class='card'><div class='card-label'>高危威胁</div><div class='card-value' style='color:var(--danger);'>$($defender.ThreatSeverityHighCount)</div></div>"
    Add '  </div>'
}

# BitLocker
if ($blVolumes -and $blVolumes.Count -gt 0) {
    Add ('  <h3 style="font-size:0.95rem;color:var(--ink2);margin:0 0 6px;"><span class="icon icon-14">' + $script:icons['lock'] + '</span> BitLocker 加密</h3>')
    Add ("  <table class='tbl' style='margin-bottom:18px;'><colgroup><col style='width:22%'><col style='width:30%'><col style='width:22%'><col style='width:26%'></colgroup><thead><tr><th>卷</th><th>保护状态</th><th>加密进度</th><th>加密方法</th></tr></thead><tbody>")
    foreach ($v in $blVolumes) {
        $vb = if ($v.ProtectionStatus -eq 'On') { 'badge-ok' } else { 'badge-warn' }
        $vi = if ($v.ProtectionStatus -eq 'On') { 'lock' } else { 'warn' }
        $vl = if ($v.ProtectionStatus -eq 'On') { '已加密' } else { '未加密' }
        Add ("    <tr><td><strong>$($v.MountPoint)</strong></td><td><span class='badge $vb'><span class='icon icon-12'>" + $script:icons[$vi] + "</span>$vl</span></td><td>$($v.EncryptionPercentage)%</td><td>$($v.EncryptionMethod)</td></tr>")
    }
    Add '  </tbody></table>'
}

# Hotfix
Add ('  <h3 style="font-size:0.95rem;color:var(--ink2);margin:0 0 6px;"><span class="icon icon-14">' + $script:icons['sync'] + '</span> 系统更新</h3>')
Add '  <div class="cards cards-3" style="margin-bottom:18px;">'
if ($lastHot) {
    Add "    <div class='card'><div class='card-label'>最新补丁</div><div class='card-value'><span class='code'>$($lastHot.HotFixID)</span></div><div class='card-sub'>$($lastHot.InstalledOn.ToString('yyyy-MM-dd')) · $($lastHot.Description)</div></div>"
} else {
    Add "    <div class='card'><div class='card-label'>最新补丁</div><div class='card-value'>无记录</div></div>"
}
Add "    <div class='card'><div class='card-label'>已安装补丁</div><div class='card-value'>$hotCount</div></div>"
$upDays = if ($lastHot) { [int]((Get-Date) - $lastHot.InstalledOn).TotalDays } else { -1 }
$upLabel = if ($upDays -eq -1) { '未知' } elseif ($upDays -gt 60) { "滞后 $upDays 天" } else { "$upDays 天前" }
$upBadge = if ($upDays -gt 60) { 'badge-warn' } else { 'badge-ok' }
Add "    <div class='card'><div class='card-label'>更新状态</div><div class='card-value'><span class='badge $upBadge'>$upLabel</span></div></div>"
Add '  </div>'

# Users
Add ('  <h3 style="font-size:0.95rem;color:var(--ink2);margin:0 0 6px;"><span class="icon icon-14">' + $script:icons['users'] + '</span> 本地用户</h3>')
if ($localUsers) {
    Add "  <table class='tbl'><colgroup><col style='width:24%'><col style='width:30%'><col style='width:18%'><col style='width:28%'></colgroup><thead><tr><th>用户名</th><th>全名</th><th>状态</th><th>上次登录</th></tr></thead><tbody>"
    foreach ($u in ($localUsers | Select-Object -First 15)) {
        $ub = if ($u.Enabled) { 'badge-ok' } else { 'badge-warn' }
        $ui = if ($u.Enabled) { 'check' } else { 'x' }
        $ul = if ($u.Enabled) { '启用' } else { '禁用' }
        $ll = if ($u.LastLogon -and $u.LastLogon.Year -gt 1970) { $u.LastLogon.ToString('yyyy-MM-dd') } else { '从未' }
        Add ("    <tr><td><strong>$($u.Name)</strong></td><td>$($u.FullName)</td><td><span class='badge $ub'><span class='icon icon-12'>" + $script:icons[$ui] + "</span>$ul</span></td><td>$ll</td></tr>")
    }
    Add '  </tbody></table>'
}

# Logged on users
if ($loggedOnRows.Count -gt 0) {
    Add ('  <h3 style="font-size:0.95rem;color:var(--ink2);margin:18px 0 10px;"><span class="icon icon-14">' + $script:icons['user'] + '</span> 当前登录</h3>')
    Add '  <table class="tbl"><thead><tr><th>用户</th><th>会话</th><th>状态</th><th>登录时间</th></tr></thead><tbody>'
    foreach ($u in $loggedOnRows) {
        Add ("    <tr><td><strong>$($u.User)</strong></td><td><span class='code'>$($u.Session)</span></td><td><span class='badge badge-ok'><span class='icon icon-12'>" + $script:icons['check'] + "</span>$($u.State)</span></td><td>$($u.LoginTime)</td></tr>")
    }
    Add '  </tbody></table>'
}
Add '</div>'

# --- EVENT LOG ---
Add '<div class="sec" id="sec_events">'
Add ("  <h2 class='sec-title'>" + (Get-Icon 'list' 24) + "事件日志摘要</h2>")

# Event source chart
$evtBySource = @()
if ($evtAll) {
    $evtBySource = @($evtAll | Group-Object Source | Sort-Object Count -Descending | Select-Object -First 8)
    $hbarItems = @()
    foreach ($e in $evtBySource) {
        $hbarItems += @{Name=$e.Name; Value=$e.Count; Color='var(--danger)'}
    }
    Add '  <div class="charts-2">'
    Add (Get-HBar $hbarItems '系统错误事件来源 Top 8' '次')

    # Event log summary donut (with warning rings)
    $evtSegments = @(
        @{Name='系统错误'; Value=$sysErrors; Color='var(--danger)'},
        @{Name='系统警告'; Value=$sysWarnings; Color='var(--warn)'},
        @{Name='应用错误'; Value=$appErrors; Color='var(--accent)'},
        @{Name='应用警告'; Value=$appWarnings; Color='var(--info)'}
    )
    Add (Get-Donut 100 100 70 28 $evtSegments '事件日志分类分布')
    Add '  </div>'
}

# KPI cards
Add '  <div class="cards cards-4" style="margin-bottom:16px;">'
$seBadge = if ($sysErrors -gt 20) { 'badge-err' } elseif ($sysErrors -gt 5) { 'badge-warn' } else { 'badge-ok' }
$swBadge = if ($sysWarnings -gt 50) { 'badge-warn' } else { 'badge-ok' }
$aeBadge = if ($appErrors -gt 20) { 'badge-err' } elseif ($appErrors -gt 5) { 'badge-warn' } else { 'badge-ok' }
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'fire' 12) + "系统日志错误</div><div class='card-value'><span class='badge $seBadge'>$sysErrors</span></div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'warn' 12) + "系统日志警告</div><div class='card-value'><span class='badge $swBadge'>$sysWarnings</span></div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'fire' 12) + "应用日志错误</div><div class='card-value'><span class='badge $aeBadge'>$appErrors</span></div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'warn' 12) + "应用日志警告</div><div class='card-value'><span class='badge $swBadge'>$appWarnings</span></div></div>")
Add '  </div>'

if ($recentEvents.Count -gt 0) {
    Add ("  <h3 style='font-size:0.95rem;color:var(--ink2);margin:0 0 6px;'><span class='icon icon-14'>" + $script:icons['warn'] + "</span> 最近系统错误事件</h3>")
    Add '  <div class="evt-list">'
    foreach ($e in $recentEvents) {
        Add "    <div class='evt'><span class='ts'>$($e.Time)</span><div style='flex:1;'><div class='src'>$($e.Source)</div><div class='msg'>$($e.Msg)</div></div></div>"
    }
    Add '  </div>'
}
Add '</div>'

# --- SCHEDULED TASKS ---
Add '<div class="sec" id="sec_tasks">'
Add ("  <h2 class='sec-title'>" + (Get-Icon 'tasks' 24) + "计划任务<span class='badge'>$taskTotal 个非微软任务</span></h2>")
Add '  <div class="cards cards-4">'
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'cogs' 12) + "总数</div><div class='card-value'>$taskTotal</div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'play' 12) + "正在运行</div><div class='card-value' style='color:var(--success);'>$taskRunning</div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'check' 12) + "准备就绪</div><div class='card-value' style='color:var(--info);'>$taskReady</div></div>")
Add ("    <div class='card'><div class='card-label'>" + (Get-Icon 'warn' 12) + "已禁用</div><div class='card-value' style='color:var(--muted);'>$taskDisabled</div></div>")
Add '  </div>'
Add '</div>'

# --- STARTUP PROGRAMS ---
if ($startupCount -gt 0) {
    Add '<div class="sec" id="sec_startup">'
    Add ("  <h2 class='sec-title'>" + (Get-Icon 'play' 24) + "启动项<span class='badge'>$startupCount 个</span></h2>")
    Add "  <table class='tbl'><colgroup><col style='width:18%'><col style='width:42%'><col style='width:24%'><col style='width:16%'></colgroup><thead><tr><th>名称</th><th>命令</th><th>位置</th><th>用户</th></tr></thead><tbody>"
    foreach ($s in $startupRaw) {
        $cmd = if ($s.Command) { ($s.Command -split '\|')[0] } else { '' }
        if ($cmd.Length -gt 60) { $cmd = $cmd.Substring(0, 60) + '...' }
        $loc = if ($s.Location) { $s.Location } else { '' }
        Add "    <tr><td><strong>$($s.Name)</strong></td><td><span class='code' style='font-size:0.75rem;'>$cmd</span></td><td>$loc</td><td>$($s.User)</td></tr>"
    }
    Add '  </tbody></table>'
    Add '</div>'
}

# --- SUMMARY ---
Add '<div class="sec" id="sec_summary" style="background:var(--grad-card);">'
Add ("  <h2 class='sec-title'>" + (Get-Icon 'flag' 24) + "巡检总结</h2>")
Add '  <div style="display:flex;align-items:center;gap:30px;flex-wrap:wrap;">'

# Health gauge
Add "    <div style='flex-shrink:0;'>"
Add (Get-Gauge $healthScore "$healthLabel" $healthColor)
Add "    </div>"

Add "    <div style='flex:1;min-width:260px;'>"
Add "      <h3 style='margin:0 0 12px;font-size:1.1rem;'>系统健康分</h3>"
Add '      <div class="cards cards-3">'
Add ("        <div class='card'><div class='card-label'>" + (Get-Icon 'check' 12) + "正常</div><div class='card-value' style='color:var(--success);'>$ok</div></div>")
Add ("        <div class='card'><div class='card-label'>" + (Get-Icon 'warn' 12) + "警告</div><div class='card-value' style='color:var(--warn);'>$warn</div></div>")
Add ("        <div class='card'><div class='card-label'>" + (Get-Icon 'x' 12) + "危险</div><div class='card-value' style='color:var(--danger);'>$crit</div></div>")
Add '      </div>'
Add "      <p style='margin-top:14px;color:var(--ink2);font-size:0.88rem;'>本次巡检完成时间: $($now.ToString('yyyy-MM-dd HH:mm:ss'))</p>"
Add "      <p style='margin:6px 0 0;color:var(--muted);font-size:0.82rem;'>共检查 12 个分类模块: 系统 · 硬件 · CPU · 内存 · 磁盘 · 网络 · 进程 · 服务 · 安全 · 事件 · 任务 · 启动项</p>"
Add "    </div>"
Add '  </div>'
Add '</div>'


# Theme toggle
Add ('<button class="theme-btn" id="themeBtn" onclick="toggleTheme()">' + $script:icons['moon'] + '</button>')

# JavaScript (minimal - just for theme toggle)
Add '<script>'
Add @'
function toggleTheme() {
  const html = document.documentElement;
  const cur = html.getAttribute('data-theme');
  html.setAttribute('data-theme', cur === 'dark' ? 'default' : 'dark');
  const btn = document.getElementById('themeBtn');
  btn.innerHTML = cur === 'dark' ? '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1111.21 3 7 7 0 0021 12.79z"/></svg>' : '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>';
}
window.addEventListener('load', () => {
  document.querySelectorAll('.proc-bar-fill, .kpi-bar-fill, .hbar-fill, .vbar-bar').forEach(el => {
    const w = el.style.width || (el.style.height + '');
    if (el.style.width) {
      el.style.width = '0';
      setTimeout(() => { el.style.width = w; }, 100);
    }
  });
});

// Scroll spy for nav highlighting
const navLinks = document.querySelectorAll('.nav li a');
const sectionIds = Array.from(navLinks).map(a => a.getAttribute('href').substring(1));
const sections = sectionIds.map(id => document.getElementById(id)).filter(Boolean);

if (sections.length > 0) {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        const id = entry.target.id;
        navLinks.forEach(a => {
          a.classList.toggle('active', a.getAttribute('href') === '#' + id);
        });
      }
    });
  }, { rootMargin: '-20% 0px -70% 0px', threshold: 0 });

  sections.forEach(s => observer.observe(s));
}
'@
Add '</script>'

Add '</div>'  # close main
Add '</div>'  # close wrap
Add '</body></html>'

# ============================================================
# Write file
# ============================================================
$html = $sb.ToString()
$utf8Bom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($report, $html, $utf8Bom)

Write-Host "[3/3] Report generated: $report" -ForegroundColor Green
Write-Host ""
Write-Host "Statistics:" -ForegroundColor Yellow
Write-Host "  - Disks: $($diskRows.Count)"
Write-Host "  - Processes: $procTotal"
Write-Host "  - Services: $($svcRows.Count) (Running: $svcRunning)"
Write-Host "  - Hotfixes: $hotCount"
Write-Host "  - Tasks: $taskTotal"
Write-Host "  - Event errors: sys=$sysErrors app=$appErrors"
Write-Host "  - Health score: $healthScore ($healthLabel)"
