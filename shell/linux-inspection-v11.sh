#!/bin/bash
set -o pipefail

# ============================================================
# Linux Inspection Script v11
# Generate multi-theme HTML inspection report (Light/White-Blue/Dark)
# ============================================================

export LC_ALL=C
export LANG=C

HTML_REPORT="system_inspection_$(date +%Y%m%d_%H%M%S).html"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
ORANGE='\033[0;33m'
NC='\033[0m'

# ------------------------------------------------------------
# 前置检查
# ------------------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${YELLOW}[WARN] 当前非 root 权限运行，部分巡检项可能无法获取完整信息${NC}"
fi

check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${YELLOW}[WARN] 命令未找到: $cmd (相关功能将被跳过)${NC}"
        return 1
    fi
    return 0
}

echo -e "${BLUE}[1/4] 检查系统环境与依赖命令...${NC}"
check_command df
check_command free
check_command uptime
check_command ps
check_command ip

check_command systemctl && SYSTEMCTL_AVAILABLE=1
check_command ss && SS_AVAILABLE=1
check_command top && TOP_AVAILABLE=1
check_command docker && DOCKER_AVAILABLE=1
check_command ufw && UFW_AVAILABLE=1
check_command firewall-cmd && FIREWALLD_AVAILABLE=1
check_command iptables && IPTABLES_AVAILABLE=1

# ------------------------------------------------------------
# 工具函数
# ------------------------------------------------------------

compare_float() {
    awk -v a="$1" -v b="$2" 'BEGIN { exit !(a >= b) }'
}

get_cpu_usage() {
    if [ -n "$TOP_AVAILABLE" ]; then
        top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{printf "%.1f", 100 - $1}'
    elif [ -f /proc/stat ]; then
        local cpu_line1 cpu_line2 idle1 idle2 total1 total2 diff_idle diff_total
        cpu_line1=$(head -1 /proc/stat)
        idle1=$(echo "$cpu_line1" | awk '{print $5}')
        total1=$(echo "$cpu_line1" | awk '{s=0; for(i=2;i<=NF;i++) s+=$i; print s}')
        sleep 0.1
        cpu_line2=$(head -1 /proc/stat)
        idle2=$(echo "$cpu_line2" | awk '{print $5}')
        total2=$(echo "$cpu_line2" | awk '{s=0; for(i=2;i<=NF;i++) s+=$i; print s}')
        diff_idle=$((idle2 - idle1))
        diff_total=$((total2 - total1))
        awk -v idle="$diff_idle" -v total="$diff_total" 'BEGIN { printf "%.1f", (total - idle) / total * 100 }'
    else
        echo "0.0"
    fi
}

get_memory_usage() {
    free | grep Mem | awk '{printf "%.1f", $3/$2 * 100}'
}

get_disk_usage() {
    df -h 2>/dev/null | awk 'NR>1 && !/tmpfs|devtmpfs|overlay/ {gsub(/%/,"",$5); if($5+0 > max+0) {max=$5; }} END {printf "%d", max+0}'
}

get_uptime_formatted() {
    awk '{printf "%.2f天", $1/86400}' /proc/uptime 2>/dev/null || echo "未知"
}

get_card_status() {
    local usage="$1"
    if compare_float "$usage" 90; then
        echo "critical"
    elif compare_float "$usage" 80; then
        echo "warning"
    else
        echo "ok"
    fi
}

add_status_badge() {
    local label="$1"
    local level="$2"
    case "$level" in
        "warning")  echo "<span class=\"status-badge status-warning\"><i class=\"fas fa-exclamation-triangle\"></i> $label</span>" ;;
        "critical") echo "<span class=\"status-badge status-critical\"><i class=\"fas fa-times-circle\"></i> $label</span>" ;;
        "info")     echo "<span class=\"status-badge status-info\"><i class=\"fas fa-info-circle\"></i> $label</span>" ;;
        *)          echo "<span class=\"status-badge status-ok\"><i class=\"fas fa-check-circle\"></i> $label</span>" ;;
    esac
}

html_escape() {
    sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g'
}

add_section() {
    local title="$1"
    local icon="$2"
    local extra_class="$3"
    local section_id="${title// /-}"
    echo "<div class=\"section fade-in ${extra_class}\" data-section=\"${section_id}\" id=\"sec-${section_id}\">" >> "$HTML_REPORT"
    echo "<h2 class=\"section-title collapsible-header\" onclick=\"toggleSection(this)\"><i class=\"${icon}\"></i>${title}<i class=\"fas fa-chevron-down collapse-icon\"></i></h2>" >> "$HTML_REPORT"
    echo "<div class=\"section-body\">" >> "$HTML_REPORT"
}

end_section() {
    echo "</div></div>" >> "$HTML_REPORT"
}

# ------------------------------------------------------------
# 收集系统指标
# ------------------------------------------------------------
echo -e "${CYAN}[2/4] 采集系统运行指标...${NC}"

CPU_USAGE=$(get_cpu_usage)
MEM_USAGE=$(get_memory_usage)
DISK_USAGE=$(get_disk_usage)
UPTIME_DAYS=$(get_uptime_formatted)

CPU_CARD_STATUS=$(get_card_status "$CPU_USAGE")
MEM_CARD_STATUS=$(get_card_status "$MEM_USAGE")
DISK_CARD_STATUS=$(get_card_status "$DISK_USAGE")

# ------------------------------------------------------------
# 生成 HTML 报告
# ------------------------------------------------------------
echo -e "${BLUE}[3/4] 生成巡检报告...${NC}"

cat > "$HTML_REPORT" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="zh-CN" data-theme="light">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Linux巡检报告</title>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">

    <script>(function(){var t=localStorage.getItem('li-theme')||'light';document.documentElement.setAttribute('data-theme',t);})();</script>
    <style>
        /* ===== 主题：浅色（默认） ===== */
        :root, [data-theme="light"] {
            --bg-page: #F5F7FA; --bg-card: #FFFFFF; --bg-sidebar: rgba(255,255,255,0.98);
            --bg-header: #FFFFFF; --bg-code: #F8FAFC; --bg-table: #FFFFFF;
            --bg-tab-active: rgba(99,102,241,0.08); --bg-input: #F8FAFC;
            --bg-timestamp: linear-gradient(135deg, rgba(99,102,241,0.06), rgba(168,85,247,0.04));
            --bg-metric: rgba(99,102,241,0.03); --row-alt: rgba(99,102,241,0.02);
            --primary-color: #6366F1; --primary-light: #818CF8; --accent-color: #A855F7;
            --text-primary: #1F2937; --text-secondary: #6B7280; --text-muted: #9CA3AF;
            --border-color: #E5E7EB; --border-light: #F3F4F6;
            --shadow-card: 0 1px 3px rgba(0,0,0,0.05), 0 4px 12px rgba(0,0,0,0.04);
            --shadow-hover: 0 4px 12px rgba(99,102,241,0.08), 0 16px 40px rgba(0,0,0,0.08);
            --success-color: #22C55E; --warning-color: #F59E0B; --danger-color: #EF4444; --info-color: #3B82F6;
            --code-text: #6366F1; --grid-opacity: 0.02; --particle-opacity: 0.06;
            --title-gradient: linear-gradient(45deg, #6366F1, #818CF8, #A855F7, #6366F1);
            --title-shadow: none; --nav-text: #6B7280; --th-text: #fff;
            --stat-icon-shadow: 0 0 15px rgba(99,102,241,0.15);
            --card-accent: linear-gradient(90deg, var(--primary-color), var(--accent-color));
            --icon-bg: rgba(99,102,241,0.1); --nav-width: 240px;
        }
        /* ===== 主题：白蓝 ===== */
        [data-theme="white-blue"] {
            --bg-page: #EFF6FF; --bg-card: #FFFFFF; --bg-sidebar: rgba(255,255,255,0.98);
            --bg-header: #FFFFFF; --bg-code: #F0F7FF; --bg-table: #FFFFFF;
            --bg-tab-active: rgba(59,130,246,0.08); --bg-input: #F0F7FF;
            --bg-timestamp: linear-gradient(135deg, rgba(59,130,246,0.06), rgba(14,165,233,0.04));
            --bg-metric: rgba(59,130,246,0.03); --row-alt: rgba(59,130,246,0.02);
            --primary-color: #3B82F6; --primary-light: #60A5FA; --accent-color: #0EA5E9;
            --text-primary: #1E40AF; --text-secondary: #64748B; --text-muted: #94A3B8;
            --border-color: #BFDBFE; --border-light: #DBEAFE;
            --shadow-card: 0 1px 3px rgba(59,130,246,0.04), 0 4px 12px rgba(59,130,246,0.06);
            --shadow-hover: 0 4px 12px rgba(59,130,246,0.1), 0 16px 40px rgba(59,130,246,0.1);
            --success-color: #22C55E; --warning-color: #F59E0B; --danger-color: #EF4444; --info-color: #0EA5E9;
            --code-text: #2563EB; --grid-opacity: 0.02; --particle-opacity: 0.06;
            --title-gradient: linear-gradient(45deg, #3B82F6, #60A5FA, #0EA5E9, #3B82F6);
            --title-shadow: none; --nav-text: #64748B; --th-text: #fff;
            --stat-icon-shadow: 0 0 15px rgba(59,130,246,0.15);
            --card-accent: linear-gradient(90deg, var(--primary-color), var(--accent-color));
            --icon-bg: rgba(59,130,246,0.1);
        }
        /* ===== 主题：暗黑 ===== */
        [data-theme="dark"] {
            --bg-page: #0F172A; --bg-card: #1E293B; --bg-sidebar: rgba(15,23,42,0.92);
            --bg-header: rgba(30,41,59,0.6); --bg-code: #0F172A; --bg-table: rgba(15,23,42,0.4);
            --bg-tab-active: rgba(129,140,248,0.12); --bg-input: rgba(15,23,42,0.6);
            --bg-timestamp: linear-gradient(135deg, rgba(30,41,59,0.8), rgba(51,65,85,0.5));
            --bg-metric: rgba(255,255,255,0.03); --row-alt: rgba(255,255,255,0.02);
            --primary-color: #818CF8; --primary-light: #A5B4FC; --accent-color: #C084FC;
            --text-primary: #E2E8F0; --text-secondary: #94A3B8; --text-muted: #64748B;
            --border-color: rgba(255,255,255,0.08); --border-light: rgba(255,255,255,0.04);
            --shadow-card: 0 4px 16px rgba(0,0,0,0.2), 0 1px 3px rgba(0,0,0,0.3);
            --shadow-hover: 0 8px 32px rgba(0,0,0,0.3), 0 4px 12px rgba(129,140,248,0.1);
            --success-color: #4ADE80; --warning-color: #FBBF24; --danger-color: #F87171; --info-color: #60A5FA;
            --code-text: #A5B4FC; --grid-opacity: 0.1; --particle-opacity: 0.3;
            --title-gradient: linear-gradient(45deg, #818CF8, #22D3EE, #C084FC, #818CF8);
            --title-shadow: 0 0 30px rgba(129,140,248,0.35); --nav-text: #94A3B8; --th-text: #fff;
            --stat-icon-shadow: 0 0 20px rgba(129,140,248,0.3);
            --card-accent: linear-gradient(90deg, var(--primary-color), var(--accent-color));
            --icon-bg: rgba(129,140,248,0.12);
        }
        /* ===== 主题：护眼绿 ===== */
        [data-theme="green"] {
            --bg-page: #F0FDF4; --bg-card: #FFFFFF; --bg-sidebar: rgba(255,255,255,0.98);
            --bg-header: #FFFFFF; --bg-code: #F0FDF4; --bg-table: #FFFFFF;
            --bg-tab-active: rgba(16,185,129,0.08); --bg-input: #F0FDF4;
            --bg-timestamp: linear-gradient(135deg, rgba(16,185,129,0.06), rgba(5,150,105,0.04));
            --bg-metric: rgba(16,185,129,0.03); --row-alt: rgba(16,185,129,0.02);
            --primary-color: #10B981; --primary-light: #34D399; --accent-color: #059669;
            --text-primary: #064E3B; --text-secondary: #6B7280; --text-muted: #9CA3AF;
            --border-color: #BBF7D0; --border-light: #DCFCE7;
            --shadow-card: 0 1px 3px rgba(16,185,129,0.04), 0 4px 12px rgba(16,185,129,0.06);
            --shadow-hover: 0 4px 12px rgba(16,185,129,0.1), 0 16px 40px rgba(16,185,129,0.1);
            --success-color: #22C55E; --warning-color: #F59E0B; --danger-color: #EF4444; --info-color: #3B82F6;
            --code-text: #059669; --grid-opacity: 0.02; --particle-opacity: 0.06;
            --title-gradient: linear-gradient(45deg, #10B981, #34D399, #059669, #10B981);
            --title-shadow: none; --nav-text: #6B7280; --th-text: #fff;
            --stat-icon-shadow: 0 0 15px rgba(16,185,129,0.15);
            --card-accent: linear-gradient(90deg, var(--primary-color), var(--accent-color));
            --icon-bg: rgba(16,185,129,0.1);
        }
        /* ===== 主题：暖橙 ===== */
        [data-theme="warm"] {
            --bg-page: #FFF7ED; --bg-card: #FFFFFF; --bg-sidebar: rgba(255,255,255,0.98);
            --bg-header: #FFFFFF; --bg-code: #FFF7ED; --bg-table: #FFFFFF;
            --bg-tab-active: rgba(249,115,22,0.08); --bg-input: #FFF7ED;
            --bg-timestamp: linear-gradient(135deg, rgba(249,115,22,0.06), rgba(234,88,12,0.04));
            --bg-metric: rgba(249,115,22,0.03); --row-alt: rgba(249,115,22,0.02);
            --primary-color: #F97316; --primary-light: #FB923C; --accent-color: #EA580C;
            --text-primary: #7C2D12; --text-secondary: #78350F; --text-muted: #9A3412;
            --border-color: #FED7AA; --border-light: #FFEDD5;
            --shadow-card: 0 1px 3px rgba(249,115,22,0.04), 0 4px 12px rgba(249,115,22,0.06);
            --shadow-hover: 0 4px 12px rgba(249,115,22,0.1), 0 16px 40px rgba(249,115,22,0.1);
            --success-color: #22C55E; --warning-color: #F59E0B; --danger-color: #EF4444; --info-color: #3B82F6;
            --code-text: #EA580C; --grid-opacity: 0.02; --particle-opacity: 0.06;
            --title-gradient: linear-gradient(45deg, #F97316, #FB923C, #EA580C, #F97316);
            --title-shadow: none; --nav-text: #78350F; --th-text: #fff;
            --stat-icon-shadow: 0 0 15px rgba(249,115,22,0.15);
            --card-accent: linear-gradient(90deg, var(--primary-color), var(--accent-color));
            --icon-bg: rgba(249,115,22,0.1);
        }
        /* ===== 主题：玫红 ===== */
        [data-theme="rose"] {
            --bg-page: #FFF1F2; --bg-card: #FFFFFF; --bg-sidebar: rgba(255,255,255,0.98);
            --bg-header: #FFFFFF; --bg-code: #FFF1F2; --bg-table: #FFFFFF;
            --bg-tab-active: rgba(225,29,72,0.08); --bg-input: #FFF1F2;
            --bg-timestamp: linear-gradient(135deg, rgba(225,29,72,0.06), rgba(190,18,60,0.04));
            --bg-metric: rgba(225,29,72,0.03); --row-alt: rgba(225,29,72,0.02);
            --primary-color: #E11D48; --primary-light: #F43F5E; --accent-color: #BE123C;
            --text-primary: #881337; --text-secondary: #9F1239; --text-muted: #BE123C;
            --border-color: #FECDD3; --border-light: #FFE4E6;
            --shadow-card: 0 1px 3px rgba(225,29,72,0.04), 0 4px 12px rgba(225,29,72,0.06);
            --shadow-hover: 0 4px 12px rgba(225,29,72,0.1), 0 16px 40px rgba(225,29,72,0.1);
            --success-color: #22C55E; --warning-color: #F59E0B; --danger-color: #EF4444; --info-color: #3B82F6;
            --code-text: #BE123C; --grid-opacity: 0.02; --particle-opacity: 0.06;
            --title-gradient: linear-gradient(45deg, #E11D48, #F43F5E, #BE123C, #E11D48);
            --title-shadow: none; --nav-text: #9F1239; --th-text: #fff;
            --stat-icon-shadow: 0 0 15px rgba(225,29,72,0.15);
            --card-accent: linear-gradient(90deg, var(--primary-color), var(--accent-color));
            --icon-bg: rgba(225,29,72,0.1);
        }
        /* ===== 主题：深空灰 ===== */
        [data-theme="slate"] {
            --bg-page: #1E293B; --bg-card: #334155; --bg-sidebar: rgba(15,23,42,0.92);
            --bg-header: rgba(51,65,85,0.6); --bg-code: #1E293B; --bg-table: rgba(15,23,42,0.4);
            --bg-tab-active: rgba(56,189,248,0.12); --bg-input: rgba(15,23,42,0.6);
            --bg-timestamp: linear-gradient(135deg, rgba(51,65,85,0.8), rgba(71,85,105,0.5));
            --bg-metric: rgba(255,255,255,0.03); --row-alt: rgba(255,255,255,0.02);
            --primary-color: #38BDF8; --primary-light: #7DD3FC; --accent-color: #0EA5E9;
            --text-primary: #E2E8F0; --text-secondary: #94A3B8; --text-muted: #64748B;
            --border-color: rgba(255,255,255,0.08); --border-light: rgba(255,255,255,0.04);
            --shadow-card: 0 4px 16px rgba(0,0,0,0.2), 0 1px 3px rgba(0,0,0,0.3);
            --shadow-hover: 0 8px 32px rgba(0,0,0,0.3), 0 4px 12px rgba(56,189,248,0.1);
            --success-color: #4ADE80; --warning-color: #FBBF24; --danger-color: #F87171; --info-color: #60A5FA;
            --code-text: #7DD3FC; --grid-opacity: 0.08; --particle-opacity: 0.25;
            --title-gradient: linear-gradient(45deg, #38BDF8, #7DD3FC, #0EA5E9, #38BDF8);
            --title-shadow: 0 0 30px rgba(56,189,248,0.3); --nav-text: #94A3B8; --th-text: #fff;
            --stat-icon-shadow: 0 0 20px rgba(56,189,248,0.25);
            --card-accent: linear-gradient(90deg, var(--primary-color), var(--accent-color));
            --icon-bg: rgba(56,189,248,0.12);
        }
        /* ===== 主题：墨绿暗黑 ===== */
        [data-theme="forest"] {
            --bg-page: #14241C; --bg-card: #1A2E23; --bg-sidebar: rgba(10,20,15,0.92);
            --bg-header: rgba(26,46,35,0.6); --bg-code: #0F1B14; --bg-table: rgba(10,20,15,0.4);
            --bg-tab-active: rgba(52,211,153,0.12); --bg-input: rgba(10,20,15,0.6);
            --bg-timestamp: linear-gradient(135deg, rgba(26,46,35,0.8), rgba(40,60,48,0.5));
            --bg-metric: rgba(255,255,255,0.03); --row-alt: rgba(255,255,255,0.02);
            --primary-color: #34D399; --primary-light: #6EE7B7; --accent-color: #10B981;
            --text-primary: #D1FAE5; --text-secondary: #6EE7B7; --text-muted: #4B9D7A;
            --border-color: rgba(52,211,153,0.08); --border-light: rgba(52,211,153,0.04);
            --shadow-card: 0 4px 16px rgba(0,0,0,0.2), 0 1px 3px rgba(0,0,0,0.3);
            --shadow-hover: 0 8px 32px rgba(0,0,0,0.3), 0 4px 12px rgba(52,211,153,0.1);
            --success-color: #4ADE80; --warning-color: #FBBF24; --danger-color: #F87171; --info-color: #60A5FA;
            --code-text: #6EE7B7; --grid-opacity: 0.08; --particle-opacity: 0.25;
            --title-gradient: linear-gradient(45deg, #34D399, #6EE7B7, #10B981, #34D399);
            --title-shadow: 0 0 30px rgba(52,211,153,0.3); --nav-text: #6EE7B7; --th-text: #fff;
            --stat-icon-shadow: 0 0 20px rgba(52,211,153,0.25);
            --card-accent: linear-gradient(90deg, var(--primary-color), var(--accent-color));
            --icon-bg: rgba(52,211,153,0.12);
        }
        /* ===== 主题：午夜紫 ===== */
        [data-theme="midnight"] {
            --bg-page: #1A1033; --bg-card: #2A1B4A; --bg-sidebar: rgba(15,10,30,0.92);
            --bg-header: rgba(42,27,74,0.6); --bg-code: #150B2E; --bg-table: rgba(15,10,30,0.4);
            --bg-tab-active: rgba(167,139,250,0.12); --bg-input: rgba(15,10,30,0.6);
            --bg-timestamp: linear-gradient(135deg, rgba(42,27,74,0.8), rgba(60,40,100,0.5));
            --bg-metric: rgba(255,255,255,0.03); --row-alt: rgba(255,255,255,0.02);
            --primary-color: #A78BFA; --primary-light: #C4B5FD; --accent-color: #8B5CF6;
            --text-primary: #E9D5FF; --text-secondary: #C4B5FD; --text-muted: #9F7AEA;
            --border-color: rgba(167,139,250,0.08); --border-light: rgba(167,139,250,0.04);
            --shadow-card: 0 4px 16px rgba(0,0,0,0.2), 0 1px 3px rgba(0,0,0,0.3);
            --shadow-hover: 0 8px 32px rgba(0,0,0,0.3), 0 4px 12px rgba(167,139,250,0.1);
            --success-color: #4ADE80; --warning-color: #FBBF24; --danger-color: #F87171; --info-color: #60A5FA;
            --code-text: #C4B5FD; --grid-opacity: 0.08; --particle-opacity: 0.25;
            --title-gradient: linear-gradient(45deg, #A78BFA, #C4B5FD, #8B5CF6, #A78BFA);
            --title-shadow: 0 0 30px rgba(167,139,250,0.3); --nav-text: #C4B5FD; --th-text: #fff;
            --stat-icon-shadow: 0 0 20px rgba(167,139,250,0.25);
            --card-accent: linear-gradient(90deg, var(--primary-color), var(--accent-color));
            --icon-bg: rgba(167,139,250,0.12);
        }
        /* ===== 主题：黑白 ===== */
        [data-theme="mono"] {
            --bg-page: #0A0A0A; --bg-card: #1A1A1A; --bg-sidebar: rgba(10,10,10,0.92);
            --bg-header: rgba(26,26,26,0.6); --bg-code: #0F0F0F; --bg-table: rgba(10,10,10,0.4);
            --bg-tab-active: rgba(255,255,255,0.08); --bg-input: rgba(10,10,10,0.6);
            --bg-timestamp: linear-gradient(135deg, rgba(40,40,40,0.8), rgba(60,60,60,0.5));
            --bg-metric: rgba(255,255,255,0.03); --row-alt: rgba(255,255,255,0.02);
            --primary-color: #E5E5E5; --primary-light: #F5F5F5; --accent-color: #A3A3A3;
            --text-primary: #FAFAFA; --text-secondary: #A3A3A3; --text-muted: #737373;
            --border-color: rgba(255,255,255,0.1); --border-light: rgba(255,255,255,0.05);
            --shadow-card: 0 4px 16px rgba(0,0,0,0.3), 0 1px 3px rgba(0,0,0,0.4);
            --shadow-hover: 0 8px 32px rgba(0,0,0,0.4), 0 4px 12px rgba(255,255,255,0.05);
            --success-color: #737373; --warning-color: #A3A3A3; --danger-color: #DCDCDC; --info-color: #909090;
            --code-text: #D4D4D4; --grid-opacity: 0.06; --particle-opacity: 0.2;
            --title-gradient: linear-gradient(45deg, #FAFAFA, #D4D4D4, #A3A3A3, #FAFAFA);
            --title-shadow: 0 0 30px rgba(255,255,255,0.1); --nav-text: #A3A3A3; --th-text: #fff;
            --stat-icon-shadow: 0 0 20px rgba(255,255,255,0.1);
            --card-accent: linear-gradient(90deg, var(--primary-color), var(--accent-color));
            --icon-bg: rgba(255,255,255,0.08);
        }
        /* ===== 主题：青蓝 ===== */
        [data-theme="cyan"] {
            --bg-page: #F0FDFA; --bg-card: #FFFFFF; --bg-sidebar: rgba(255,255,255,0.98);
            --bg-header: #FFFFFF; --bg-code: #F0FDFA; --bg-table: #FFFFFF;
            --bg-tab-active: rgba(6,182,212,0.1); --bg-input: #F0FDFA;
            --bg-timestamp: linear-gradient(135deg, rgba(6,182,212,0.08), rgba(34,211,238,0.05));
            --bg-metric: rgba(6,182,212,0.04); --row-alt: rgba(6,182,212,0.03);
            --primary-color: #06B6D4; --primary-light: #22D3EE; --accent-color: #0EA5E9;
            --text-primary: #0F172A; --text-secondary: #475569; --text-muted: #94A3B8;
            --border-color: #E0F2FE; --border-light: #F0F9FF;
            --shadow-card: 0 4px 16px rgba(6,182,212,0.08), 0 1px 3px rgba(6,182,212,0.06);
            --shadow-hover: 0 8px 32px rgba(6,182,212,0.12), 0 4px 12px rgba(6,182,212,0.08);
            --success-color: #10B981; --warning-color: #F59E0B; --danger-color: #EF4444; --info-color: #0EA5E9;
            --code-text: #0F766E; --grid-opacity: 0.04; --particle-opacity: 0.3;
            --title-gradient: linear-gradient(45deg, #06B6D4, #22D3EE, #0EA5E9, #06B6D4);
            --title-shadow: 0 0 30px rgba(6,182,212,0.2); --nav-text: #475569; --th-text: #fff;
            --stat-icon-shadow: 0 0 20px rgba(6,182,212,0.15);
            --card-accent: linear-gradient(90deg, var(--primary-color), var(--accent-color));
            --icon-bg: rgba(6,182,212,0.1);
        }
        /* ===== 主题：琥珀暗黑 ===== */
        [data-theme="amber"] {
            --bg-page: #1C1410; --bg-card: #2A2018; --bg-sidebar: rgba(28,20,16,0.92);
            --bg-header: rgba(42,32,24,0.6); --bg-code: #1A120E; --bg-table: rgba(28,20,16,0.4);
            --bg-tab-active: rgba(245,158,11,0.12); --bg-input: rgba(28,20,16,0.6);
            --bg-timestamp: linear-gradient(135deg, rgba(245,158,11,0.1), rgba(217,119,6,0.06));
            --bg-metric: rgba(245,158,11,0.04); --row-alt: rgba(245,158,11,0.02);
            --primary-color: #F59E0B; --primary-light: #FBBF24; --accent-color: #D97706;
            --text-primary: #FEF3C7; --text-secondary: #D6B68A; --text-muted: #92744F;
            --border-color: rgba(245,158,11,0.15); --border-light: rgba(245,158,11,0.08);
            --shadow-card: 0 4px 16px rgba(0,0,0,0.4), 0 1px 3px rgba(0,0,0,0.5);
            --shadow-hover: 0 8px 32px rgba(0,0,0,0.5), 0 4px 12px rgba(245,158,11,0.1);
            --success-color: #84CC16; --warning-color: #F59E0B; --danger-color: #DC2626; --info-color: #0EA5E9;
            --code-text: #FBBF24; --grid-opacity: 0.05; --particle-opacity: 0.25;
            --title-gradient: linear-gradient(45deg, #FBBF24, #F59E0B, #D97706, #FBBF24);
            --title-shadow: 0 0 30px rgba(245,158,11,0.25); --nav-text: #D6B68A; --th-text: #fff;
            --stat-icon-shadow: 0 0 20px rgba(245,158,11,0.2);
            --card-accent: linear-gradient(90deg, var(--primary-color), var(--accent-color));
            --icon-bg: rgba(245,158,11,0.12);
        }
        /* ===== 主题：樱花粉 ===== */
        [data-theme="sakura"] {
            --bg-page: #FDF2F8; --bg-card: #FFFFFF; --bg-sidebar: rgba(255,255,255,0.98);
            --bg-header: #FFFFFF; --bg-code: #FDF2F8; --bg-table: #FFFFFF;
            --bg-tab-active: rgba(236,72,153,0.1); --bg-input: #FDF2F8;
            --bg-timestamp: linear-gradient(135deg, rgba(236,72,153,0.08), rgba(244,114,182,0.05));
            --bg-metric: rgba(236,72,153,0.04); --row-alt: rgba(236,72,153,0.03);
            --primary-color: #EC4899; --primary-light: #F472B6; --accent-color: #DB2777;
            --text-primary: #1F2937; --text-secondary: #6B7280; --text-muted: #9CA3AF;
            --border-color: #FCE7F3; --border-light: #FDF2F8;
            --shadow-card: 0 4px 16px rgba(236,72,153,0.08), 0 1px 3px rgba(236,72,153,0.06);
            --shadow-hover: 0 8px 32px rgba(236,72,153,0.12), 0 4px 12px rgba(236,72,153,0.08);
            --success-color: #10B981; --warning-color: #F59E0B; --danger-color: #EF4444; --info-color: #3B82F6;
            --code-text: #BE185D; --grid-opacity: 0.04; --particle-opacity: 0.3;
            --title-gradient: linear-gradient(45deg, #EC4899, #F472B6, #DB2777, #EC4899);
            --title-shadow: 0 0 30px rgba(236,72,153,0.2); --nav-text: #6B7280; --th-text: #fff;
            --stat-icon-shadow: 0 0 20px rgba(236,72,153,0.15);
            --card-accent: linear-gradient(90deg, var(--primary-color), var(--accent-color));
            --icon-bg: rgba(236,72,153,0.1);
        }

        * { margin: 0; padding: 0; box-sizing: border-box; }
        html { scroll-behavior: smooth; }
        body {
            font-family: 'Segoe UI', 'Microsoft YaHei', 'PingFang SC', 'Hiragino Sans GB', sans-serif; background: var(--bg-page);
            background-attachment: fixed; color: var(--text-primary);
            min-height: 100vh; overflow-x: hidden; transition: background 0.3s ease, color 0.3s ease;
            font-size: 14px; line-height: 1.55;
        }

        /* ---- 加载遮罩 ---- */
        .loading-overlay {
            position: fixed; inset: 0; z-index: 9999; background: var(--bg-page);
            display: flex; flex-direction: column; align-items: center; justify-content: center;
            transition: opacity 0.6s ease;
        }
        .loading-overlay.hidden { opacity: 0; pointer-events: none; }
        .loading-spinner {
            width: 56px; height: 56px; border: 3px solid var(--border-light);
            border-top-color: var(--primary-color); border-radius: 50%; animation: spin 0.7s linear infinite;
        }
        @keyframes spin { to { transform: rotate(360deg); } }
        .loading-text {
            margin-top: 18px; font-family: 'Segoe UI', 'Microsoft YaHei', sans-serif; font-size: 1rem;
            color: var(--primary-color); letter-spacing: 3px; animation: pulse 1.5s ease infinite;
        }
        @keyframes pulse { 0%,100% { opacity: 0.5; } 50% { opacity: 1; } }

        /* ---- 侧边导航 ---- */
        .side-nav {
            position: fixed; top: 0; left: 0; width: var(--nav-width); height: 100vh;
            background: var(--bg-sidebar); backdrop-filter: blur(20px);
            border-right: 1px solid var(--border-color); padding: 28px 0 0 0; overflow-y: auto;
            z-index: 100; transition: transform 0.3s ease, background 0.3s ease; display: flex; flex-direction: column;
        }
        .side-nav::-webkit-scrollbar { width: 3px; }
        .side-nav::-webkit-scrollbar-track { background: transparent; }
        .side-nav::-webkit-scrollbar-thumb { background: var(--primary-color); border-radius: 2px; opacity: 0.5; }
        .side-nav-logo {
            display: flex; align-items: center; justify-content: center; gap: 12px;
            font-family: 'Segoe UI', 'Microsoft YaHei', sans-serif; font-size: 1.2rem; font-weight: 800;
            color: var(--text-primary); padding: 0 20px 24px; margin-bottom: 8px;
            border-bottom: 1px solid var(--border-color); letter-spacing: 1.5px;
        }
        .side-nav-logo i {
            width: 42px; height: 42px; border-radius: 12px; background: var(--card-accent);
            color: #fff; display: flex; align-items: center; justify-content: center; font-size: 1.1rem;
            box-shadow: var(--stat-icon-shadow);
        }
        #navItems { flex: 1; padding: 8px 0; }
        .side-nav-item {
            display: flex; align-items: center; gap: 14px; padding: 12px 24px; cursor: pointer;
            color: var(--nav-text); font-size: 0.88rem; transition: all 0.2s ease;
            border-left: 3px solid transparent; text-decoration: none; margin: 2px 8px; border-radius: 0 10px 10px 0;
        }
        .side-nav-item:hover { color: var(--text-primary); background: var(--bg-tab-active); border-left-color: var(--primary-color); }
        .side-nav-item.active {
            color: var(--text-primary); background: var(--bg-tab-active); border-left-color: var(--primary-color);
            font-weight: 600; box-shadow: inset 0 1px 0 var(--border-light);
        }
        .side-nav-item i { width: 18px; text-align: center; font-size: 0.9rem; color: var(--primary-color); }

        /* ---- 主题切换器 ---- */
        .theme-switcher {
            display: flex; gap: 6px; justify-content: center; flex-wrap: wrap; padding: 8px 14px 12px;
            border-top: 1px solid var(--border-color); margin-top: auto;
        }
        .theme-switcher-title {
            width: 100%; text-align: center; font-size: 0.72rem; font-weight: 600;
            text-transform: uppercase; letter-spacing: 1px; color: var(--text-muted);
            padding: 10px 0 4px; border-top: 1px solid var(--border-color);
        }
        .theme-btn {
            width: 32px; height: 32px; border-radius: 8px; border: 2px solid var(--border-color);
            background: var(--bg-card); color: var(--text-secondary); cursor: pointer; font-size: 0.85rem;
            display: flex; align-items: center; justify-content: center; transition: all 0.25s ease;
        }
        .theme-btn:hover { border-color: var(--primary-color); color: var(--primary-color); transform: translateY(-2px); }
        .theme-btn.active {
            border-color: var(--primary-color); color: #fff; background: var(--card-accent);
            box-shadow: var(--stat-icon-shadow); border-color: transparent;
        }

        .nav-toggle {
            display: none; position: fixed; top: 15px; left: 15px; z-index: 200; width: 44px; height: 44px;
            background: var(--bg-sidebar); border: 1px solid var(--border-color); border-radius: 10px;
            color: var(--text-primary); font-size: 1.2rem; cursor: pointer; backdrop-filter: blur(10px);
            align-items: center; justify-content: center;
        }

        .container { max-width: 1500px; margin: 0 auto; padding: 20px 20px 20px calc(var(--nav-width) + 28px); }

        /* ---- 网格背景 ---- */
        .cyber-grid {
            position: fixed; top: 0; left: 0; width: 100%; height: 100%;
            background: linear-gradient(var(--border-color) 1px, transparent 1px), linear-gradient(90deg, var(--border-color) 1px, transparent 1px);
            background-size: 50px 50px; z-index: -1; opacity: var(--grid-opacity); animation: gridMove 25s linear infinite;
        }
        @keyframes gridMove { 0% { transform: translate(0,0); } 100% { transform: translate(50px,50px); } }
        .particles { position: fixed; top: 0; left: 0; width: 100%; height: 100%; pointer-events: none; z-index: -1; }
        .particle { position: absolute; width: 2px; height: 2px; background: var(--primary-color); border-radius: 50%; opacity: var(--particle-opacity); animation: float 15s infinite linear; }
        @keyframes float { 0% { transform: translateY(100vh) translateX(0); opacity: 0; } 10% { opacity: var(--particle-opacity); } 90% { opacity: var(--particle-opacity); } 100% { transform: translateY(-100px) translateX(100px); opacity: 0; } }

        /* ---- 头部 ---- */
        .header {
            text-align: center; padding: 32px 24px 28px; background: var(--bg-header); backdrop-filter: blur(15px);
            border-radius: 20px; margin-bottom: 24px; border: 1px solid var(--border-color);
            position: relative; overflow: hidden; box-shadow: var(--shadow-card);
        }
        .header::after {
            content: ''; position: absolute; top: 0; left: 0; right: 0; height: 4px;
            background: var(--card-accent); background-size: 200% auto; animation: shimmer 4s infinite linear;
        }
        .cyber-title {
            font-family: 'Segoe UI', 'Microsoft YaHei', sans-serif; font-size: 2.4rem; font-weight: 800;
            background: var(--title-gradient); -webkit-background-clip: text; -webkit-text-fill-color: transparent;
            background-size: 300% auto; animation: shimmer 4s infinite linear;
            letter-spacing: 2px; margin-bottom: 12px; text-shadow: var(--title-shadow);
        }
        .cyber-title i { -webkit-text-fill-color: var(--primary-color); margin-right: 12px; }
        @keyframes shimmer { 0% { background-position: 0% center; } 100% { background-position: 300% center; } }
        .subtitle { font-size: 1.05rem; opacity: 0.7; margin-bottom: 0; color: var(--text-secondary); font-weight: 400; letter-spacing: 0.5px; }
        .timestamp { display: flex; justify-content: center; gap: 12px; flex-wrap: wrap; margin-top: 20px; }
        .timestamp-item {
            background: var(--bg-timestamp); padding: 12px 22px; border-radius: 10px;
            border: 1px solid var(--border-color); backdrop-filter: blur(10px);
            transition: all 0.25s ease; font-size: 0.85rem; color: var(--text-secondary); display: flex; align-items: center; gap: 8px;
        }
        .timestamp-item i { color: var(--primary-color); font-size: 0.85rem; }
        .timestamp-item:hover { transform: translateY(-2px); border-color: var(--primary-light); color: var(--text-primary); }

        /* ---- 仪表板 ---- */
        .dashboard { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; margin-bottom: 12px; padding: 12px; background: var(--bg-metric); border-radius: 12px; border: 1px solid var(--border-color); }
        .stat-card {
            background: var(--bg-card); border-radius: 10px; padding: 8px 8px;
            border: 1px solid var(--border-color); transition: all 0.35s cubic-bezier(0.175,0.885,0.32,1.275);
            position: relative; overflow: hidden; box-shadow: var(--shadow-card);
            display: flex; flex-direction: column; align-items: center;
        }
        .stat-card::before {
            content: ''; position: absolute; top: 0; left: 0; right: 0; height: 4px;
            background: var(--card-accent); border-radius: 16px 16px 0 0;
        }
        .stat-card:hover { transform: translateY(-6px); box-shadow: var(--shadow-hover); border-color: var(--primary-light); }
        .stat-card.critical::before { background: linear-gradient(90deg, var(--danger-color), #FF6B6B); }
        .stat-card.warning::before  { background: linear-gradient(90deg, var(--warning-color), #FFD93D); }
        .stat-card.ok::before       { background: linear-gradient(90deg, var(--success-color), #6BCF7F); }

        /* ---- 环形进度 ---- */
        .circular-progress { position: relative; width: 88px; height: 88px; margin: 2px 0; }
        .circular-progress svg { transform: rotate(-90deg); width: 88px; height: 88px; }
        .circular-progress .track { fill: none; stroke: var(--border-light); stroke-width: 8; }
        .circular-progress .fill { fill: none; stroke-width: 8; stroke-linecap: round; transition: stroke-dashoffset 1.5s cubic-bezier(0.34,1.56,0.64,1); }
        .circular-progress .fill.progress-cpu { stroke: var(--primary-color); filter: drop-shadow(0 0 4px var(--primary-color)); }
        .circular-progress .fill.progress-memory { stroke: var(--accent-color); filter: drop-shadow(0 0 4px var(--accent-color)); }
        .circular-progress .fill.progress-disk { stroke: var(--warning-color); filter: drop-shadow(0 0 4px var(--warning-color)); }
        .circular-progress .icon-center { position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; }
        .circular-progress .icon-center i { font-size: 0.9rem; color: var(--primary-color); opacity: 0.7; }
        .circular-progress .icon-center .pct { font-size: 1.1rem; font-weight: 700; margin-top: 1px; color: var(--text-primary); font-family: 'Segoe UI', 'Microsoft YaHei', sans-serif; }
        .stat-value { font-size: 1.05rem; font-weight: 700; color: var(--text-primary); margin-top: 2px; text-align: center; font-family: 'Segoe UI', 'Microsoft YaHei', sans-serif; }
        .stat-label { font-size: 0.74rem; text-transform: uppercase; letter-spacing: 1px; font-weight: 600; margin-top: 2px; color: var(--text-secondary); }

        /* ---- 线性进度条 ---- */
        .progress-container { margin-top: 14px; width: 100%; }
        .progress-info { display: flex; justify-content: space-between; margin-bottom: 8px; font-size: 0.88rem; color: var(--text-secondary); }
        .progress-bar { background: var(--border-light); border-radius: 8px; height: 10px; overflow: hidden; position: relative; }
        .progress-fill { height: 100%; border-radius: 8px; transition: width 1.5s cubic-bezier(0.34,1.56,0.64,1); position: relative; overflow: hidden; }
        .progress-fill::after { content: ''; position: absolute; top: 0; left: -100%; width: 100%; height: 100%; background: linear-gradient(90deg, transparent, rgba(255,255,255,0.4), transparent); animation: shine 2s infinite; }
        @keyframes shine { 0% { left: -100%; } 100% { left: 100%; } }

        /* ---- 分段式进度条 ---- */
        .seg-bar { display: flex; align-items: center; gap: 5px; }
        .seg { display: inline-block; width: 4px; height: 16px; background: var(--border-light); border-radius: 1px; flex-shrink: 0; }
        .seg.filled { opacity: 1; }
        .seg-pct { font-size: 0.82rem; font-weight: 600; margin-left: 4px; color: var(--text-primary); white-space: nowrap; min-width: 36px; }
        .progress-fill.progress-cpu { background: linear-gradient(90deg, var(--primary-light), var(--primary-color)); }
        .progress-fill.progress-memory { background: linear-gradient(90deg, var(--accent-color), var(--primary-color)); }
        .progress-fill.progress-disk { background: linear-gradient(90deg, var(--warning-color), var(--danger-color)); }
        .progress-fill.progress-network { background: linear-gradient(90deg, var(--info-color), var(--primary-color)); }

        /* ---- 章节 ---- */
        .section {
            background: var(--bg-card); border-radius: 16px; padding: 20px; margin-bottom: 16px;
            border: 1px solid var(--border-color); box-shadow: var(--shadow-card); transition: box-shadow 0.3s ease;
        }
        .section:hover { box-shadow: var(--shadow-hover); }
        .section-title {
            font-family: 'Segoe UI', 'Microsoft YaHei', sans-serif; font-size: 1.2rem; margin-bottom: 12px; padding-bottom: 0;
            display: flex; align-items: center; gap: 14px;
            color: var(--text-primary); cursor: pointer; user-select: none; border-bottom: none;
        }
        .section-title i:first-child {
            width: 40px; height: 40px; border-radius: 10px; background: var(--icon-bg);
            color: var(--primary-color); display: flex; align-items: center; justify-content: center; font-size: 1.1rem;
            transition: all 0.3s ease;
        }
        .section-title:hover i:first-child { background: var(--card-accent); color: #fff; }
        .section-title::after {
            content: ''; flex: 1; height: 2px; margin-left: 4px;
            background: linear-gradient(90deg, var(--border-color), transparent); border-radius: 1px;
        }
        .collapse-icon { font-size: 1rem; transition: transform 0.3s ease; opacity: 0.4; color: var(--text-secondary); }
        .section.collapsed .collapse-icon { transform: rotate(-90deg); }
        .section.collapsed .section-body { display: none; }
        .section-body { transition: opacity 0.3s ease; }
        .section h3 {
            color: var(--text-primary); font-size: 1.0rem; margin: 12px 0 8px;
            display: flex; align-items: center; gap: 10px;
            cursor: pointer; user-select: none; transition: all 0.2s ease;
            padding: 8px 12px; border-radius: 10px;
            background: var(--bg-metric); border: 1px solid var(--border-light);
        }
        .section h3:hover { color: var(--primary-color); border-color: var(--primary-light); background: var(--bg-tab-active); }
        .section h3 i { color: var(--primary-color); font-size: 0.95rem; transition: transform 0.3s ease; }
        .section h3:hover > i:first-child { transform: scale(1.15); }
        .section h3::after {
            content: '\f078'; font-family: 'Font Awesome 6 Free'; font-weight: 900;
            font-size: 0.72rem; margin-left: auto; transition: transform 0.3s ease;
            opacity: 0.35; color: var(--text-secondary);
        }
        .section h3:hover::after { opacity: 0.7; color: var(--primary-color); }
        .section h3.sub-collapsed::after { transform: rotate(-90deg); }
        .section h3.sub-collapsed { margin-bottom: 0; }
        .section h4 { color: var(--text-secondary); font-size: 0.88rem; margin-bottom: 8px; font-weight: 600; }

        .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
        .grid-3 { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 16px; }

        /* ---- 表格 ---- */
        table { width: 100%; border-collapse: separate; border-spacing: 0; margin: 10px 0; background: var(--bg-table); border-radius: 12px; overflow: hidden; box-shadow: var(--shadow-card); border: 1px solid var(--border-color); }
        th {
            background: var(--card-accent); padding: 8px 12px; text-align: left; font-weight: 700;
            text-transform: uppercase; letter-spacing: 0.6px; font-size: 0.75rem;
            font-family: 'Segoe UI', 'Microsoft YaHei', sans-serif; color: var(--th-text);
        }
        td { padding: 6px 12px; border-bottom: 1px solid var(--border-light); transition: all 0.2s ease; font-size: 0.84rem; color: var(--text-primary); }
        tr:nth-child(even) td { background: var(--row-alt); }
        tr:hover td { background: var(--bg-tab-active); }
        tr:last-child td { border-bottom: none; }

        /* ---- 搜索框 ---- */
        .search-box { position: relative; margin-bottom: 16px; max-width: 400px; }
        .search-box input { width: 100%; padding: 10px 16px 10px 38px; background: var(--bg-input); border: 1px solid var(--border-color); border-radius: 10px; color: var(--text-primary); font-size: 0.85rem; font-family: 'Segoe UI', 'Microsoft YaHei', 'PingFang SC', 'Hiragino Sans GB', sans-serif; transition: all 0.25s ease; }
        .search-box input:focus { outline: none; border-color: var(--primary-color); box-shadow: 0 0 0 3px var(--bg-tab-active); }
        .search-box input::placeholder { color: var(--text-muted); }
        .search-box i { position: absolute; left: 15px; top: 50%; transform: translateY(-50%); color: var(--text-muted); font-size: 0.9rem; }

        /* ---- 状态徽章 ---- */
        .status-badge { padding: 3px 10px; border-radius: 20px; font-size: 0.76rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px; display: inline-flex; align-items: center; gap: 4px; transition: all 0.25s ease; }
        .status-badge:hover { transform: scale(1.05); }
        .status-ok       { background: linear-gradient(135deg, #22C55E, #16A34A); color: white; }
        .status-warning  { background: linear-gradient(135deg, #F59E0B, #D97706); color: white; }
        .status-critical { background: linear-gradient(135deg, #EF4444, #DC2626); color: white; }
        .status-info     { background: linear-gradient(135deg, #3B82F6, #2563EB); color: white; }
        .status-badge i { font-size: 0.72rem; }
        code { background: var(--bg-code); padding: 2px 6px; border-radius: 4px; font-family: 'Consolas', 'Courier New', monospace; font-size: 0.78rem; }

        /* ---- 代码块 ---- */
        .code-block {
            background: var(--bg-code); padding: 10px 14px; border-radius: 12px; margin: 8px 0;
            border: 1px solid var(--border-color); overflow-x: auto;
            font-family: 'Consolas', 'Courier New', monospace; font-size: 0.8rem; position: relative;
        }
        .code-block::before {
            content: ''; position: absolute; top: 12px; left: 14px;
            width: 7px; height: 7px; border-radius: 50%; background: #FF5F56;
            box-shadow: 12px 0 0 #FFBD2E, 24px 0 0 #27C93F;
        }
        .code-block pre { color: var(--code-text); line-height: 1.5; margin: 18px 0 0 0; }
        .code-block h4 { color: var(--text-secondary); font-size: 0.82rem; margin: 0 0 8px 50px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; }

        /* ---- 指标网格 ---- */
        .metric-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 10px; margin: 10px 0; }
        .metric-item {
            text-align: center; padding: 16px 12px; background: var(--bg-metric); border-radius: 12px;
            transition: all 0.3s ease; position: relative; overflow: hidden; border: 1px solid var(--border-color);
        }
        .metric-item::before { content: ''; position: absolute; top: 0; left: 0; right: 0; height: 3px; background: var(--card-accent); opacity: 0.6; }
        .metric-item:hover { transform: translateY(-4px); border-color: var(--primary-light); box-shadow: var(--shadow-card); }
        .metric-item:hover::before { opacity: 1; }
        .metric-item i { color: var(--text-muted); font-size: 1.3rem; }
        .metric-value { font-size: 1.4rem; font-weight: 700; color: var(--primary-color); margin: 6px 0 2px; font-family: 'Segoe UI', 'Microsoft YaHei', sans-serif; }
        .metric-label { font-size: 0.82rem; text-transform: uppercase; letter-spacing: 1px; color: var(--text-secondary); }

        /* ---- 系统概览紧凑卡片 ---- */
        .overview-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; margin-bottom: 12px; }
        .overview-card {
            display: flex; align-items: center; gap: 8px; padding: 8px 10px;
            background: var(--bg-card); border: 1px solid var(--border-color); border-radius: 8px;
            transition: all 0.25s ease; position: relative; overflow: hidden;
        }
        .overview-card::before {
            content: ''; position: absolute; top: 0; left: 0; bottom: 0; width: 3px;
            background: var(--card-accent); opacity: 0.6;
        }
        .overview-card:hover { border-color: var(--primary-light); box-shadow: var(--shadow-card); transform: translateY(-2px); }
        .overview-card:hover::before { opacity: 1; }
        .overview-icon {
            width: 28px; height: 28px; border-radius: 6px; background: var(--icon-bg);
            color: var(--primary-color); display: flex; align-items: center; justify-content: center;
            font-size: 0.82rem; flex-shrink: 0;
        }
        .overview-info { min-width: 0; flex: 1; }
        .overview-value { font-size: 0.84rem; font-weight: 700; color: var(--text-primary); line-height: 1.2; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .overview-label { font-size: 0.72rem; color: var(--text-secondary); text-transform: uppercase; letter-spacing: 0.5px; margin-top: 2px; }

        .docker-container   { border-top: 3px solid rgba(32,156,238,0.4); }
        .firewall-container { border-top: 3px solid rgba(255,65,108,0.4); }

        /* ---- 标签页 ---- */
        .nav-tabs { display: flex; gap: 6px; margin-bottom: 12px; flex-wrap: wrap; }
        .nav-tab {
            padding: 6px 14px; background: var(--bg-input); border-radius: 8px; cursor: pointer;
            transition: all 0.25s ease; font-weight: 600; font-size: 0.82rem; color: var(--text-secondary);
            border: 1px solid transparent;
        }
        .nav-tab:hover { background: var(--bg-tab-active); color: var(--text-primary); border-color: var(--border-color); }
        .nav-tab.active { background: var(--card-accent); color: white; border-color: transparent; box-shadow: var(--stat-icon-shadow); }
        .tab-content { display: none; }
        .tab-content.active { display: block; animation: fadeIn 0.4s ease; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(15px); } to { opacity: 1; transform: translateY(0); } }

        /* ---- 健康评分 ---- */
        .health-gauge { position: relative; width: 120px; height: 120px; margin: 8px auto; }
        .health-gauge svg { transform: rotate(-90deg); }
        .health-gauge .track { fill: none; stroke: var(--border-light); stroke-width: 8; }
        .health-gauge .fill { fill: none; stroke-width: 8; stroke-linecap: round; transition: stroke-dashoffset 2s cubic-bezier(0.34,1.56,0.64,1); }
        .health-gauge .center { position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; }
        .health-gauge .score { font-size: 1.8rem; font-weight: 800; font-family: 'Segoe UI', 'Microsoft YaHei', sans-serif; }
        .health-gauge .label { font-size: 0.72rem; opacity: 0.6; text-transform: uppercase; letter-spacing: 1.2px; margin-top: 2px; color: var(--text-secondary); }

        /* ---- 返回顶部 ---- */
        .back-to-top {
            position: fixed; bottom: 28px; right: 28px; width: 46px; height: 46px; border-radius: 50%;
            background: var(--card-accent); color: white; border: none; cursor: pointer; font-size: 1.1rem;
            display: flex; align-items: center; justify-content: center; box-shadow: var(--shadow-hover);
            opacity: 0; pointer-events: none; transition: all 0.3s ease; z-index: 200;
        }
        .back-to-top.visible { opacity: 1; pointer-events: auto; }
        .back-to-top:hover { transform: translateY(-4px) scale(1.05); }

        /* ---- 动画 ---- */
        .fade-in { opacity: 0; animation: fadeInUp 0.8s ease forwards; }
        @keyframes fadeInUp { to { opacity: 1; transform: translateY(0); } }
        .stagger-1 { animation-delay: 0.08s; transform: translateY(20px); }
        .stagger-2 { animation-delay: 0.16s; transform: translateY(20px); }
        .stagger-3 { animation-delay: 0.24s; transform: translateY(20px); }
        .stagger-4 { animation-delay: 0.32s; transform: translateY(20px); }
        .floating { animation: floating 3s ease-in-out infinite; }
        @keyframes floating { 0%,100% { transform: translateY(0); } 50% { transform: translateY(-8px); } }
        @keyframes pulseIcon { 0%,100% { transform: scale(1); } 50% { transform: scale(1.08); } }

        .stat-icon {
            font-size: 2.5rem; color: var(--primary-color); margin-bottom: 16px;
            width: 64px; height: 64px; border-radius: 16px; background: var(--icon-bg);
            display: flex; align-items: center; justify-content: center;
            box-shadow: var(--stat-icon-shadow); animation: pulseIcon 3s infinite;
        }

        /* ---- 响应式 ---- */
        @media (max-width: 1200px) {
            .grid-2, .grid-3 { grid-template-columns: 1fr; }
            .cyber-title { font-size: 2.2rem; }
            .dashboard { grid-template-columns: repeat(2, 1fr); }
            .overview-grid { grid-template-columns: repeat(2, 1fr); }
            .header { padding: 32px 24px; }
            .circular-progress { width: 100px; height: 100px; }
            .circular-progress svg { width: 100px; height: 100px; }
            .circular-progress .icon-center .pct { font-size: 1.2rem; }
        }
        @media (max-width: 768px) {
            .side-nav { transform: translateX(-100%); }
            .side-nav.open { transform: translateX(0); }
            .nav-toggle { display: flex; }
            .container { padding: 64px 14px 20px 14px; }
            .cyber-title { font-size: 1.5rem; letter-spacing: 1px; }
            .timestamp { gap: 10px; }
            .timestamp-item { padding: 8px 14px; font-size: 0.82rem; }
            .circular-progress { width: 90px; height: 90px; }
            .circular-progress svg { width: 90px; height: 90px; }
            .circular-progress .icon-center i { font-size: 1.1rem; }
            .circular-progress .icon-center .pct { font-size: 1.2rem; }
            .section { padding: 20px; }
            .section-title { font-size: 1.2rem; }
            .section-title i:first-child { width: 34px; height: 34px; }
            .stat-icon { width: 52px; height: 52px; font-size: 2rem; }
            .dashboard { grid-template-columns: 1fr; }
            .overview-grid { grid-template-columns: 1fr; }
        }

        /* ---- 导出按钮 ---- */
        .export-bar { display: flex; gap: 10px; justify-content: center; margin-top: 18px; }
        .export-btn {
            display: inline-flex; align-items: center; gap: 8px; padding: 8px 20px; border-radius: 10px;
            border: 1px solid var(--border-color); background: var(--bg-card); color: var(--text-secondary);
            cursor: pointer; font-size: 0.85rem; font-weight: 600; font-family: 'Segoe UI', 'Microsoft YaHei', sans-serif;
            transition: all 0.25s ease; text-decoration: none;
        }
        .export-btn:hover { transform: translateY(-2px); box-shadow: var(--shadow-card); }
        .export-btn i { font-size: 0.9rem; }
        .export-btn.word:hover { border-color: #2563EB; color: #2563EB; }

        /* ---- 打印样式 ---- */
        @media print {
            .side-nav, .nav-toggle, .back-to-top, .cyber-grid, .particles, .loading-overlay, .export-bar { display: none !important; }
            .container { padding: 0; max-width: 100%; }
            body { background: #fff; color: #000; }
            .section, .stat-card, .header { background: #fff !important; border: 1px solid #ccc !important; box-shadow: none !important; break-inside: avoid; }
            .section:hover, .stat-card:hover { transform: none !important; }
            .section-body { display: block !important; }
            .tab-content { display: block !important; }
            .cyber-title { -webkit-text-fill-color: #333 !important; background: none !important; }
            .cyber-title i { -webkit-text-fill-color: #333 !important; }
            .code-block pre { color: #333 !important; }
            th { background: #333 !important; color: #fff !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
            .status-badge { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
            .stat-card::before, .metric-item::before, .header::after { display: none !important; }
        }
    </style>
</head>
<body>
    <div class="loading-overlay" id="loadingOverlay">
        <div class="loading-spinner"></div>
        <div class="loading-text">LOADING...</div>
    </div>

    <button class="nav-toggle" id="navToggle" onclick="toggleNav()"><i class="fas fa-bars"></i></button>

    <nav class="side-nav" id="sideNav">
        <div class="side-nav-logo"><i class="fas fa-server"></i> Linux巡检报告</div>
        <div id="navItems"></div>
        <div class="theme-switcher">
            <div class="theme-switcher-title">主题选择</div>
            <button class="theme-btn active" data-theme="light" title="浅色"><i class="fas fa-sun"></i></button>
            <button class="theme-btn" data-theme="white-blue" title="白蓝"><i class="fas fa-water"></i></button>
            <button class="theme-btn" data-theme="green" title="护眼绿"><i class="fas fa-leaf"></i></button>
            <button class="theme-btn" data-theme="warm" title="暖橙"><i class="fas fa-fire"></i></button>
            <button class="theme-btn" data-theme="rose" title="玫红"><i class="fas fa-heart"></i></button>
            <button class="theme-btn" data-theme="dark" title="暗黑"><i class="fas fa-moon"></i></button>
            <button class="theme-btn" data-theme="slate" title="深空灰"><i class="fas fa-meteor"></i></button>
            <button class="theme-btn" data-theme="forest" title="墨绿暗黑"><i class="fas fa-tree"></i></button>
            <button class="theme-btn" data-theme="midnight" title="午夜紫"><i class="fas fa-gem"></i></button>
            <button class="theme-btn" data-theme="mono" title="黑白"><i class="fas fa-adjust"></i></button>
            <button class="theme-btn" data-theme="cyan" title="青蓝"><i class="fas fa-water"></i></button>
            <button class="theme-btn" data-theme="amber" title="琥珀暗黑"><i class="fas fa-fire-flame-curved"></i></button>
            <button class="theme-btn" data-theme="sakura" title="樱花粉"><i class="fas fa-spa"></i></button>
            <label class="theme-btn theme-custom-btn" title="自定义颜色" style="position:relative;overflow:hidden">
                <i class="fas fa-palette"></i>
                <input type="color" id="customColorPicker" style="position:absolute;inset:0;opacity:0;cursor:pointer;border:none;background:none" value="#6366F1">
            </label>
        </div>
    </nav>

    <div class="cyber-grid"></div>
    <div class="particles" id="particles"></div>
    <div class="container" id="mainContent">
        <div class="header fade-in">
            <h1 class="cyber-title floating"><i class="fas fa-server"></i> Linux巡检报告</h1>
            <p class="subtitle">全方位系统健康监控与分析平台</p>
            <div class="timestamp">
                <div class="timestamp-item"><i class="fas fa-clock"></i> 生成时间: DATETIME_PLACEHOLDER</div>
                <div class="timestamp-item"><i class="fas fa-desktop"></i> 主机名: HOSTNAME_PLACEHOLDER</div>
                <div class="timestamp-item"><i class="fas fa-microchip"></i> 架构: ARCH_PLACEHOLDER</div>
                <div class="timestamp-item"><i class="fas fa-code-branch"></i> 内核: KERNEL_PLACEHOLDER</div>
            </div>
            <div class="export-bar">
                <button class="export-btn word" onclick="exportWord()"><i class="fas fa-file-word"></i> 导出 Word</button>
            </div>
        </div>
HTMLEOF

sed -i "s|DATETIME_PLACEHOLDER|$(date "+%Y-%m-%d %H:%M:%S")|g" "$HTML_REPORT"
sed -i "s|HOSTNAME_PLACEHOLDER|$(hostname)|g" "$HTML_REPORT"
sed -i "s|ARCH_PLACEHOLDER|$(uname -m)|g" "$HTML_REPORT"
sed -i "s|KERNEL_PLACEHOLDER|$(uname -r)|g" "$HTML_REPORT"

# ------------------------------------------------------------
# 仪表板 - 环形进度
# ------------------------------------------------------------
make_circular_progress() {
    local pct="$1"
    local color_class="$2"
    local icon="$3"
    local circumference=314.16
    local offset
    offset=$(awk -v c="$circumference" -v p="$pct" 'BEGIN { printf "%.2f", c - (c * p / 100) }')
    echo "<div class=\"circular-progress\"><svg width=\"120\" height=\"120\" viewBox=\"0 0 160 160\"><circle class=\"track\" cx=\"80\" cy=\"80\" r=\"50\"></circle><circle class=\"fill ${color_class}\" cx=\"80\" cy=\"80\" r=\"50\" stroke-dasharray=\"${circumference}\" stroke-dashoffset=\"${circumference}\" data-offset=\"${offset}\"></circle></svg><div class=\"icon-center\"><i class=\"${icon}\"></i></div></div><div class=\"stat-value\">${pct}%</div>"
}

CPU_CIRCULAR=$(make_circular_progress "$CPU_USAGE" "progress-cpu" "fas fa-microchip")
MEM_CIRCULAR=$(make_circular_progress "$MEM_USAGE" "progress-memory" "fas fa-memory")
DISK_CIRCULAR=$(make_circular_progress "$DISK_USAGE" "progress-disk" "fas fa-hdd")

# ------------------------------------------------------------
# 1. 系统概览
# ------------------------------------------------------------
add_section "系统概览" "fas fa-rocket" ""

OS_NAME="未知"
if [ -f /etc/os-release ]; then
    OS_NAME=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' | cut -c1-25)
fi

cat >> "$HTML_REPORT" << EOF
        <div class="dashboard">
            <div class="stat-card ${CPU_CARD_STATUS} fade-in stagger-1">
                ${CPU_CIRCULAR}
                <div class="stat-label">CPU 使用率</div>
            </div>
            <div class="stat-card ${MEM_CARD_STATUS} fade-in stagger-2">
                ${MEM_CIRCULAR}
                <div class="stat-label">内存使用率</div>
            </div>
            <div class="stat-card ${DISK_CARD_STATUS} fade-in stagger-3">
                ${DISK_CIRCULAR}
                <div class="stat-label">磁盘使用率（最高）</div>
            </div>
            <div class="stat-card ok fade-in stagger-4">
                <div class="circular-progress">
                    <svg width="120" height="120" viewBox="0 0 160 160"><circle class="track" cx="80" cy="80" r="50"></circle><circle class="fill progress-cpu" cx="80" cy="80" r="50" stroke-dasharray="314.16" stroke-dashoffset="314.16" data-offset="0"></circle></svg>
                    <div class="icon-center"><i class="fas fa-clock"></i></div>
                </div>
                <div class="stat-value">${UPTIME_DAYS:-未知}</div>
                <div class="stat-label">系统运行时间</div>
            </div>
        </div>
        <div class="overview-grid">
            <div class="overview-card">
                <div class="overview-icon"><i class="fas fa-desktop"></i></div>
                <div class="overview-info"><div class="overview-value">$(hostname)</div><div class="overview-label">主机名</div></div>
            </div>
            <div class="overview-card">
                <div class="overview-icon"><i class="fab fa-linux"></i></div>
                <div class="overview-info"><div class="overview-value">${OS_NAME}</div><div class="overview-label">操作系统</div></div>
            </div>
            <div class="overview-card">
                <div class="overview-icon"><i class="fas fa-code-branch"></i></div>
                <div class="overview-info"><div class="overview-value">$(uname -r | cut -c1-15)</div><div class="overview-label">内核版本</div></div>
            </div>
            <div class="overview-card">
                <div class="overview-icon"><i class="fas fa-microchip"></i></div>
                <div class="overview-info"><div class="overview-value">$(grep -c "^processor" /proc/cpuinfo)</div><div class="overview-label">CPU 核心</div></div>
            </div>
            <div class="overview-card">
                <div class="overview-icon"><i class="fas fa-memory"></i></div>
                <div class="overview-info"><div class="overview-value">$(free -h | awk '/Mem/{print $2}')</div><div class="overview-label">总内存</div></div>
            </div>
            <div class="overview-card">
                <div class="overview-icon"><i class="fas fa-hdd"></i></div>
                <div class="overview-info"><div class="overview-value">$(df -h / 2>/dev/null | awk 'NR==2{print $2}')</div><div class="overview-label">根分区</div></div>
            </div>
            <div class="overview-card">
                <div class="overview-icon"><i class="fas fa-network-wired"></i></div>
                <div class="overview-info"><div class="overview-value">$(ip link show 2>/dev/null | grep -c "^[0-9]:")</div><div class="overview-label">网络接口</div></div>
            </div>
        </div>
        <table>
            <tr><th>项目</th><th>值</th><th>状态</th></tr>
            <tr><td><i class="fas fa-rocket"></i> 启动时间</td><td>$(uptime -s 2>/dev/null || echo "未知")</td><td>$(add_status_badge "正常" "ok")</td></tr>
            <tr><td><i class="fas fa-clock"></i> 运行时间</td><td>$(uptime -p 2>/dev/null | sed 's/up //' || echo "未知")</td><td>$(add_status_badge "稳定" "ok")</td></tr>
            <tr><td><i class="fas fa-microchip"></i> CPU型号</td><td>$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^[ \t]*//' | cut -c1-40)</td><td>$(add_status_badge "正常" "ok")</td></tr>
        </table>
EOF
end_section

# ------------------------------------------------------------
# 1b. 资产信息
# ------------------------------------------------------------
add_section "资产信息" "fas fa-barcode" ""

DMI_DIR="/sys/class/dmi/id"
HW_MANUFACTURER="未知"; HW_PRODUCT="未知"; HW_SERIAL="未知"
HW_UUID="未知"; BIOS_VERSION="未知"; BIOS_DATE="未知"; BIOS_VENDOR="未知"
BOARD_NAME="未知"; BOARD_VENDOR="未知"; BOARD_SERIAL="未知"

if [ -d "$DMI_DIR" ]; then
    [ -r "$DMI_DIR/sys_vendor" ]    && HW_MANUFACTURER=$(cat "$DMI_DIR/sys_vendor" 2>/dev/null | head -1)
    [ -r "$DMI_DIR/product_name" ]  && HW_PRODUCT=$(cat "$DMI_DIR/product_name" 2>/dev/null | head -1)
    [ -r "$DMI_DIR/product_serial" ] && HW_SERIAL=$(cat "$DMI_DIR/product_serial" 2>/dev/null | head -1)
    [ -r "$DMI_DIR/product_uuid" ]  && HW_UUID=$(cat "$DMI_DIR/product_uuid" 2>/dev/null | head -1)
    [ -r "$DMI_DIR/bios_version" ]  && BIOS_VERSION=$(cat "$DMI_DIR/bios_version" 2>/dev/null | head -1)
    [ -r "$DMI_DIR/bios_date" ]     && BIOS_DATE=$(cat "$DMI_DIR/bios_date" 2>/dev/null | head -1)
    [ -r "$DMI_DIR/bios_vendor" ]   && BIOS_VENDOR=$(cat "$DMI_DIR/bios_vendor" 2>/dev/null | head -1)
    [ -r "$DMI_DIR/board_name" ]    && BOARD_NAME=$(cat "$DMI_DIR/board_name" 2>/dev/null | head -1)
    [ -r "$DMI_DIR/board_vendor" ]  && BOARD_VENDOR=$(cat "$DMI_DIR/board_vendor" 2>/dev/null | head -1)
    [ -r "$DMI_DIR/board_serial" ]  && BOARD_SERIAL=$(cat "$DMI_DIR/board_serial" 2>/dev/null | head -1)
fi

if [ "$HW_SERIAL" = "未知" ] && command -v dmidecode &>/dev/null; then
    HW_MANUFACTURER=$(dmidecode -s system-manufacturer 2>/dev/null | head -1)
    HW_PRODUCT=$(dmidecode -s system-product-name 2>/dev/null | head -1)
    HW_SERIAL=$(dmidecode -s system-serial-number 2>/dev/null | head -1)
    HW_UUID=$(dmidecode -s system-uuid 2>/dev/null | head -1)
    BIOS_VERSION=$(dmidecode -s bios-version 2>/dev/null | head -1)
    BIOS_DATE=$(dmidecode -s bios-release-date 2>/dev/null | head -1)
fi

VIRT_TYPE="物理机"
if command -v systemd-detect-virt &>/dev/null; then
    VIRT_TYPE=$(systemd-detect-virt 2>/dev/null)
    [ "$VIRT_TYPE" = "none" ] && VIRT_TYPE="物理机"
elif [ -f /proc/1/cgroup ] && grep -qE 'docker|lxc|kubepods' /proc/1/cgroup 2>/dev/null; then
    VIRT_TYPE="容器"
elif grep -q "hypervisor" /proc/cpuinfo 2>/dev/null; then
    VIRT_TYPE="虚拟机"
fi

[ -z "$HW_MANUFACTURER" ] && HW_MANUFACTURER="未知"
[ -z "$HW_PRODUCT" ] && HW_PRODUCT="未知"
[ -z "$HW_SERIAL" ] && HW_SERIAL="未知"
[ -z "$HW_UUID" ] && HW_UUID="未知"

cat >> "$HTML_REPORT" << EOF
        <table>
            <colgroup><col style="width:16%"><col style="width:34%"><col style="width:16%"><col style="width:34%"></colgroup>
            <tr><th>项目</th><th>值</th><th>项目</th><th>值</th></tr>
            <tr>
                <td><i class="fas fa-industry"></i> 制造商</td><td>${HW_MANUFACTURER}</td>
                <td><i class="fas fa-tag"></i> BIOS厂商</td><td>${BIOS_VENDOR}</td>
            </tr>
            <tr>
                <td><i class="fas fa-cube"></i> 产品型号</td><td>${HW_PRODUCT}</td>
                <td><i class="fas fa-code-branch"></i> BIOS版本</td><td>${BIOS_VERSION}</td>
            </tr>
            <tr>
                <td><i class="fas fa-barcode"></i> 序列号</td><td>${HW_SERIAL}</td>
                <td><i class="fas fa-calendar"></i> 发布日期</td><td>${BIOS_DATE}</td>
            </tr>
            <tr>
                <td><i class="fas fa-fingerprint"></i> UUID</td><td style="font-family:'Consolas','Courier New',monospace;font-size:0.82rem;word-break:break-all">${HW_UUID}</td>
                <td><i class="fas fa-microchip"></i> 主板型号</td><td>${BOARD_VENDOR} ${BOARD_NAME}</td>
            </tr>
            <tr>
                <td><i class="fas fa-keyboard"></i> 主板序列号</td><td>${BOARD_SERIAL}</td>
                <td><i class="fas fa-virtualbox"></i> 虚拟化类型</td><td>$(add_status_badge "$VIRT_TYPE" "info")</td>
            </tr>
        </table>
        <h3><i class="fas fa-info-circle"></i> 系统标识</h3>
        <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:12px;">
            <div class="overview-card">
                <div class="overview-icon"><i class="fas fa-microchip"></i></div>
                <div class="overview-info"><div class="overview-value">$(uname -m)</div><div class="overview-label">架构</div></div>
            </div>
            <div class="overview-card">
                <div class="overview-icon"><i class="fas fa-code"></i></div>
                <div class="overview-info"><div class="overview-value" style="font-size:0.95rem">$(uname -r | cut -c1-20)</div><div class="overview-label">内核</div></div>
            </div>
            <div class="overview-card">
                <div class="overview-icon"><i class="fas fa-desktop"></i></div>
                <div class="overview-info"><div class="overview-value" style="font-size:0.95rem">${OS_NAME}</div><div class="overview-label">系统</div></div>
            </div>
        </div>
EOF
end_section

# ------------------------------------------------------------
# 2. 防火墙状态
# ------------------------------------------------------------
add_section "防火墙状态" "fas fa-shield-alt" "firewall-container"
cat >> "$HTML_REPORT" << 'EOF'
        <div class="nav-tabs" id="firewallTabs">
            <div class="nav-tab active" data-tab="fwStatus">状态概览</div>
            <div class="nav-tab" data-tab="fwRules">规则详情</div>
            <div class="nav-tab" data-tab="fwServices">服务状态</div>
        </div>
        <div class="tab-content active" id="fwStatusTab">
            <table>
                <tr><th>防火墙类型</th><th>状态</th><th>详细信息</th></tr>
EOF

if [ "$UFW_AVAILABLE" = "1" ]; then
    if ufw status 2>/dev/null | head -1 | grep -q "active"; then
        UFW_POLICY=$(ufw status verbose 2>/dev/null | grep "Default:" | head -1 | sed 's/Default: //')
        UFW_PORTS=$(ufw status 2>/dev/null | grep -c "ALLOW" 2>/dev/null || echo 0)
        echo "<tr><td><i class=\"fas fa-shield-alt\"></i> UFW</td><td>$(add_status_badge "激活" "ok")</td><td>默认策略: ${UFW_POLICY:-未知} | 开放规则: ${UFW_PORTS:-0} 条</td></tr>" >> "$HTML_REPORT"
    else
        echo "<tr><td><i class=\"fas fa-shield-alt\"></i> UFW</td><td>$(add_status_badge "未激活" "warning")</td><td>建议启用防火墙保护</td></tr>" >> "$HTML_REPORT"
    fi
fi

if [ "$FIREWALLD_AVAILABLE" = "1" ]; then
    if firewall-cmd --state 2>/dev/null | grep -q "running"; then
        FW_ZONE=$(firewall-cmd --get-active-zones 2>/dev/null | head -1)
        FW_SVCS=$(firewall-cmd --list-services 2>/dev/null | tr ' ' ', ' | cut -c1-60)
        echo "<tr><td><i class=\"fas fa-fire\"></i> Firewalld</td><td>$(add_status_badge "运行中" "ok")</td><td>区域: ${FW_ZONE:-未知} | 服务: ${FW_SVCS:-无}</td></tr>" >> "$HTML_REPORT"
    else
        echo "<tr><td><i class=\"fas fa-fire\"></i> Firewalld</td><td>$(add_status_badge "未运行" "warning")</td><td>建议启动 Firewalld 服务</td></tr>" >> "$HTML_REPORT"
    fi
fi

if [ "$IPTABLES_AVAILABLE" = "1" ]; then
    IPT_IN=$(iptables -L INPUT -n 2>/dev/null | wc -l)
    IPT_OUT=$(iptables -L OUTPUT -n 2>/dev/null | wc -l)
    IPT_FWD=$(iptables -L FORWARD -n 2>/dev/null | wc -l)
    IPT_TOTAL=$((IPT_IN + IPT_OUT + IPT_FWD - 12))
    if [ "$IPT_TOTAL" -gt 0 ]; then
        echo "<tr><td><i class=\"fas fa-table\"></i> IPTables</td><td>$(add_status_badge "已配置" "info")</td><td>规则: ${IPT_TOTAL} 条 | INPUT: $((IPT_IN-4)) / OUTPUT: $((IPT_OUT-4)) / FORWARD: $((IPT_FWD-4))</td></tr>" >> "$HTML_REPORT"
    fi
fi

if [ -z "$UFW_AVAILABLE" ] && [ -z "$FIREWALLD_AVAILABLE" ] && [ -z "$IPTABLES_AVAILABLE" ]; then
    echo "<tr><td><i class=\"fas fa-exclamation-triangle\"></i> 无防火墙</td><td>$(add_status_badge "未检测到" "warning")</td><td>未检测到防火墙工具</td></tr>" >> "$HTML_REPORT"
fi

cat >> "$HTML_REPORT" << 'EOF'
            </table>
        </div>
        <div class="tab-content" id="fwRulesTab">
            <h3><i class="fas fa-ruler"></i> 防火墙规则</h3>
EOF

if [ "$IPTABLES_AVAILABLE" = "1" ]; then
    IPTABLES_OUTPUT=$(iptables -L -n 2>/dev/null | head -30 | html_escape)
    echo "<div class=\"code-block\"><pre>${IPTABLES_OUTPUT}</pre></div>" >> "$HTML_REPORT"
else
    echo "<div class=\"code-block\"><pre>iptables 不可用</pre></div>" >> "$HTML_REPORT"
fi

cat >> "$HTML_REPORT" << 'EOF'
        </div>
        <div class="tab-content" id="fwServicesTab">
            <h3><i class="fas fa-cogs"></i> 防火墙服务详情</h3>
EOF

FW_SERVICE_OUTPUT=""
if [ "$FIREWALLD_AVAILABLE" = "1" ]; then
    FW_SERVICE_OUTPUT=$(firewall-cmd --list-all 2>/dev/null | head -15 | html_escape)
elif [ "$UFW_AVAILABLE" = "1" ]; then
    FW_SERVICE_OUTPUT=$(ufw status verbose 2>/dev/null | head -15 | html_escape)
fi
[ -z "$FW_SERVICE_OUTPUT" ] && FW_SERVICE_OUTPUT="无活跃防火墙服务"

echo "<div class=\"code-block\"><pre>${FW_SERVICE_OUTPUT}</pre></div>" >> "$HTML_REPORT"

echo "<h3><i class=\"fas fa-list\"></i> 防火墙服务状态</h3>" >> "$HTML_REPORT"
echo "<table><tr><th>防火墙类型</th><th>状态</th><th>说明</th></tr>" >> "$HTML_REPORT"

check_fw_service() {
    local svc="$1"
    local desc="$2"
    local status_badge
    if [ "$SYSTEMCTL_AVAILABLE" = "1" ] && systemctl is-active "$svc" &>/dev/null; then
        status_badge=$(add_status_badge "运行中" "ok")
    elif command -v "$svc" &>/dev/null || [ "$svc" = "firewalld" ] && [ "$FIREWALLD_AVAILABLE" = "1" ]; then
        status_badge=$(add_status_badge "已安装" "info")
    else
        status_badge=$(add_status_badge "未安装" "warning")
    fi
    echo "<tr><td>$svc</td><td>$status_badge</td><td>$desc</td></tr>" >> "$HTML_REPORT"
}

check_fw_service "ufw" "Uncomplicated Firewall"
check_fw_service "firewalld" "动态防火墙管理"
check_fw_service "iptables" "传统IP表防火墙"
echo "</table>" >> "$HTML_REPORT"

echo "</div>" >> "$HTML_REPORT"
end_section

# ------------------------------------------------------------
# 3. Docker 状态
# ------------------------------------------------------------
if [ "$DOCKER_AVAILABLE" = "1" ]; then
    add_section "Docker状态" "fab fa-docker" "docker-container"
    cat >> "$HTML_REPORT" << 'EOF'
        <div class="nav-tabs" id="dockerTabs">
            <div class="nav-tab active" data-tab="containers">容器状态</div>
            <div class="nav-tab" data-tab="images">镜像信息</div>
            <div class="nav-tab" data-tab="resources">资源使用</div>
            <div class="nav-tab" data-tab="networks">网络信息</div>
        </div>
        <div class="tab-content active" id="containersTab">
EOF

    if docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' > /dev/null 2>&1; then
        DOCKER_STATS_DATA=$(docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}' 2>/dev/null)
        echo "<table><tr><th>容器名称</th><th>镜像</th><th>状态</th><th>CPU</th><th>内存</th><th>端口</th></tr>" >> "$HTML_REPORT"
        while IFS=$'\t' read -r name image status ports; do
            [ -z "$name" ] && continue
            name_esc=$(echo "$name" | html_escape)
            image_esc=$(echo "$image" | html_escape)
            status_esc=$(echo "$status" | html_escape)
            ports_esc=$(echo "$ports" | html_escape)
            stats_line=$(echo "$DOCKER_STATS_DATA" | grep "^${name}|" | head -1)
            if [ -n "$stats_line" ]; then
                cpu=$(echo "$stats_line" | cut -d'|' -f2 | html_escape)
                mem=$(echo "$stats_line" | cut -d'|' -f3 | html_escape)
            else
                cpu="-"; mem="-"
            fi
            echo "<tr><td><strong>${name_esc}</strong></td><td>${image_esc}</td><td>$(add_status_badge "${status_esc}" "ok")</td><td>${cpu}</td><td>${mem}</td><td><code>${ports_esc}</code></td></tr>" >> "$HTML_REPORT"
        done < <(docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null)
        echo "</table>" >> "$HTML_REPORT"
    else
        echo "<p>$(add_status_badge "Docker服务不可用" "warning")</p>" >> "$HTML_REPORT"
    fi

    cat >> "$HTML_REPORT" << 'EOF'
        </div>
        <div class="tab-content" id="imagesTab">
            <h3><i class="fas fa-layer-group"></i> Docker镜像</h3>
EOF
    DOCKER_IMAGES=$(docker images 2>/dev/null | head -15 | html_escape)
    echo "<div class=\"code-block\"><pre>${DOCKER_IMAGES:-无法获取Docker镜像信息}</pre></div>" >> "$HTML_REPORT"

    echo "</div><div class=\"tab-content\" id=\"resourcesTab\"><h3><i class=\"fas fa-chart-pie\"></i> Docker资源使用</h3>" >> "$HTML_REPORT"
    DOCKER_STATS=$(docker stats --no-stream 2>/dev/null | html_escape)
    echo "<div class=\"code-block\"><pre>${DOCKER_STATS:-无法获取Docker资源使用情况}</pre></div>" >> "$HTML_REPORT"

    echo "</div><div class=\"tab-content\" id=\"networksTab\"><h3><i class=\"fas fa-project-diagram\"></i> Docker网络</h3>" >> "$HTML_REPORT"
    DOCKER_NETS=$(docker network ls 2>/dev/null | html_escape)
    echo "<div class=\"code-block\"><pre>${DOCKER_NETS:-无法获取Docker网络信息}</pre></div>" >> "$HTML_REPORT"

    echo "</div>" >> "$HTML_REPORT"
    end_section
fi

# ------------------------------------------------------------
# 4. 性能监控
# ------------------------------------------------------------
add_section "性能监控" "fas fa-tachometer-alt" ""

CPU_BAR_COLOR="var(--success-color)"
if compare_float "$CPU_USAGE" 80; then
    CPU_BAR_COLOR="var(--danger-color)"
elif compare_float "$CPU_USAGE" 50; then
    CPU_BAR_COLOR="var(--warning-color)"
fi

MEM_BAR_COLOR="var(--success-color)"
if compare_float "$MEM_USAGE" 80; then
    MEM_BAR_COLOR="var(--danger-color)"
elif compare_float "$MEM_USAGE" 50; then
    MEM_BAR_COLOR="var(--warning-color)"
fi

cat >> "$HTML_REPORT" << EOF
        <div class="grid-2">
            <div>
                <h3><i class="fas fa-microchip"></i> CPU 详细信息</h3>
                <table>
                    <tr><td colspan="2">
                        <div style="display:flex;align-items:center;gap:10px">
                            <span style="min-width:50px;font-size:0.88rem;color:var(--text-secondary)">使用率</span>
                            <div class="progress-bar" style="flex:1;height:8px;margin:0"><div class="progress-fill" style="width:${CPU_USAGE}%;background:${CPU_BAR_COLOR}"></div></div>
                            <span style="min-width:48px;text-align:right;font-weight:700;font-family:'Segoe UI','Microsoft YaHei',sans-serif">${CPU_USAGE}%</span>
                        </div>
                    </td></tr>
                    <tr><td>核心数</td><td>$(grep -c "^processor" /proc/cpuinfo)</td></tr>
                    <tr><td>线程数</td><td>$(nproc 2>/dev/null || echo "未知")</td></tr>
                    <tr><td>平均负载</td><td>$(uptime | awk -F'load average:' '{print $2}')</td></tr>
                </table>
            </div>
            <div>
                <h3><i class="fas fa-memory"></i> 内存详细信息</h3>
                <table>
                    <tr><td colspan="2">
                        <div style="display:flex;align-items:center;gap:10px">
                            <span style="min-width:50px;font-size:0.88rem;color:var(--text-secondary)">使用率</span>
                            <div class="progress-bar" style="flex:1;height:8px;margin:0"><div class="progress-fill" style="width:${MEM_USAGE}%;background:${MEM_BAR_COLOR}"></div></div>
                            <span style="min-width:48px;text-align:right;font-weight:700;font-family:'Segoe UI','Microsoft YaHei',sans-serif">${MEM_USAGE}%</span>
                        </div>
                    </td></tr>
                    <tr><td>总内存</td><td>$(free -h | awk '/Mem/{print $2}')</td></tr>
                    <tr><td>已用内存</td><td>$(free -h | awk '/Mem/{print $3}')</td></tr>
                    <tr><td>可用内存</td><td>$(free -h | awk '/Mem/{print $7}')</td></tr>
                    <tr><td>缓存/缓冲</td><td>$(free -h | awk '/Mem/{print $6}')</td></tr>
                </table>
            </div>
        </div>
        <h3><i class="fas fa-wave-square"></i> 系统负载</h3>
        <div class="code-block"><pre>$(uptime | html_escape)</pre></div>
        <h3><i class="fas fa-tasks"></i> Top进程监控</h3>
        <div class="grid-2">
            <div class="code-block"><h4>CPU使用前5</h4><pre>$(ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu --no-headers 2>/dev/null | head -5 | html_escape)</pre></div>
            <div class="code-block"><h4>内存使用前5</h4><pre>$(ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem --no-headers 2>/dev/null | head -5 | html_escape)</pre></div>
        </div>
EOF

if compare_float "$CPU_USAGE" 90; then
    echo "<div style='margin-top: 10px;'>$(add_status_badge "警告: CPU使用率超过90%" "critical")</div>" >> "$HTML_REPORT"
elif compare_float "$CPU_USAGE" 80; then
    echo "<div style='margin-top: 10px;'>$(add_status_badge "注意: CPU使用率超过80%" "warning")</div>" >> "$HTML_REPORT"
fi

if compare_float "$MEM_USAGE" 90; then
    echo "<div style='margin-top: 10px;'>$(add_status_badge "警告: 内存使用率超过90%" "critical")</div>" >> "$HTML_REPORT"
elif compare_float "$MEM_USAGE" 80; then
    echo "<div style='margin-top: 10px;'>$(add_status_badge "注意: 内存使用率超过80%" "warning")</div>" >> "$HTML_REPORT"
fi

end_section

# ------------------------------------------------------------
# 4b. CPU 信息
# ------------------------------------------------------------
add_section "CPU信息" "fas fa-microchip" ""

CPU_MODEL=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^[ \t]*//')
CPU_VENDOR=$(grep "vendor_id" /proc/cpuinfo 2>/dev/null | head -1 | awk '{print $3}')
CPU_SOCKETS=$(grep "physical id" /proc/cpuinfo 2>/dev/null | sort -u | wc -l)
[ "$CPU_SOCKETS" -eq 0 ] && CPU_SOCKETS=1
CPU_CORES_PER_SOCKET=$(grep "cpu cores" /proc/cpuinfo 2>/dev/null | head -1 | awk '{print $4}')
[ -z "$CPU_CORES_PER_SOCKET" ] && CPU_CORES_PER_SOCKET=1
CPU_THREADS_PER_CORE=$(grep "siblings" /proc/cpuinfo 2>/dev/null | head -1 | awk '{print $3}')
[ -z "$CPU_THREADS_PER_CORE" ] && CPU_THREADS_PER_CORE=$CPU_CORES_PER_SOCKET
CPU_TOTAL=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null)
CPU_MHZ=$(grep "cpu MHz" /proc/cpuinfo 2>/dev/null | head -1 | awk '{printf "%.0f", $4}')
CPU_CACHE_L2=$(grep "cache size" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^[ \t]*//')
CPU_FLAGS=$(grep "flags" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2)

VIRT_FLAG="不支持"; AES_FLAG="不支持"; HT_FLAG="不支持"
echo "$CPU_FLAGS" | grep -qw "vmx\|svm" && VIRT_FLAG="支持"
echo "$CPU_FLAGS" | grep -qw "aes" && AES_FLAG="支持"
[ "$CPU_THREADS_PER_CORE" -gt "$CPU_CORES_PER_SOCKET" ] 2>/dev/null && HT_FLAG="支持"

cat >> "$HTML_REPORT" << EOF
        <div class="grid-2">
            <div>
                <h3><i class="fas fa-microchip"></i> CPU 规格</h3>
                <table>
                    <tr><th>项目</th><th>值</th></tr>
                    <tr><td><i class="fas fa-tag"></i> 型号</td><td>${CPU_MODEL:-未知}</td></tr>
                    <tr><td><i class="fas fa-industry"></i> 厂商</td><td>${CPU_VENDOR:-未知}</td></tr>
                    <tr><td><i class="fas fa-cubes"></i> 插槽</td><td>${CPU_SOCKETS}</td></tr>
                    <tr><td><i class="fas fa-cube"></i> 每槽核心</td><td>${CPU_CORES_PER_SOCKET}</td></tr>
                    <tr><td><i class="fas fa-thread"></i> 每核线程</td><td>${CPU_THREADS_PER_CORE}</td></tr>
                    <tr><td><i class="fas fa-layer-group"></i> 逻辑CPU</td><td>${CPU_TOTAL}</td></tr>
                    <tr><td><i class="fas fa-tachometer-alt"></i> 主频</td><td>${CPU_MHZ:-未知} MHz</td></tr>
                    <tr><td><i class="fas fa-database"></i> L2缓存</td><td>${CPU_CACHE_L2:-未知}</td></tr>
                </table>
            </div>
            <div>
                <h3><i class="fas fa-cogs"></i> CPU 特性</h3>
                <table>
                    <tr><th>特性</th><th>状态</th></tr>
                    <tr><td><i class="fas fa-virtualbox"></i> 虚拟化(VT-x/AMD-V)</td><td>$(add_status_badge "$VIRT_FLAG" "$([ "$VIRT_FLAG" = "支持" ] && echo "ok" || echo "warning")")</td></tr>
                    <tr><td><i class="fas fa-lock"></i> AES-NI 硬件加密</td><td>$(add_status_badge "$AES_FLAG" "$([ "$AES_FLAG" = "支持" ] && echo "ok" || echo "warning")")</td></tr>
                    <tr><td><i class="fas fa-stream"></i> 超线程(HT)</td><td>$(add_status_badge "$HT_FLAG" "info")</td></tr>
                </table>
                <h3><i class="fas fa-chart-line"></i> CPU 使用情况</h3>
                <div class="metric-grid">
                    <div class="metric-item"><i class="fas fa-bolt fa-2x"></i><div class="metric-value">${CPU_USAGE}%</div><div class="metric-label">使用率</div></div>
                    <div class="metric-item"><i class="fas fa-server fa-2x"></i><div class="metric-value">${CPU_TOTAL}</div><div class="metric-label">逻辑CPU</div></div>
                    <div class="metric-item"><i class="fas fa-weight-hanging fa-2x"></i><div class="metric-value" style="font-size:1.5rem">$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')</div><div class="metric-label">1分钟负载</div></div>
                </div>
            </div>
        </div>
EOF

if [ -n "$TOP_AVAILABLE" ] || [ -f /proc/loadavg ]; then
    LOADAVG=$(cat /proc/loadavg 2>/dev/null | html_escape)
    echo "<h3><i class=\"fas fa-wave-square\"></i> 负载平均值</h3><div class=\"code-block\"><pre>${LOADAVG:-无法获取}</pre></div>" >> "$HTML_REPORT"
fi
end_section

# ------------------------------------------------------------
# 4c. 内存信息
# ------------------------------------------------------------
add_section "内存信息" "fas fa-memory" ""

MEM_TOTAL=$(free -h | awk '/Mem/{print $2}')
MEM_USED=$(free -h | awk '/Mem/{print $3}')
MEM_FREE=$(free -h | awk '/Mem/{print $4}')
MEM_SHARED=$(free -h | awk '/Mem/{print $5}')
MEM_BUFF=$(free -h | awk '/Mem/{print $6}')
MEM_AVAIL=$(free -h | awk '/Mem/{print $7}')
SWAP_TOTAL=$(free -h | awk '/Swap/{print $2}')
SWAP_USED=$(free -h | awk '/Swap/{print $3}')
SWAP_FREE=$(free -h | awk '/Swap/{print $4}')

[ -z "$SWAP_TOTAL" ] || [ "$SWAP_TOTAL" = "0B" ] && SWAP_STATUS=$(add_status_badge "无Swap" "warning") || SWAP_STATUS=$(add_status_badge "已启用" "ok")

HUGEPAGES_TOTAL=$(grep HugePages_Total /proc/meminfo 2>/dev/null | awk '{print $2}')
HUGEPAGES_FREE=$(grep HugePages_Free /proc/meminfo 2>/dev/null | awk '{print $2}')
HUGEPAGE_SIZE=$(grep Hugepagesize /proc/meminfo 2>/dev/null | awk '{print $2}')

cat >> "$HTML_REPORT" << EOF
        <div class="grid-2">
            <div>
                <h3><i class="fas fa-memory"></i> 物理内存</h3>
                <table>
                    <tr><th>项目</th><th>值</th></tr>
                    <tr><td colspan="2">
                        <div style="display:flex;align-items:center;gap:10px">
                            <span style="min-width:50px;font-size:0.88rem;color:var(--text-secondary)">使用率</span>
                            <div class="progress-bar" style="flex:1;height:8px;margin:0"><div class="progress-fill" style="width:${MEM_USAGE}%;background:${MEM_BAR_COLOR}"></div></div>
                            <span style="min-width:48px;text-align:right;font-weight:700;font-family:'Segoe UI','Microsoft YaHei',sans-serif">${MEM_USAGE}%</span>
                        </div>
                    </td></tr>
                    <tr><td><i class="fas fa-database"></i> 总内存</td><td>${MEM_TOTAL}</td></tr>
                    <tr><td><i class="fas fa-fire"></i> 已用</td><td>${MEM_USED}</td></tr>
                    <tr><td><i class="fas fa-check-circle"></i> 空闲</td><td>${MEM_FREE}</td></tr>
                    <tr><td><i class="fas fa-share-alt"></i> 共享</td><td>${MEM_SHARED}</td></tr>
                    <tr><td><i class="fas fa-archive"></i> 缓存/缓冲</td><td>${MEM_BUFF}</td></tr>
                    <tr><td><i class="fas fa-check-double"></i> 可用</td><td>${MEM_AVAIL}</td></tr>
                </table>
            </div>
            <div>
                <h3><i class="fas fa-exchange-alt"></i> 交换分区 (Swap)</h3>
                <table>
                    <tr><th>项目</th><th>值</th></tr>
                    <tr><td><i class="fas fa-database"></i> 总Swap</td><td>${SWAP_TOTAL:-0B}</td></tr>
                    <tr><td><i class="fas fa-fire"></i> 已用</td><td>${SWAP_USED:-0B}</td></tr>
                    <tr><td><i class="fas fa-check-circle"></i> 空闲</td><td>${SWAP_FREE:-0B}</td></tr>
                    <tr><td><i class="fas fa-toggle-on"></i> 状态</td><td>${SWAP_STATUS}</td></tr>
                </table>
                <h3><i class="fas fa-expand-arrows-alt"></i> 大页内存 (HugePages)</h3>
                <table>
                    <tr><th>项目</th><th>值</th></tr>
                    <tr><td><i class="fas fa-layer-group"></i> 总大页数</td><td>${HUGEPAGES_TOTAL:-0}</td></tr>
                    <tr><td><i class="fas fa-check"></i> 空闲大页</td><td>${HUGEPAGES_FREE:-0}</td></tr>
                    <tr><td><i class="fas fa-expand"></i> 大页大小</td><td>${HUGEPAGE_SIZE:-0} KB</td></tr>
                </table>
            </div>
        </div>
EOF

MEM_MODULES=""
if command -v dmidecode &>/dev/null && [ "$(id -u)" -eq 0 ]; then
    MEM_MODULES=$(dmidecode -t memory 2>/dev/null | grep -E "Size:|Type:|Speed:|Manufacturer:|Locator:" | grep -v "No Module\|Unknown\|Empty" | head -60 | html_escape)
fi

if [ -n "$MEM_MODULES" ]; then
    echo "<h3><i class=\"fas fa-list-ol\"></i> 内存条详情</h3><div class=\"code-block\"><pre>${MEM_MODULES}</pre></div>" >> "$HTML_REPORT"
else
    echo "<h3><i class=\"fas fa-list-ol\"></i> 内存条详情</h3><div class=\"code-block\"><pre>需要 root 权限运行 dmidecode 获取内存条详细信息</pre></div>" >> "$HTML_REPORT"
fi
end_section

# ------------------------------------------------------------
# 4d. 进程监控
# ------------------------------------------------------------
add_section "进程监控" "fas fa-tasks" ""

PROC_TOTAL=$(ps -e --no-headers 2>/dev/null | wc -l)
PROC_RUNNING=$(ps -e --no-headers -o stat 2>/dev/null | grep -c "^R")
PROC_SLEEPING=$(ps -e --no-headers -o stat 2>/dev/null | grep -c "^S")
PROC_STOPPED=$(ps -e --no-headers -o stat 2>/dev/null | grep -c "^T")
PROC_ZOMBIE=$(ps -e --no-headers -o stat 2>/dev/null | grep -c "^Z")
PROC_UNINTERRUPT=$(ps -e --no-headers -o stat 2>/dev/null | grep -c "^D")

if [ "${PROC_ZOMBIE:-0}" -gt 0 ]; then
    ZOMBIE_STATUS=$(add_status_badge "发现${PROC_ZOMBIE}个僵尸进程" "critical")
    ZOMBIE_LIST=$(ps -eo pid,ppid,stat,cmd --no-headers 2>/dev/null | grep "^.*Z" | head -10 | html_escape)
    ZOMBIE_COLOR="var(--danger-color)"
else
    ZOMBIE_STATUS=$(add_status_badge "无僵尸进程" "ok")
    ZOMBIE_LIST=""
    ZOMBIE_COLOR="var(--primary-color)"
fi

cat >> "$HTML_REPORT" << EOF
        <div class="metric-grid">
            <div class="metric-item"><i class="fas fa-list fa-2x"></i><div class="metric-value">${PROC_TOTAL}</div><div class="metric-label">进程总数</div></div>
            <div class="metric-item"><i class="fas fa-running fa-2x"></i><div class="metric-value">${PROC_RUNNING}</div><div class="metric-label">运行中</div></div>
            <div class="metric-item"><i class="fas fa-bed fa-2x"></i><div class="metric-value">${PROC_SLEEPING}</div><div class="metric-label">睡眠中</div></div>
            <div class="metric-item"><i class="fas fa-ghost fa-2x"></i><div class="metric-value" style="color:${ZOMBIE_COLOR}">${PROC_ZOMBIE}</div><div class="metric-label">僵尸进程</div></div>
            <div class="metric-item"><i class="fas fa-pause fa-2x"></i><div class="metric-value">${PROC_STOPPED}</div><div class="metric-label">已停止</div></div>
            <div class="metric-item"><i class="fas fa-lock fa-2x"></i><div class="metric-value">${PROC_UNINTERRUPT}</div><div class="metric-label">不可中断</div></div>
        </div>
        <div style="margin: 15px 0;">${ZOMBIE_STATUS}</div>
        <div class="grid-2">
            <div class="code-block"><h4>CPU使用前10</h4><pre>$(ps -eo pid,user,%cpu,%mem,stat,cmd --sort=-%cpu --no-headers 2>/dev/null | head -10 | html_escape)</pre></div>
            <div class="code-block"><h4>内存使用前10</h4><pre>$(ps -eo pid,user,%cpu,%mem,stat,cmd --sort=-%mem --no-headers 2>/dev/null | head -10 | html_escape)</pre></div>
        </div>
EOF

if [ -n "$ZOMBIE_LIST" ]; then
    echo "<h3><i class=\"fas fa-ghost\"></i> 僵尸进程列表</h3><div class=\"code-block\"><pre>${ZOMBIE_LIST}</pre></div>" >> "$HTML_REPORT"
fi
end_section

# ------------------------------------------------------------
# 5. 存储分析
# ------------------------------------------------------------
add_section "存储分析" "fas fa-hdd" ""
cat >> "$HTML_REPORT" << 'EOF'
        <div class="search-box">
            <i class="fas fa-search"></i>
            <input type="text" placeholder="搜索文件系统或挂载点..." onkeyup="filterTable(this, 'diskTable')">
        </div>
        <table id="diskTable">
            <tr><th>文件系统</th><th>挂载点</th><th>总大小</th><th>已用</th><th>可用</th><th>使用率</th><th>状态</th></tr>
EOF

df -h 2>/dev/null | awk 'NR>1 && !/tmpfs|devtmpfs|overlay/ {print $1, $6, $2, $3, $4, $5}' | while read -r fs mount size used avail use_pct; do
    [ -z "$fs" ] && continue
    if [ ${#fs} -gt 30 ]; then
        fs_display="${fs:0:30}..."
    else
        fs_display="$fs"
    fi
    if [ ${#mount} -gt 30 ]; then
        mount_display="${mount:0:30}..."
    else
        mount_display="$mount"
    fi
    use_pct_num=$(echo "$use_pct" | sed 's/%//')
    if [ "${use_pct_num:-0}" -gt 90 ]; then
        status=$(add_status_badge "危险" "critical")
        seg_color="var(--danger-color)"
    elif [ "${use_pct_num:-0}" -gt 80 ]; then
        status=$(add_status_badge "警告" "warning")
        seg_color="var(--warning-color)"
    else
        status=$(add_status_badge "正常" "ok")
        seg_color="var(--success-color)"
    fi
    seg_total=20
    seg_filled=$(( (use_pct_num * seg_total + 50) / 100 ))
    [ "$seg_filled" -lt 1 ] && [ "$use_pct_num" -gt 0 ] && seg_filled=1
    seg_html=""
    seg_i=0
    while [ "$seg_i" -lt "$seg_total" ]; do
        if [ "$seg_i" -lt "$seg_filled" ]; then
            seg_html="${seg_html}<span class=\"seg filled\" style=\"background:${seg_color}\"></span>"
        else
            seg_html="${seg_html}<span class=\"seg\"></span>"
        fi
        seg_i=$((seg_i + 1))
    done
    echo "<tr><td title=\"${fs}\">${fs_display}</td><td title=\"${mount}\">${mount_display}</td><td>${size}</td><td>${used}</td><td>${avail}</td><td><div class=\"seg-bar\">${seg_html}<span class=\"seg-pct\">${use_pct}</span></div></td><td>${status}</td></tr>" >> "$HTML_REPORT"
done

echo "</table>" >> "$HTML_REPORT"

cat >> "$HTML_REPORT" << 'EOF'
        <h3><i class="fas fa-hdd"></i> 块设备信息</h3>
EOF

LSBLK_OUTPUT=$(lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL 2>/dev/null | head -25 | html_escape)
if [ -n "$LSBLK_OUTPUT" ]; then
    echo "<div class=\"code-block\"><pre>${LSBLK_OUTPUT}</pre></div>" >> "$HTML_REPORT"
else
    echo "<div class=\"code-block\"><pre>lsblk 命令不可用</pre></div>" >> "$HTML_REPORT"
fi

cat >> "$HTML_REPORT" << 'EOF'
        <h3><i class="fas fa-file-alt"></i> Inode 使用情况</h3>
EOF

echo "<table><tr><th>文件系统</th><th>挂载点</th><th>总Inode</th><th>已用</th><th>可用</th><th>使用率</th></tr>" >> "$HTML_REPORT"
df -i 2>/dev/null | awk 'NR>1 && !/tmpfs|devtmpfs|overlay/ {print $1, $6, $2, $3, $4, $5}' | while read -r fs mount itotal iused iavail iuse; do
    [ -z "$fs" ] && continue
    if [ ${#fs} -gt 30 ]; then
        fs_display="${fs:0:30}..."
    else
        fs_display="$fs"
    fi
    if [ ${#mount} -gt 30 ]; then
        mount_display="${mount:0:30}..."
    else
        mount_display="$mount"
    fi
    echo "<tr><td title=\"${fs}\">${fs_display}</td><td title=\"${mount}\">${mount_display}</td><td>${itotal}</td><td>${iused}</td><td>${iavail}</td><td>${iuse}</td></tr>" >> "$HTML_REPORT"
done
echo "</table>" >> "$HTML_REPORT"

if command -v lvs &>/dev/null; then
    LVM_OUTPUT=$(lvs 2>/dev/null | html_escape)
    if [ -n "$LVM_OUTPUT" ]; then
        echo "<h3><i class=\"fas fa-layer-group\"></i> LVM 逻辑卷</h3><div class=\"code-block\"><pre>${LVM_OUTPUT}</pre></div>" >> "$HTML_REPORT"
    fi
fi

cat >> "$HTML_REPORT" << EOF
        <h3><i class="fas fa-mount"></i> 挂载信息</h3>
        <div class="code-block"><pre>$(mount 2>/dev/null | grep -v "cgroup\|proc\|sysfs\|devpts\|mqueue\|tmpfs\|securityfs" | head -15 | html_escape)</pre></div>
EOF
end_section

# ------------------------------------------------------------
# 6. 网络监控
# ------------------------------------------------------------
add_section "网络监控" "fas fa-network-wired" ""
cat >> "$HTML_REPORT" << 'EOF'
        <h3><i class="fas fa-plug"></i> 网络接口信息</h3>
        <table>
            <tr><th>接口</th><th>IP地址</th><th>MAC地址</th><th>状态</th><th>速度</th></tr>
EOF

ip link show 2>/dev/null | grep "^[0-9]:" | awk -F: '{print $2}' | tr -d ' ' | while read -r iface; do
    [ -z "$iface" ] && continue
    ip_addr=$(ip addr show "$iface" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
    mac=$(ip link show "$iface" 2>/dev/null | grep "link/ether" | awk '{print $2}')
    state=$(ip link show "$iface" 2>/dev/null | grep -o "state [A-Z]*" | awk '{print $2}')
    speed=$(ethtool "$iface" 2>/dev/null | grep Speed | awk '{print $2}')

    case "$iface" in
        lo|docker*|br-*|veth*|virbr*|tun*|tap*|flannel*|cni*|calico*)
            if [ "$state" = "UP" ]; then
                state_badge=$(add_status_badge "在线" "ok")
            else
                state_badge=$(add_status_badge "离线" "info")
            fi ;;
        *)
            if [ "$state" = "UP" ]; then
                state_badge=$(add_status_badge "在线" "ok")
            else
                state_badge=$(add_status_badge "离线" "critical")
            fi ;;
    esac
    echo "<tr><td>${iface}</td><td>${ip_addr:-无IP}</td><td>${mac:-未知}</td><td>${state_badge}</td><td>${speed:-未知}</td></tr>" >> "$HTML_REPORT"
done

echo "</table>" >> "$HTML_REPORT"

# 网络连接统计
cat >> "$HTML_REPORT" << 'EOF'
        <h3><i class="fas fa-chart-bar"></i> 网络连接统计</h3>
EOF
SS_SUMMARY=$(ss -s 2>/dev/null | head -10 | html_escape)
if [ -n "$SS_SUMMARY" ]; then
    echo "<div class=\"code-block\"><pre>${SS_SUMMARY}</pre></div>" >> "$HTML_REPORT"
else
    echo "<div class=\"code-block\"><pre>ss 命令不可用</pre></div>" >> "$HTML_REPORT"
fi

# 监听端口表格（带进程关联）
cat >> "$HTML_REPORT" << 'EOF'
        <h3><i class="fas fa-plug"></i> 监听端口</h3>
        <div class="search-box">
            <i class="fas fa-search"></i>
            <input type="text" placeholder="搜索端口或进程..." onkeyup="filterTable(this, 'listenTable')">
        </div>
        <table id="listenTable">
            <tr><th>协议</th><th>监听地址</th><th>端口</th><th>进程</th><th>PID</th></tr>
EOF

if command -v ss &>/dev/null; then
    ss -tulnp 2>/dev/null | awk 'NR>1' | while IFS= read -r line; do
        [ -z "$line" ] && continue
        proto=$(echo "$line" | awk '{print $1}')
        addr_port=$(echo "$line" | awk '{print $5}')
        local_port=$(echo "$addr_port" | grep -oE '[0-9]+$')
        local_addr=$(echo "$addr_port" | sed "s/:${local_port}\$//" | sed 's/\[//g;s/\]//g')
        [ -z "$local_addr" ] || [ "$local_addr" = "*" ] && local_addr="0.0.0.0"

        proc_name=$(echo "$line" | sed -n 's/.*users:(("\([^"]*\)".*/\1/p')
        proc_pid=$(echo "$line" | sed -n 's/.*pid=\([0-9]*\).*/\1/p')

        case "$proto" in
            tcp)  proto_disp="<span style='color:var(--primary-color);font-weight:600'>TCP</span>" ;;
            udp)  proto_disp="<span style='color:var(--warning-color);font-weight:600'>UDP</span>" ;;
            *)    proto_disp="$proto" ;;
        esac

        if [ -n "$proc_name" ]; then
            proc_disp="<i class='fas fa-cog' style='color:var(--success-color)'></i> ${proc_name}"
        else
            proc_disp="<span style='opacity:0.5'>需要root权限</span>"
        fi
        [ -z "$proc_pid" ] && proc_pid="-"

        echo "<tr><td>${proto_disp}</td><td><code>${local_addr}</code></td><td><strong>${local_port}</strong></td><td>${proc_disp}</td><td>${proc_pid}</td></tr>" >> "$HTML_REPORT"
    done
else
    echo "<tr><td colspan=\"5\" style=\"text-align:center\">ss 命令不可用</td></tr>" >> "$HTML_REPORT"
fi

echo "</table>" >> "$HTML_REPORT"

# 已建立连接统计
cat >> "$HTML_REPORT" << 'EOF'
        <h3><i class="fas fa-exchange-alt"></i> 连接状态统计</h3>
        <table>
            <tr><th>状态</th><th>数量</th><th>说明</th></tr>
EOF

if command -v ss &>/dev/null; then
    ESTAB_COUNT=$(ss -tn state established 2>/dev/null | tail -n +2 | wc -l)
    TIME_WAIT_COUNT=$(ss -tn state time-wait 2>/dev/null | tail -n +2 | wc -l)
    CLOSE_WAIT_COUNT=$(ss -tn state close-wait 2>/dev/null | tail -n +2 | wc -l)
    LISTEN_COUNT=$(ss -tln 2>/dev/null | tail -n +2 | wc -l)

    echo "<tr><td><span style='color:var(--success-color);font-weight:600'>ESTABLISHED</span></td><td>${ESTAB_COUNT}</td><td>已建立连接</td></tr>" >> "$HTML_REPORT"
    echo "<tr><td><span style='color:var(--warning-color);font-weight:600'>TIME-WAIT</span></td><td>${TIME_WAIT_COUNT}</td><td>等待关闭</td></tr>" >> "$HTML_REPORT"
    echo "<tr><td><span style='color:var(--danger-color);font-weight:600'>CLOSE-WAIT</span></td><td>${CLOSE_WAIT_COUNT}</td><td>对端已关闭</td></tr>" >> "$HTML_REPORT"
    echo "<tr><td><span style='color:var(--primary-color);font-weight:600'>LISTEN</span></td><td>${LISTEN_COUNT}</td><td>监听中</td></tr>" >> "$HTML_REPORT"
else
    echo "<tr><td colspan=\"3\">ss 命令不可用</td></tr>" >> "$HTML_REPORT"
fi

echo "</table>" >> "$HTML_REPORT"

# 已建立连接详情
if command -v ss &>/dev/null; then
    ESTAB_DETAIL=$(ss -tnp state established 2>/dev/null | head -15 | html_escape)
    if [ -n "$ESTAB_DETAIL" ]; then
        echo "<h3><i class=\"fas fa-link\"></i> 已建立连接详情 (Top 15)</h3><div class=\"code-block\"><pre>${ESTAB_DETAIL}</pre></div>" >> "$HTML_REPORT"
    fi
fi
end_section

# ------------------------------------------------------------
# 7. 服务状态
# ------------------------------------------------------------
if [ "$SYSTEMCTL_AVAILABLE" = "1" ]; then
    add_section "服务状态" "fas fa-cogs" ""
    cat >> "$HTML_REPORT" << 'EOF'
        <div class="search-box">
            <i class="fas fa-search"></i>
            <input type="text" placeholder="搜索服务名称..." onkeyup="filterTable(this, 'serviceTable')">
        </div>
        <table id="serviceTable">
            <tr><th>服务名称</th><th>状态</th><th>启用</th><th>描述</th></tr>
EOF

    SERVICES=("sshd" "nginx" "httpd" "apache2" "mysql" "mariadb" "postgresql" "redis" "mongod" "docker" "crond" "cron" "rsyslog" "systemd-journald" "network" "dbus" "snmpd" "zabbix-agent" "node_exporter")

    for service in "${SERVICES[@]}"; do
        if systemctl is-active "$service" &>/dev/null; then
            status=$(add_status_badge "运行中" "ok")
        elif systemctl is-enabled "$service" &>/dev/null 2>&1; then
            status=$(add_status_badge "已停止" "warning")
        else
            status=$(add_status_badge "未安装" "info")
        fi

        if systemctl is-enabled "$service" &>/dev/null 2>&1; then
            enabled=$(add_status_badge "是" "ok")
        else
            enabled=$(add_status_badge "否" "warning")
        fi

        description=$(systemctl show "$service" --property=Description 2>/dev/null | cut -d= -f2)
        [ -z "$description" ] && description="系统服务"

        echo "<tr><td><i class=\"fas fa-cube\"></i> $service</td><td>$status</td><td>$enabled</td><td>$description</td></tr>" >> "$HTML_REPORT"
    done

    echo "</table>" >> "$HTML_REPORT"
    end_section
fi

# ------------------------------------------------------------
# 8. 安全审计
# ------------------------------------------------------------
add_section "安全审计" "fas fa-user-shield" ""

WHO_ROWS=""
while IFS=$'\t' read -r user term dt src; do
    [ -z "$user" ] && continue
    user_esc=$(echo "$user" | html_escape)
    term_esc=$(echo "$term" | html_escape)
    dt_esc=$(echo "$dt" | html_escape)
    src_esc=$(echo "$src" | html_escape)
    WHO_ROWS="${WHO_ROWS}<tr><td><strong>${user_esc}</strong></td><td>${term_esc}</td><td>${dt_esc}</td><td>${src_esc}</td></tr>"
done < <(who 2>/dev/null | head -10 | awk '
{
    user=$1; term=$2;
    rest=""; for(i=3;i<=NF;i++) rest=rest" "$i; sub(/^ /,"",rest);
    if (match(rest,/\([^)]*\)/)) {
        src=substr(rest,RSTART,RLENGTH); gsub(/[()]/,"",src);
        dt=substr(rest,1,RSTART-1); sub(/ $/,"",dt);
    } else { src="-"; dt=rest; }
    printf "%s\t%s\t%s\t%s\n", user, term, dt, src;
}')
[ -z "$WHO_ROWS" ] && WHO_ROWS="<tr><td colspan='4' style='text-align:center;color:var(--text-muted)'>无登录用户</td></tr>"

LAST_ROWS=""
while IFS=$'\t' read -r user term src rest; do
    [ -z "$user" ] && continue
    user_esc=$(echo "$user" | html_escape)
    term_esc=$(echo "$term" | html_escape)
    src_esc=$(echo "$src" | html_escape)
    rest_esc=$(echo "$rest" | html_escape)
    LAST_ROWS="${LAST_ROWS}<tr><td><strong>${user_esc}</strong></td><td>${term_esc}</td><td>${src_esc}</td><td>${rest_esc}</td></tr>"
done < <(last -10 2>/dev/null | head -10 | awk '
/wtmp begins/ { next }
NF==0 { next }
{
    user=$1; term=$2; src=$3;
    rest=""; for(i=4;i<=NF;i++) rest=rest" "$i; sub(/^ /,"",rest);
    printf "%s\t%s\t%s\t%s\n", user, term, src, rest;
}')
[ -z "$LAST_ROWS" ] && LAST_ROWS="<tr><td colspan='4' style='text-align:center;color:var(--text-muted)'>无登录记录</td></tr>"

ONLINE_USERS=$(who 2>/dev/null | wc -l)
OPEN_PORTS=$(ss -tuln 2>/dev/null | grep -c LISTEN 2>/dev/null || echo "0")
RECENT_ERRORS=$(journalctl -p 3 --since="1 hour ago" 2>/dev/null | wc -l)
UPTIME_DAYS=$(awk '{print int($1/86400)"d"}' /proc/uptime 2>/dev/null || echo "未知")

cat >> "$HTML_REPORT" << EOF
        <div class="grid-2">
            <div>
                <h3><i class="fas fa-users"></i> 当前登录用户</h3>
                <table>
                    <tr><th>用户</th><th>终端</th><th>登录时间</th><th>来源</th></tr>
                    ${WHO_ROWS}
                </table>
            </div>
            <div>
                <h3><i class="fas fa-history"></i> 最近登录</h3>
                <table>
                    <tr><th>用户</th><th>终端</th><th>来源</th><th>时间/状态</th></tr>
                    ${LAST_ROWS}
                </table>
            </div>
        </div>
        <h3><i class="fas fa-shield-alt"></i> 系统安全状态</h3>
        <div class="overview-grid">
            <div class="overview-card">
                <div class="overview-icon"><i class="fas fa-user-check"></i></div>
                <div class="overview-info"><div class="overview-value">${ONLINE_USERS}</div><div class="overview-label">在线用户</div></div>
            </div>
            <div class="overview-card">
                <div class="overview-icon"><i class="fas fa-door-open"></i></div>
                <div class="overview-info"><div class="overview-value">${OPEN_PORTS}</div><div class="overview-label">开放端口</div></div>
            </div>
            <div class="overview-card">
                <div class="overview-icon"><i class="fas fa-exclamation-triangle"></i></div>
                <div class="overview-info"><div class="overview-value">${RECENT_ERRORS}</div><div class="overview-label">近期错误</div></div>
            </div>
            <div class="overview-card">
                <div class="overview-icon"><i class="fas fa-clock"></i></div>
                <div class="overview-info"><div class="overview-value">${UPTIME_DAYS}</div><div class="overview-label">运行天数</div></div>
            </div>
        </div>
EOF

SSH_VERSION=$(ssh -V 2>&1 | head -1 | html_escape)
SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
[ -z "$SSH_PORT" ] && SSH_PORT="22 (默认)"
SSH_PERMIT_ROOT=$(grep -E "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
[ -z "$SSH_PERMIT_ROOT" ] && SSH_PERMIT_ROOT="yes (默认)"
SSH_PASSWORD_AUTH=$(grep -E "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
[ -z "$SSH_PASSWORD_AUTH" ] && SSH_PASSWORD_AUTH="yes (默认)"
SSH_PUBKEY_AUTH=$(grep -E "^PubkeyAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
[ -z "$SSH_PUBKEY_AUTH" ] && SSH_PUBKEY_AUTH="yes (默认)"
SSH_MAX_AUTH=$(grep -E "^MaxAuthTries" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
[ -z "$SSH_MAX_AUTH" ] && SSH_MAX_AUTH="6 (默认)"
SSH_PERMIT_EMPTY=$(grep -E "^PermitEmptyPasswords" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
[ -z "$SSH_PERMIT_EMPTY" ] && SSH_PERMIT_EMPTY="no (默认)"

if [ "$SYSTEMCTL_AVAILABLE" = "1" ]; then
    if systemctl is-active sshd &>/dev/null || systemctl is-active ssh &>/dev/null || systemctl is-active ssh.socket &>/dev/null; then
        SSH_RUN_STATUS=$(add_status_badge "运行中" "ok")
    else
        SSH_RUN_STATUS=$(add_status_badge "未运行" "critical")
    fi
    if systemctl is-enabled sshd &>/dev/null || systemctl is-enabled ssh &>/dev/null || systemctl is-enabled ssh.socket &>/dev/null; then
        SSH_ENABLED_STATUS=$(add_status_badge "是" "ok")
    else
        SSH_ENABLED_STATUS=$(add_status_badge "否" "warning")
    fi
else
    SSH_RUN_STATUS=$(add_status_badge "未知" "info")
    SSH_ENABLED_STATUS=$(add_status_badge "未知" "info")
fi

SSH_ISSUES=""
if [ "$SSH_PERMIT_ROOT" = "yes" ] || [ "$SSH_PERMIT_ROOT" = "yes (默认)" ]; then
    SSH_ISSUES="${SSH_ISSUES}<i class=\"fas fa-exclamation-triangle\" style=\"color:var(--warning-color)\"></i> 允许Root登录&nbsp;&nbsp;"
fi
if [ "$SSH_PASSWORD_AUTH" = "yes" ] || [ "$SSH_PASSWORD_AUTH" = "yes (默认)" ]; then
    SSH_ISSUES="${SSH_ISSUES}<i class=\"fas fa-exclamation-triangle\" style=\"color:var(--warning-color)\"></i> 允许密码认证&nbsp;&nbsp;"
fi
if [ "$SSH_PERMIT_EMPTY" = "yes" ]; then
    SSH_ISSUES="${SSH_ISSUES}<i class=\"fas fa-times-circle\" style=\"color:var(--danger-color)\"></i> 允许空密码"
fi

cat >> "$HTML_REPORT" << SSHEOF
        <h3><i class="fas fa-key"></i> OpenSSH 服务</h3>
        <table>
            <tr><th>项目</th><th>值</th><th>项目</th><th>值</th></tr>
            <tr><td><i class="fas fa-info-circle"></i> 版本信息</td><td>${SSH_VERSION}</td><td><i class="fas fa-plug"></i> 监听端口</td><td>${SSH_PORT}</td></tr>
            <tr><td><i class="fas fa-toggle-on"></i> 运行状态</td><td>${SSH_RUN_STATUS}</td><td><i class="fas fa-power-off"></i> 开机自启</td><td>${SSH_ENABLED_STATUS}</td></tr>
            <tr><td><i class="fas fa-user-shield"></i> Root登录</td><td>${SSH_PERMIT_ROOT}</td><td><i class="fas fa-key"></i> 密码认证</td><td>${SSH_PASSWORD_AUTH}</td></tr>
            <tr><td><i class="fas fa-id-card"></i> 公钥认证</td><td>${SSH_PUBKEY_AUTH}</td><td><i class="fas fa-lock"></i> 最大尝试</td><td>${SSH_MAX_AUTH}</td></tr>
            <tr><td><i class="fas fa-shield-alt"></i> 空密码</td><td>${SSH_PERMIT_EMPTY}</td><td colspan="2"></td></tr>
        </table>
SSHEOF
[ -n "$SSH_ISSUES" ] && echo "<div style='margin-top:8px;font-size:0.88rem;'>${SSH_ISSUES}</div>" >> "$HTML_REPORT"

end_section

# ------------------------------------------------------------
# 巡检总结
# ------------------------------------------------------------
SECTION_COUNT=$(grep -c "section fade-in" "$HTML_REPORT" 2>/dev/null | tr -dc '0-9'); [ -z "$SECTION_COUNT" ] && SECTION_COUNT=0
OK_COUNT=$(grep -c 'status-badge status-ok' "$HTML_REPORT" 2>/dev/null | tr -dc '0-9'); [ -z "$OK_COUNT" ] && OK_COUNT=0
WARN_COUNT=$(grep -c 'status-badge status-warning' "$HTML_REPORT" 2>/dev/null | tr -dc '0-9'); [ -z "$WARN_COUNT" ] && WARN_COUNT=0
CRIT_COUNT=$(grep -c 'status-badge status-critical' "$HTML_REPORT" 2>/dev/null | tr -dc '0-9'); [ -z "$CRIT_COUNT" ] && CRIT_COUNT=0

HEALTH_SCORE=100
if [ "${WARN_COUNT:-0}" -gt 0 ]; then
    HEALTH_SCORE=$((HEALTH_SCORE - WARN_COUNT * 1))
fi
if [ "${CRIT_COUNT:-0}" -gt 0 ]; then
    HEALTH_SCORE=$((HEALTH_SCORE - CRIT_COUNT * 10))
fi
if [ "$HEALTH_SCORE" -lt 0 ]; then
    HEALTH_SCORE=0
fi

HEALTH_CIRCUMFERENCE=376.99
HEALTH_OFFSET=$(awk -v c="$HEALTH_CIRCUMFERENCE" -v s="$HEALTH_SCORE" 'BEGIN { printf "%.2f", c - (c * s / 100) }')

if [ "$HEALTH_SCORE" -ge 80 ]; then
    HEALTH_COLOR="#22C55E"; HEALTH_LABEL="系统健康"
elif [ "$HEALTH_SCORE" -ge 60 ]; then
    HEALTH_COLOR="#F59E0B"; HEALTH_LABEL="需要注意"
else
    HEALTH_COLOR="#EF4444"; HEALTH_LABEL="需要处理"
fi

DANGER_LIST=""
CURRENT_SEC=""
while IFS= read -r line; do
    if echo "$line" | grep -q 'section-title.*collapsible'; then
        CURRENT_SEC=$(echo "$line" | sed 's/<[^>]*>//g; s/^[[:space:]]*//')
    fi
    if echo "$line" | grep -q 'status-badge status-critical'; then
        BADGE_TEXT=$(echo "$line" | sed 's/.*<\/i> //;s/<\/span>.*//')
        [ "$BADGE_TEXT" = "危险" ] && BADGE_TEXT="使用率>90%"
        [ "$BADGE_TEXT" = "警告" ] && BADGE_TEXT="使用率>80%"
        if echo "$line" | grep -q '<td'; then
            TD_CONTEXT=$(echo "$line" | awk -F'<td[^>]*>' '{
                count=0
                for(i=2;i<=NF;i++) {
                    cell=$i; sub(/<\/td>.*/, "", cell)
                    gsub(/<[^>]*>/, "", cell); gsub(/^[ \t]+|[ \t]+$/, "", cell)
                    if (cell!="" && cell!~ /^(在线|离线|运行中|已停止|未安装|已安装|激活|未激活|运行|未运行|是|否|正常|警告|危险|已配置|未检测到|无Swap|已启用|无防火墙)$/ && count<2) {
                        printf "%s | ", cell; count++
                    }
                }
            }' | sed 's/ | $//')
            if [ -n "$TD_CONTEXT" ]; then
                ITEM="${TD_CONTEXT} - ${BADGE_TEXT}"
            else
                ITEM="$BADGE_TEXT"
            fi
        else
            ITEM="$BADGE_TEXT"
        fi
        if [ -n "$ITEM" ] && [ -n "$CURRENT_SEC" ]; then
            ITEM_ESC=$(echo "$ITEM" | html_escape)
            SEC_ESC=$(echo "$CURRENT_SEC" | html_escape)
            DANGER_LIST="${DANGER_LIST}<tr><td><strong>${SEC_ESC}</strong></td><td><i class=\"fas fa-exclamation-circle\" style=\"color:var(--danger-color)\"></i> ${ITEM_ESC}</td></tr>"
        fi
    fi
done < "$HTML_REPORT"
[ -z "$DANGER_LIST" ] && DANGER_LIST="<tr><td colspan='2' style='text-align:center;color:var(--text-muted)'>无危险项目</td></tr>"

WARNING_LIST=""
CURRENT_SEC=""
while IFS= read -r line; do
    if echo "$line" | grep -q 'section-title.*collapsible'; then
        CURRENT_SEC=$(echo "$line" | sed 's/<[^>]*>//g; s/^[[:space:]]*//')
    fi
    if echo "$line" | grep -q 'status-badge status-warning'; then
        BADGE_TEXT=$(echo "$line" | sed 's/.*<\/i> //;s/<\/span>.*//')
        [ "$BADGE_TEXT" = "否" ] && BADGE_TEXT="开机未自启"
        [ "$BADGE_TEXT" = "危险" ] && BADGE_TEXT="使用率>90%"
        [ "$BADGE_TEXT" = "警告" ] && BADGE_TEXT="使用率>80%"
        if echo "$line" | grep -q '<td'; then
            TD_CONTEXT=$(echo "$line" | awk -F'<td[^>]*>' '{
                count=0
                for(i=2;i<=NF;i++) {
                    cell=$i; sub(/<\/td>.*/, "", cell)
                    gsub(/<[^>]*>/, "", cell); gsub(/^[ \t]+|[ \t]+$/, "", cell)
                    if (cell!="" && cell!~ /^(在线|离线|运行中|已停止|未安装|已安装|激活|未激活|运行|未运行|是|否|正常|警告|危险|已配置|未检测到|无Swap|已启用|无防火墙)$/ && count<2) {
                        printf "%s | ", cell; count++
                    }
                }
            }' | sed 's/ | $//')
            if [ -n "$TD_CONTEXT" ]; then
                ITEM="${TD_CONTEXT} - ${BADGE_TEXT}"
            else
                ITEM="$BADGE_TEXT"
            fi
        else
            ITEM="$BADGE_TEXT"
        fi
        if [ -n "$ITEM" ] && [ -n "$CURRENT_SEC" ]; then
            ITEM_ESC=$(echo "$ITEM" | html_escape)
            SEC_ESC=$(echo "$CURRENT_SEC" | html_escape)
            WARNING_LIST="${WARNING_LIST}<tr><td><strong>${SEC_ESC}</strong></td><td><i class=\"fas fa-exclamation-triangle\" style=\"color:var(--warning-color)\"></i> ${ITEM_ESC}</td></tr>"
        fi
    fi
done < "$HTML_REPORT"
[ -z "$WARNING_LIST" ] && WARNING_LIST="<tr><td colspan='2' style='text-align:center;color:var(--text-muted)'>无警告项目</td></tr>"

cat >> "$HTML_REPORT" << EOF
        <div class="section fade-in" id="sec-巡检总结">
            <h2 class="section-title collapsible-header" onclick="toggleSection(this)"><i class="fas fa-flag-checkered"></i>巡检总结<i class="fas fa-chevron-down collapse-icon"></i></h2>
            <div class="section-body">
                <div style="display:flex;align-items:center;gap:24px;padding:12px 16px;">
                    <div class="health-gauge" style="margin:0;flex-shrink:0;">
                        <svg width="120" height="120" viewBox="0 0 140 140">
                            <circle class="track" cx="70" cy="70" r="60"></circle>
                            <circle class="fill" cx="70" cy="70" r="60" stroke="${HEALTH_COLOR}" stroke-dasharray="${HEALTH_CIRCUMFERENCE}" stroke-dashoffset="${HEALTH_CIRCUMFERENCE}" data-offset="${HEALTH_OFFSET}" id="healthFill"></circle>
                        </svg>
                        <div class="center">
                            <div class="score" style="color: ${HEALTH_COLOR}" id="healthScore">0</div>
                            <div class="label">${HEALTH_LABEL}</div>
                        </div>
                    </div>
                    <div style="flex:1;">
                        <h3 style="color: var(--success-color); margin:0 0 4px 0; font-size:1.15rem;">系统巡检完成</h3>
                        <p style="font-size:0.82rem; margin:0 0 10px 0; opacity:0.8; color:var(--text-secondary);">报告生成时间: $(date "+%Y-%m-%d %H:%M:%S")</p>
                        <div class="overview-grid">
                            <div class="overview-card">
                                <div class="overview-icon"><i class="fas fa-clipboard-list"></i></div>
                                <div class="overview-info"><div class="overview-value">${SECTION_COUNT}</div><div class="overview-label">检查项目</div></div>
                            </div>
                            <div class="overview-card">
                                <div class="overview-icon" style="color:var(--success-color)"><i class="fas fa-check-circle"></i></div>
                                <div class="overview-info"><div class="overview-value" style="color:var(--success-color)">${OK_COUNT}</div><div class="overview-label">正常</div></div>
                            </div>
                            <div class="overview-card">
                                <div class="overview-icon" style="color:var(--warning-color)"><i class="fas fa-exclamation-triangle"></i></div>
                                <div class="overview-info"><div class="overview-value" style="color:var(--warning-color)">${WARN_COUNT}</div><div class="overview-label">警告</div></div>
                            </div>
                            <div class="overview-card">
                                <div class="overview-icon" style="color:var(--danger-color)"><i class="fas fa-times-circle"></i></div>
                                <div class="overview-info"><div class="overview-value" style="color:var(--danger-color)">${CRIT_COUNT}</div><div class="overview-label">危险</div></div>
                            </div>
                        </div>
                    </div>
                </div>
                <h3><i class="fas fa-times-circle"></i> 危险项目详情</h3>
                <table>
                    <tr><th>模块</th><th>问题</th></tr>
                    ${DANGER_LIST}
                </table>
                <h3><i class="fas fa-exclamation-triangle"></i> 警告项目详情</h3>
                <table>
                    <tr><th>模块</th><th>问题</th></tr>
                    ${WARNING_LIST}
                </table>
            </div>
        </div>
    </div>

    <button class="back-to-top" id="backToTop" onclick="scrollToTop()"><i class="fas fa-arrow-up"></i></button>

    <script>
        // ---- 主题切换 ----
        function setTheme(theme) {
            document.documentElement.setAttribute('data-theme', theme);
            localStorage.setItem('li-theme', theme);
            document.querySelectorAll('.theme-btn').forEach(function(btn) {
                btn.classList.toggle('active', btn.getAttribute('data-theme') === theme);
            });
        }
        function applyCustomTheme(color) {
            var hex = color.replace('#', '');
            var r = parseInt(hex.substr(0,2), 16);
            var g = parseInt(hex.substr(2,2), 16);
            var b = parseInt(hex.substr(4,2), 16);
            var hsl = rgbToHsl(r, g, b);
            var h = hsl[0], s = hsl[1], l = hsl[2];
            var isDark = l < 0.4;
            var root = document.documentElement;
            root.setAttribute('data-theme', 'light');
            var vars = {
                '--primary-color': 'hsl(' + h + ',' + s + '%,' + (isDark ? 70 : 55) + '%)',
                '--primary-light': 'hsl(' + h + ',' + s + '%,' + (isDark ? 80 : 65) + '%)',
                '--accent-color': 'hsl(' + ((h + 20) % 360) + ',' + s + '%,' + (isDark ? 65 : 50) + '%)',
                '--bg-page': isDark ? 'hsl(' + h + ',15%,8%)' : 'hsl(' + h + ',30%,97%)',
                '--bg-card': isDark ? 'hsl(' + h + ',15%,12%)' : '#FFFFFF',
                '--bg-sidebar': isDark ? 'hsl(' + h + ',15%,8%,0.92)' : 'rgba(255,255,255,0.98)',
                '--bg-header': isDark ? 'hsl(' + h + ',15%,12%,0.6)' : '#FFFFFF',
                '--bg-code': isDark ? 'hsl(' + h + ',15%,6%)' : 'hsl(' + h + ',30%,97%)',
                '--bg-table': isDark ? 'hsl(' + h + ',15%,10%,0.4)' : '#FFFFFF',
                '--bg-tab-active': 'hsla(' + h + ',' + s + '%,50%,0.1)',
                '--bg-input': isDark ? 'hsl(' + h + ',15%,10%,0.6)' : 'hsl(' + h + ',30%,97%)',
                '--bg-timestamp': 'linear-gradient(135deg, hsla(' + h + ',' + s + '%,50%,0.08), hsla(' + h + ',' + s + '%,60%,0.05))',
                '--bg-metric': 'hsla(' + h + ',' + s + '%,50%,0.04)',
                '--row-alt': 'hsla(' + h + ',' + s + '%,50%,0.03)',
                '--text-primary': isDark ? 'hsl(' + h + ',20%,92%)' : '#1F2937',
                '--text-secondary': isDark ? 'hsl(' + h + ',15%,70%)' : '#6B7280',
                '--text-muted': isDark ? 'hsl(' + h + ',10%,50%)' : '#9CA3AF',
                '--border-color': isDark ? 'hsla(' + h + ',' + s + '%,50%,0.15)' : 'hsl(' + h + ',40%,93%)',
                '--border-light': isDark ? 'hsla(' + h + ',' + s + '%,50%,0.08)' : 'hsl(' + h + ',40%,97%)',
                '--shadow-card': isDark ? '0 4px 16px rgba(0,0,0,0.4)' : '0 4px 16px hsla(' + h + ',' + s + '%,50%,0.08)',
                '--shadow-hover': isDark ? '0 8px 32px rgba(0,0,0,0.5)' : '0 8px 32px hsla(' + h + ',' + s + '%,50%,0.12)',
                '--success-color': '#22C55E', '--warning-color': '#F59E0B', '--danger-color': '#EF4444', '--info-color': '#3B82F6',
                '--code-text': isDark ? 'hsl(' + h + ',20%,75%)' : 'hsl(' + h + ',' + s + '%,35%)',
                '--grid-opacity': isDark ? '0.05' : '0.04',
                '--particle-opacity': isDark ? '0.25' : '0.3',
                '--title-gradient': 'linear-gradient(45deg, hsl(' + h + ',' + s + '%,' + (isDark?75:55) + '%), hsl(' + h + ',' + s + '%,' + (isDark?85:65) + '%), hsl(' + ((h+20)%360) + ',' + s + '%,' + (isDark?70:50) + '%), hsl(' + h + ',' + s + '%,' + (isDark?75:55) + '%))',
                '--title-shadow': '0 0 30px hsla(' + h + ',' + s + '%,50%,0.2)',
                '--nav-text': isDark ? 'hsl(' + h + ',15%,70%)' : '#6B7280',
                '--th-text': '#fff',
                '--stat-icon-shadow': '0 0 20px hsla(' + h + ',' + s + '%,50%,0.15)',
                '--card-accent': 'linear-gradient(90deg, var(--primary-color), var(--accent-color))',
                '--icon-bg': 'hsla(' + h + ',' + s + '%,50%,0.1)'
            };
            var styleId = 'custom-theme-vars';
            var existing = document.getElementById(styleId);
            if (existing) existing.remove();
            var style = document.createElement('style');
            style.id = styleId;
            var css = ':root[data-theme="light"]{';
            Object.keys(vars).forEach(function(k) { css += k + ':' + vars[k] + ';'; });
            css += '}';
            style.textContent = css;
            document.head.appendChild(style);
            localStorage.setItem('li-theme', 'light');
            localStorage.setItem('li-custom-color', color);
            document.querySelectorAll('.theme-btn').forEach(function(btn) { btn.classList.remove('active'); });
            document.querySelector('.theme-custom-btn').classList.add('active');
        }
        function rgbToHsl(r, g, b) {
            r /= 255; g /= 255; b /= 255;
            var max = Math.max(r,g,b), min = Math.min(r,g,b);
            var h, s, l = (max + min) / 2;
            if (max === min) { h = s = 0; }
            else {
                var d = max - min;
                s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
                switch(max) {
                    case r: h = (g - b) / d + (g < b ? 6 : 0); break;
                    case g: h = (b - r) / d + 2; break;
                    case b: h = (r - g) / d + 4; break;
                }
                h /= 6;
            }
            return [Math.round(h * 360), Math.round(s * 100), Math.round(l * 100) / 100];
        }
        function initThemeSwitcher() {
            var saved = localStorage.getItem('li-theme') || 'light';
            var customColor = localStorage.getItem('li-custom-color');
            if (saved === 'light' && customColor) {
                applyCustomTheme(customColor);
            } else {
                setTheme(saved);
            }
            document.querySelectorAll('.theme-btn').forEach(function(btn) {
                btn.addEventListener('click', function() {
                    localStorage.removeItem('li-custom-color');
                    var styleEl = document.getElementById('custom-theme-vars');
                    if (styleEl) styleEl.remove();
                    setTheme(this.getAttribute('data-theme'));
                });
            });
            var picker = document.getElementById('customColorPicker');
            if (picker) {
                if (customColor) picker.value = customColor;
                picker.addEventListener('input', function() { applyCustomTheme(this.value); });
            }
        }

        // ---- 加载遮罩 ----
        function hideLoading() {
            var overlay = document.getElementById('loadingOverlay');
            if (overlay) { overlay.classList.add('hidden'); setTimeout(function() { overlay.style.display = 'none'; }, 600); }
        }

        // ---- 侧边导航构建 ----
        function buildSideNav() {
            var sections = document.querySelectorAll('.section[id]');
            var navItems = document.getElementById('navItems');
            var iconMap = {
                '系统概览': 'fas fa-rocket', '资产信息': 'fas fa-barcode', '防火墙状态': 'fas fa-shield-alt',
                'Docker状态': 'fab fa-docker', '性能监控': 'fas fa-tachometer-alt',
                'CPU信息': 'fas fa-microchip', '内存信息': 'fas fa-memory', '进程监控': 'fas fa-tasks',
                '存储分析': 'fas fa-hdd', '网络监控': 'fas fa-network-wired',
                '服务状态': 'fas fa-cogs', '安全审计': 'fas fa-user-shield', '巡检总结': 'fas fa-flag-checkered'
            };
            sections.forEach(function(sec) {
                var titleEl = sec.querySelector('.section-title');
                if (!titleEl) return;
                var title = titleEl.textContent.replace(/[\s\n]/g, '').replace(' ChevronDown', '').replace('chevrondown', '');
                var id = sec.id;
                var icon = iconMap[title] || 'fas fa-circle';
                var item = document.createElement('a');
                item.className = 'side-nav-item';
                item.setAttribute('data-target', id);
                item.innerHTML = '<i class="' + icon + '"></i><span>' + title + '</span>';
                item.addEventListener('click', function() {
                    document.getElementById(this.getAttribute('data-target')).scrollIntoView({ behavior: 'smooth', block: 'start' });
                    if (window.innerWidth <= 768) { document.getElementById('sideNav').classList.remove('open'); }
                });
                navItems.appendChild(item);
            });
        }

        function setupScrollSpy() {
            var sections = document.querySelectorAll('.section[id]');
            var navItems = document.querySelectorAll('.side-nav-item');
            var observer = new IntersectionObserver(function(entries) {
                entries.forEach(function(entry) {
                    if (entry.isIntersecting) {
                        var id = entry.target.id;
                        navItems.forEach(function(item) {
                            item.classList.toggle('active', item.getAttribute('data-target') === id);
                        });
                    }
                });
            }, { rootMargin: '-20% 0px -60% 0px' });
            sections.forEach(function(sec) { observer.observe(sec); });
        }

        function setupBackToTop() {
            var btn = document.getElementById('backToTop');
            window.addEventListener('scroll', function() { btn.classList.toggle('visible', window.scrollY > 400); });
        }
        function scrollToTop() { window.scrollTo({ top: 0, behavior: 'smooth' }); }
        function toggleNav() { document.getElementById('sideNav').classList.toggle('open'); }

        function exportWord() {
            var hostname = document.querySelector('.timestamp-item:nth-child(2)') ?
                document.querySelector('.timestamp-item:nth-child(2)').textContent.replace('主机名:', '').trim() : 'linux';
            var dateStr = new Date().toISOString().slice(0, 10);
            var filename = 'Linux巡检报告_' + hostname + '_' + dateStr + '.doc';

            var container = document.querySelector('.container');
            var clone = container.cloneNode(true);

            clone.querySelectorAll('.export-bar, .back-to-top, .loading-overlay, .cyber-grid, .particles, .nav-toggle, .search-box').forEach(function(el) { el.remove(); });
            clone.querySelectorAll('.section').forEach(function(s) { s.classList.remove('collapsed'); });
            clone.querySelectorAll('.section h3.sub-collapsed').forEach(function(h3) {
                h3.classList.remove('sub-collapsed');
                var next = h3.nextElementSibling;
                while (next && next.tagName !== 'H3') { next.style.display = ''; next = next.nextElementSibling; }
            });
            clone.querySelectorAll('.tab-content').forEach(function(t) { t.classList.add('active'); });
            clone.querySelectorAll('.circular-progress svg, .health-gauge svg').forEach(function(svg) { svg.remove(); });
            clone.querySelectorAll('.circular-progress .icon-center').forEach(function(ic) { ic.remove(); });

            clone.querySelectorAll('.dashboard').forEach(function(dash) {
                var cards = dash.querySelectorAll('.stat-card');
                if (!cards.length) return;
                var table = document.createElement('table');
                var html = '<tr><th style="width:50%">指标</th><th>值</th></tr>';
                cards.forEach(function(card) {
                    var label = card.querySelector('.stat-label') ? card.querySelector('.stat-label').textContent : '';
                    var value = card.querySelector('.stat-value') ? card.querySelector('.stat-value').textContent : '';
                    if (!value) {
                        var cp = card.querySelector('.circular-progress');
                        if (cp) { var sv = card.querySelector('.stat-value'); if (sv) value = sv.textContent; }
                    }
                    html += '<tr><td>' + label + '</td><td><b>' + value + '</b></td></tr>';
                });
                table.innerHTML = html;
                dash.parentNode.replaceChild(table, dash);
            });

            clone.querySelectorAll('.overview-grid').forEach(function(grid) {
                var cards = grid.querySelectorAll('.overview-card');
                if (!cards.length) return;
                var table = document.createElement('table');
                var html = '<tr><th style="width:50%">属性</th><th>值</th></tr>';
                cards.forEach(function(card) {
                    var label = card.querySelector('.overview-label') ? card.querySelector('.overview-label').textContent : '';
                    var value = card.querySelector('.overview-value') ? card.querySelector('.overview-value').textContent : '';
                    html += '<tr><td>' + label + '</td><td><b>' + value + '</b></td></tr>';
                });
                table.innerHTML = html;
                grid.parentNode.replaceChild(table, grid);
            });

            clone.querySelectorAll('.metric-grid').forEach(function(grid) {
                var items = grid.querySelectorAll('.metric-item');
                if (!items.length) return;
                var table = document.createElement('table');
                var html = '<tr><th style="width:50%">指标</th><th>值</th></tr>';
                items.forEach(function(item) {
                    var label = item.querySelector('.metric-label') ? item.querySelector('.metric-label').textContent : '';
                    var value = item.querySelector('.metric-value') ? item.querySelector('.metric-value').textContent : '';
                    html += '<tr><td>' + label + '</td><td><b>' + value + '</b></td></tr>';
                });
                table.innerHTML = html;
                grid.parentNode.replaceChild(table, grid);
            });

            clone.querySelectorAll('.seg-bar').forEach(function(bar) {
                var pct = bar.querySelector('.seg-pct') ? bar.querySelector('.seg-pct').textContent : '';
                bar.parentNode.innerHTML = pct;
            });

            clone.querySelectorAll('.progress-container').forEach(function(pc) {
                var info = pc.querySelector('.progress-info') ? pc.querySelector('.progress-info').textContent : '';
                var fill = pc.querySelector('.progress-fill');
                var pct = '';
                if (fill) { var w = fill.style.width; pct = w ? w : ''; }
                var text = info || pct;
                var table = document.createElement('table');
                table.style.cssText = 'width:100%;border-collapse:collapse;';
                table.innerHTML = '<tr><td style="width:80%;border:0.5pt solid #D1D5DB;padding:4pt 8pt;">' + text + '</td><td style="border:0.5pt solid #D1D5DB;padding:4pt 8pt;text-align:center;"><b>' + pct + '</b></td></tr>';
                pc.parentNode.replaceChild(table, pc);
            });

            clone.querySelectorAll('.progress-bar').forEach(function(pb) {
                if (pb.closest('.progress-container')) return;
                var fill = pb.querySelector('.progress-fill');
                var pct = '';
                if (fill) { var w = fill.style.width; pct = w ? w : ''; }
                var span = document.createElement('span');
                span.textContent = pct;
                span.style.cssText = 'font-weight:700;color:#6366F1;';
                pb.parentNode.replaceChild(span, pb);
            });

            clone.querySelectorAll('div[style*="display:flex"]').forEach(function(div) {
                div.style.cssText = 'display:block;';
            });

            clone.querySelectorAll('td i, th i, h2 i, h3 i, .timestamp-item i, .status-badge i').forEach(function(icon) {
                icon.remove();
            });

            clone.querySelectorAll('.overview-icon').forEach(function(oi) { oi.remove(); });

            var wordCSS =
                '<style>' +
                '@page { size: A4; margin: 2cm 1.8cm; }' +
                'body { font-family: "Segoe UI", "Microsoft YaHei", "PingFang SC", sans-serif; font-size: 10.5pt; line-height: 1.6; color: #1F2937; }' +
                'h1 { font-size: 20pt; color: #4F46E5; text-align: center; margin: 0 0 6pt 0; padding-bottom: 8pt; border-bottom: 2.5pt solid #6366F1; }' +
                'h1 + p { text-align: center; color: #6B7280; font-size: 10pt; margin: 0 0 4pt 0; }' +
                '.timestamp { text-align: center; margin: 0 0 12pt 0; }' +
                '.timestamp-item { display: inline; color: #6B7280; font-size: 9pt; margin: 0 6pt; }' +
                'h2 { font-size: 14pt; color: #fff; background: linear-gradient(135deg, #6366F1, #818CF8); padding: 6pt 12pt; margin: 16pt 0 8pt 0; border-radius: 4pt; }' +
                'h2 .collapse-icon { display: none; }' +
                'h3 { font-size: 11.5pt; color: #3730A3; margin: 12pt 0 6pt 0; padding-left: 8pt; border-left: 3pt solid #818CF8; }' +
                'table { width: 100%; border-collapse: collapse; margin: 6pt 0 10pt 0; font-size: 9.5pt; }' +
                'th { background: #6366F1; color: #fff; padding: 5pt 8pt; text-align: left; font-size: 9pt; font-weight: 700; border: 0.5pt solid #4F46E5; }' +
                'td { padding: 4pt 8pt; border: 0.5pt solid #D1D5DB; vertical-align: top; }' +
                'tr:nth-child(even) td { background: #F8FAFC; }' +
                '.status-badge { display: inline-block; padding: 1.5pt 7pt; border-radius: 8pt; font-size: 8.5pt; font-weight: 700; color: #fff; }' +
                '.status-ok { background: #22C55E; }' +
                '.status-warning { background: #F59E0B; }' +
                '.status-critical { background: #EF4444; }' +
                '.status-info { background: #3B82F6; }' +
                '.health-gauge { text-align: center; margin: 8pt 0; }' +
                '.health-gauge .center .score { font-size: 24pt; font-weight: 800; }' +
                '.health-gauge .center .label { font-size: 9pt; color: #6B7280; }' +
                '.code-block { background: #F8FAFC; border: 0.5pt solid #E5E7EB; border-radius: 4pt; padding: 8pt; margin: 6pt 0; font-family: "Consolas", "Courier New", monospace; font-size: 9pt; }' +
                '.code-block::before { display: none; }' +
                '.code-block h4 { font-size: 9pt; color: #6B7280; margin: 0 0 4pt 0; }' +
                'code { font-family: "Consolas", "Courier New", monospace; font-size: 9pt; background: #F3F4F6; padding: 1pt 4pt; border-radius: 2pt; }' +
                '.section { margin: 0 0 12pt 0; padding: 0; border: none; }' +
                '.section-body { display: block !important; }' +
                '.tab-content { display: block !important; }' +
                '.nav-tabs { display: none; }' +
                '.export-bar, .loading-overlay, .cyber-grid, .particles, .back-to-top, .search-box { display: none !important; }' +
                '.fade-in { animation: none !important; opacity: 1 !important; }' +
                '</style>';

            var header =
                '<html xmlns:o="urn:schemas-microsoft-com:office:office" ' +
                'xmlns:w="urn:schemas-microsoft-com:office:word" ' +
                'xmlns="http://www.w3.org/TR/REC-html40">' +
                '<head><meta charset="utf-8"><title>Linux巡检报告</title>' +
                '<!--[if gte mso 9]><xml><w:WordDocument><w:View>Print</w:View>' +
                '<w:Zoom>100</w:Zoom><w:DoNotOptimizeForBrowser/></w:WordDocument></xml><![endif]-->' +
                wordCSS + '</head><body>';
            var footer = '</body></html>';

            var content = header + clone.innerHTML + footer;
            var blob = new Blob(['\ufeff' + content], { type: 'application/msword' });
            var url = URL.createObjectURL(blob);
            var link = document.createElement('a');
            link.href = url;
            link.download = filename;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            setTimeout(function() { URL.revokeObjectURL(url); }, 100);
        }

        function createParticles() {
            var container = document.getElementById('particles');
            for (var i = 0; i < 50; i++) {
                var p = document.createElement('div');
                p.className = 'particle';
                p.style.left = Math.random() * 100 + 'vw';
                p.style.animationDelay = Math.random() * 15 + 's';
                p.style.animationDuration = (15 + Math.random() * 10) + 's';
                container.appendChild(p);
            }
        }

        function setupTabs() {
            document.querySelectorAll('.nav-tabs').forEach(function(tabGroup) {
                var parent = tabGroup.parentElement;
                tabGroup.querySelectorAll('.nav-tab').forEach(function(tab) {
                    tab.addEventListener('click', function() {
                        var targetTab = this.getAttribute('data-tab');
                        tabGroup.querySelectorAll('.nav-tab').forEach(function(t) { t.classList.remove('active'); });
                        parent.querySelectorAll('.tab-content').forEach(function(c) { c.classList.remove('active'); });
                        this.classList.add('active');
                        var target = document.getElementById(targetTab + 'Tab');
                        if (target) target.classList.add('active');
                    });
                });
            });
        }

        function setupAnimations() {
            var observer = new IntersectionObserver(function(entries) {
                entries.forEach(function(entry) { if (entry.isIntersecting) entry.target.style.animationPlayState = 'running'; });
            }, { threshold: 0.1 });
            document.querySelectorAll('.fade-in').forEach(function(el) { observer.observe(el); });
        }

        function animateCircularProgress() {
            document.querySelectorAll('.circular-progress .fill').forEach(function(circle) {
                var offset = circle.getAttribute('data-offset');
                setTimeout(function() { circle.style.strokeDashoffset = offset; }, 300);
            });
        }

        function animateHealthScore() {
            var fill = document.getElementById('healthFill');
            var scoreEl = document.getElementById('healthScore');
            if (!fill || !scoreEl) return;
            var offset = fill.getAttribute('data-offset');
            setTimeout(function() { fill.style.strokeDashoffset = offset; }, 300);
            var current = 0;
            var interval = setInterval(function() {
                if (current >= HEALTH_SCORE_TARGET) { current = HEALTH_SCORE_TARGET; clearInterval(interval); }
                scoreEl.textContent = current;
                current += Math.ceil(HEALTH_SCORE_TARGET / 40);
            }, 30);
        }

        function filterTable(input, tableId) {
            var filter = input.value.toLowerCase();
            var table = document.getElementById(tableId);
            if (!table) return;
            table.querySelectorAll('tr').forEach(function(row, index) {
                if (index === 0) return;
                row.style.display = row.textContent.toLowerCase().indexOf(filter) > -1 ? '' : 'none';
            });
        }

        function toggleSection(header) {
            var section = header.closest('.section');
            if (section) section.classList.toggle('collapsed');
        }

        function setupCollapsibleSubs() {
            document.querySelectorAll('.section h3').forEach(function(h3) {
                h3.addEventListener('click', function() {
                    this.classList.toggle('sub-collapsed');
                    var next = this.nextElementSibling;
                    while (next && next.tagName !== 'H3') {
                        next.style.display = this.classList.contains('sub-collapsed') ? 'none' : '';
                        next = next.nextElementSibling;
                    }
                });
            });
        }

        function setupClickEffects() {
            document.querySelectorAll('.stat-card').forEach(function(card) {
                card.addEventListener('click', function() {
                    this.style.transform = 'scale(0.98)';
                    var self = this;
                    setTimeout(function() { self.style.transform = ''; }, 150);
                });
            });
        }

        var HEALTH_SCORE_TARGET = ${HEALTH_SCORE};

        document.addEventListener('DOMContentLoaded', function() {
            initThemeSwitcher();
            createParticles();
            buildSideNav();
            setupTabs();
            setupAnimations();
            setupScrollSpy();
            setupBackToTop();
            setupClickEffects();
            setupCollapsibleSubs();
            setTimeout(function() { animateCircularProgress(); animateHealthScore(); }, 200);
            setTimeout(hideLoading, 400);
        });

        window.addEventListener('beforeprint', function() {
            document.querySelectorAll('.stat-card').forEach(function(card) { card.style.transform = 'none'; });
            document.querySelectorAll('.section').forEach(function(s) { s.classList.remove('collapsed'); });
            document.querySelectorAll('.section h3.sub-collapsed').forEach(function(h3) {
                h3.classList.remove('sub-collapsed');
                var next = h3.nextElementSibling;
                while (next && next.tagName !== 'H3') { next.style.display = ''; next = next.nextElementSibling; }
            });
            document.querySelectorAll('.tab-content').forEach(function(t) { t.classList.add('active'); });
        });
    </script>
</body>
</html>
EOF

# ------------------------------------------------------------
# 完成
# ------------------------------------------------------------
echo -e "${GREEN}[4/4] Linux 系统巡检完成 (v11)${NC}"
echo -e "${CYAN}报告路径: ${YELLOW}$HTML_REPORT${NC}"
echo -e "${BLUE}报告特性:${NC}"
echo -e "${GREEN}   ✓ 多主题切换 (13种预设配色 + 自定义颜色选择器)${NC}"
echo -e "${GREEN}   ✓ 主题偏好自动保存${NC}"
echo -e "${GREEN}   ✓ 资源使用率可视化 (CPU / 内存 / 磁盘)${NC}"
echo -e "${GREEN}   ✓ 系统健康评分${NC}"
echo -e "${GREEN}   ✓ 侧边栏导航与滚动定位${NC}"
echo -e "${GREEN}   ✓ 表格搜索与筛选${NC}"
echo -e "${GREEN}   ✓ 章节折叠展开${NC}"
echo -e "${GREEN}   ✓ 返回顶部快捷按钮${NC}"
echo -e "${GREEN}   ✓ 加载动画效果${NC}"
echo -e "${GREEN}   ✓ 导出 Word 报告 (表格化展示)${NC}"
echo -e "${GREEN}   ✓ 打印优化样式${NC}"
echo -e "${GREEN}   ✓ 防火墙状态检测 (UFW / Firewalld / iptables)${NC}"
if [ "$DOCKER_AVAILABLE" = "1" ]; then
    echo -e "${GREEN}   ✓ Docker 容器与资源监控${NC}"
fi
if [ "$SYSTEMCTL_AVAILABLE" = "1" ]; then
    echo -e "${GREEN}   ✓ 系统服务状态监控${NC}"
fi
echo -e "${GREEN}   ✓ 网络接口与监听端口${NC}"
echo -e "${GREEN}   ✓ 安全审计 (登录用户 / 登录历史 / 错误日志)${NC}"
echo -e "${GREEN}   ✓ 移动端响应式适配${NC}"

if command -v xdg-open >/dev/null 2>&1; then
    echo -e "${ORANGE}正在浏览器中打开报告...${NC}"
    xdg-open "$HTML_REPORT" 2>/dev/null &
elif command -v open >/dev/null 2>&1; then
    echo -e "${ORANGE}正在浏览器中打开报告...${NC}"
    open "$HTML_REPORT" 2>/dev/null &
fi
