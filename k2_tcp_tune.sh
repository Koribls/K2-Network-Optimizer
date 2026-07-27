#!/usr/bin/env bash
# K2 CLOUD TCP Kernel Tuning Script
# Copyright (c) K2 CLOUD. All rights reserved.
# Author: K2 CLOUD
# Email: Kfcmature@gmail.com
# Target: Debian 12/13

set -euo pipefail

K2_TUNE_FILE="/etc/sysctl.d/99-k2-tcp-tune.conf"
SYSCTL_CONF="/etc/sysctl.conf"
SYSCTL_DIR="/etc/sysctl.d"
BACKED_UP_FILES=()
VERIFY_FAILED=0
VERIFY_UNSUPPORTED=0

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    PURPLE='\033[0;35m'
    GRAY='\033[0;90m'
    DIM='\033[2m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    GREEN=''
    YELLOW=''
    RED=''
    BLUE=''
    CYAN=''
    PURPLE=''
    GRAY=''
    DIM=''
    BOLD=''
    NC=''
fi
REPORT_LABEL_WIDTH=32

print_green() { printf "%b\n" "${GREEN}${BOLD}  ✓${NC} ${GREEN}$*${NC}"; }
print_yellow() { printf "%b\n" "${YELLOW}${BOLD}  !${NC} ${YELLOW}$*${NC}"; }
print_red() { printf "%b\n" "${RED}${BOLD}  ×${NC} ${RED}$*${NC}"; }
print_blue() { printf "%b\n" "${BLUE}${BOLD}  i${NC} ${BLUE}$*${NC}"; }

print_section() {
    printf "\n%b\n" "${DIM}──────────────────────────────────────────────────────────────${NC}"
    printf "%b\n" "${CYAN}${BOLD}  $*${NC}"
}

print_menu_item() {
    local color="$1"
    local option="$2"
    local title="$3"
    local detail="$4"

    printf "%b\n" "${color}${BOLD}  [${option}]${NC} ${color}${title}${NC}"
    printf "%b\n" "${DIM}      ${detail}${NC}"
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        print_red "错误：请在 root 环境下运行本脚本。"
        exit 1
    fi
}

check_debian_version() {
    if [[ ! -r /etc/os-release ]]; then
        print_yellow "警告：无法读取 /etc/os-release，跳过 Debian 版本检测。"
        return
    fi

    . /etc/os-release
    if [[ "${ID:-}" != "debian" ]]; then
        print_yellow "警告：当前系统不是 Debian，脚本目标系统为 Debian 12/13。"
        return
    fi

    case "${VERSION_ID:-}" in
        12|13|12.*|13.*)
            print_green "系统检测通过：Debian ${VERSION_ID}"
            ;;
        *)
            print_yellow "警告：当前 Debian 版本为 ${VERSION_ID:-unknown}，脚本目标系统为 Debian 12/13。"
            ;;
    esac
}

has_existing_backups() {
    [[ -e "${SYSCTL_CONF}.bak" ]] && return 0
    compgen -G "${SYSCTL_DIR}/*.conf.bak" > /dev/null && return 0
    return 1
}

backup_file() {
    local src="$1"
    local dst="${src}.bak"

    if [[ -e "${dst}" ]]; then
        print_red "备份目标已存在：${dst}"
        exit 1
    fi

    mv -n -- "${src}" "${dst}"

    if [[ -e "${src}" || ! -e "${dst}" ]]; then
        print_red "备份失败，可能目标已存在：${src} -> ${dst}"
        exit 1
    fi

    BACKED_UP_FILES+=("${dst}")
    print_green "已备份：${src} -> ${dst}"
}

rollback_backups_created_this_run() {
    local idx backup target
    for (( idx=${#BACKED_UP_FILES[@]} - 1; idx >= 0; idx-- )); do
        backup="${BACKED_UP_FILES[idx]}"
        target="${backup%.bak}"
        if [[ -e "${backup}" && ! -e "${target}" ]]; then
            mv -n -- "${backup}" "${target}"
            print_yellow "已回滚备份：${backup} -> ${target}"
        fi
    done
}

restore_file() {
    local backup="$1"
    local target="${backup%.bak}"

    if [[ -e "${target}" ]]; then
        print_red "恢复目标已存在，已跳过：${target}"
        print_yellow "请手动检查后再决定是否覆盖：${backup}"
        return 1
    fi

    mv -n -- "${backup}" "${target}"

    if [[ -e "${backup}" || ! -e "${target}" ]]; then
        print_red "恢复失败：${backup} -> ${target}"
        return 1
    fi

    print_green "已恢复：${backup} -> ${target}"
}

backup_existing_sysctl_files() {
    if has_existing_backups; then
        print_red "检测到已有 .bak 备份文件。"
        print_yellow "为避免覆盖原始备份，请先运行选项 2 恢复备份，或运行选项 3 删除当前调优文件后手动处理备份。"
        exit 1
    fi

    local conf_files=()
    local file
    for file in "${SYSCTL_DIR}"/*.conf; do
        [[ -e "${file}" ]] || continue
        conf_files+=("${file}")
    done

    if (( ${#conf_files[@]} == 0 )); then
        print_yellow "未发现 ${SYSCTL_DIR}/*.conf，跳过备份。"
    else
        for file in "${conf_files[@]}"; do
            backup_file "${file}"
        done
    fi

    if [[ -f "${SYSCTL_CONF}" ]]; then
        backup_file "${SYSCTL_CONF}"
    else
        print_yellow "未发现 ${SYSCTL_CONF}，跳过备份。"
    fi
}

write_tuning_file() {
    local tmp_file="${K2_TUNE_FILE}.tmp.$$"

    if ! cat > "${tmp_file}" <<'SYSCTL'
# K2 CLOUD TCP Kernel Tuning Parameters
# Copyright (c) K2 CLOUD. All rights reserved.
# Author: K2 CLOUD
# Email: Kfcmature@gmail.com
# Target: Debian 12/13

net.core.default_qdisc = fq
net.core.rmem_max = 268435456
net.core.wmem_max = 268435456
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.optmem_max = 65536
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 32768

net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_rmem = 4096 262144 268435456
net.ipv4.tcp_wmem = 4096 262144 268435456
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_no_metrics_save = 0
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
SYSCTL
    then
        rm -f -- "${tmp_file}"
        return 1
    fi

    if ! mv -f -- "${tmp_file}" "${K2_TUNE_FILE}"; then
        rm -f -- "${tmp_file}"
        return 1
    fi

    print_green "已写入：${K2_TUNE_FILE}"
}

get_sysctl_value() {
    local key="$1"
    sysctl -n "${key}" 2>/dev/null || true
}

normalize_sysctl_value() {
    local value="$1"
    local parts=()
    read -r -a parts <<< "${value}"
    printf "%s" "${parts[*]}"
}

check_one_param() {
    local key="$1"
    local expected="$2"
    local current
    current="$(get_sysctl_value "${key}")"

    if [[ -z "${current}" ]]; then
        print_yellow "${key} 不存在或当前内核不支持，目标值：${expected}"
        return 2
    fi

    local normalized_current normalized_expected
    normalized_current="$(normalize_sysctl_value "${current}")"
    normalized_expected="$(normalize_sysctl_value "${expected}")"

    if [[ "${normalized_current}" == "${normalized_expected}" ]]; then
        print_green "${key} = ${current}"
        return 0
    else
        print_red "${key} 当前值：${current}，目标值：${expected}"
        return 1
    fi
}

verify_one_param() {
    local status=0

    check_one_param "$@" || status=$?
    case "${status}" in
        1) (( VERIFY_FAILED += 1 )) ;;
        2) (( VERIFY_UNSUPPORTED += 1 )) ;;
    esac
}

verify_tuning() {
    VERIFY_FAILED=0
    VERIFY_UNSUPPORTED=0
    print_section "验证内核参数"

    verify_one_param "net.core.default_qdisc" "fq"
    verify_one_param "net.core.rmem_max" "268435456"
    verify_one_param "net.core.wmem_max" "268435456"
    verify_one_param "net.core.rmem_default" "262144"
    verify_one_param "net.core.wmem_default" "262144"
    verify_one_param "net.core.optmem_max" "65536"
    verify_one_param "net.core.somaxconn" "65535"
    verify_one_param "net.core.netdev_max_backlog" "32768"
    verify_one_param "net.ipv4.tcp_congestion_control" "bbr"
    verify_one_param "net.ipv4.tcp_rmem" "4096 262144 268435456"
    verify_one_param "net.ipv4.tcp_wmem" "4096 262144 268435456"
    verify_one_param "net.ipv4.tcp_moderate_rcvbuf" "1"
    verify_one_param "net.ipv4.tcp_max_syn_backlog" "65535"
    verify_one_param "net.ipv4.tcp_max_tw_buckets" "262144"
    verify_one_param "net.ipv4.tcp_fin_timeout" "30"
    verify_one_param "net.ipv4.tcp_keepalive_time" "600"
    verify_one_param "net.ipv4.tcp_keepalive_intvl" "30"
    verify_one_param "net.ipv4.tcp_keepalive_probes" "5"
    verify_one_param "net.ipv4.tcp_fastopen" "3"
    verify_one_param "net.ipv4.tcp_mtu_probing" "1"
    verify_one_param "net.ipv4.tcp_slow_start_after_idle" "0"
    verify_one_param "net.ipv4.tcp_no_metrics_save" "0"
    verify_one_param "net.ipv4.tcp_window_scaling" "1"
    verify_one_param "net.ipv4.tcp_sack" "1"
    verify_one_param "net.ipv4.tcp_timestamps" "1"
    verify_one_param "net.ipv4.ip_local_port_range" "1024 65535"
    verify_one_param "net.ipv4.ip_forward" "1"
    verify_one_param "net.ipv6.conf.all.forwarding" "1"
    verify_one_param "net.ipv6.conf.default.forwarding" "1"

    if (( VERIFY_FAILED == 0 && VERIFY_UNSUPPORTED == 0 )); then
        print_green "TCP 调优参数已全部应用并验证成功。"
        return 0
    fi

    print_red "TCP 调优未完全成功：${VERIFY_FAILED} 项不匹配，${VERIFY_UNSUPPORTED} 项不支持。"
    return 1
}

check_bbr_available() {
    local available
    available="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"

    if [[ " ${available} " != *" bbr "* ]]; then
        print_yellow "警告：当前内核可用拥塞控制算法：${available:-unknown}"
        print_yellow "如果不包含 bbr，net.ipv4.tcp_congestion_control = bbr 将无法应用。"
    fi
}

command_exists() {
    command -v "$1" > /dev/null 2>&1
}

report_item() {
    local label="$1"
    local value="$2"
    local label_width padding

    label_width="$(printf '%s\n' "${label}" | LC_ALL=C.UTF-8 wc -L | tr -d '[:space:]')"
    if [[ ! "${label_width}" =~ ^[0-9]+$ ]]; then
        label_width=0
    fi

    padding=$(( REPORT_LABEL_WIDTH - label_width ))
    if (( padding < 1 )); then
        padding=1
    fi

    printf "  %b%s%*s%b %b\n" "${GRAY}" "${label}" "${padding}" "" "${NC}" "${value}"
}

get_default_interface() {
    if ! command_exists ip; then
        return
    fi

    ip -o route show default 2>/dev/null | awk '
        NR == 1 {
            for (i = 1; i <= NF; i++) {
                if ($i == "dev") {
                    print $(i + 1)
                    exit
                }
            }
        }
    '
}

get_interface_stat() {
    local interface="$1"
    local stat="$2"
    local path="/sys/class/net/${interface}/statistics/${stat}"

    if [[ -r "${path}" ]]; then
        cat "${path}"
    else
        printf "未知"
    fi
}

get_tcp_stat() {
    local key="$1"

    awk -v target="${key}" '
        /^Tcp:/ {
            count++
            if (count == 1) {
                for (i = 1; i <= NF; i++) {
                    header[i] = $i
                }
                next
            }
            if (count == 2) {
                for (i = 1; i <= NF; i++) {
                    if (header[i] == target) {
                        print $i
                        exit
                    }
                }
            }
        }
    ' /proc/net/snmp 2>/dev/null || true
}

show_environment_report() {
    local os_name kernel_version cpu_count mem_kib mem_display
    local bbr_available qdisc congestion_control rmem_max wmem_max rmem_default wmem_default tcp_rmem tcp_wmem
    local interface link_speed rx_queue_count queue
    local rx_errors tx_errors rx_dropped tx_dropped tcp_retrans tcp_out_segs retrans_ratio total_drops

    print_section "运行环境检测（只读）"
    report_item "检测模式" "不修改任何系统配置"

    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        os_name="${PRETTY_NAME:-${ID:-unknown} ${VERSION_ID:-}}"
    else
        os_name="未知"
    fi
    kernel_version="$(uname -r 2>/dev/null || printf "未知")"
    cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
    cpu_count="${cpu_count:-未知}"
    mem_kib="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo 2>/dev/null || true)"
    if [[ "${mem_kib}" =~ ^[0-9]+$ ]]; then
        mem_display="$(( mem_kib / 1024 )) MiB"
    else
        mem_kib=0
        mem_display="未知"
    fi

    report_item "系统" "${os_name}"
    report_item "内核" "${kernel_version}"
    report_item "CPU 逻辑核心" "${cpu_count}"
    report_item "物理内存" "${mem_display}"

    print_section "TCP 能力与缓冲"
    bbr_available="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
    qdisc="$(get_sysctl_value "net.core.default_qdisc")"
    congestion_control="$(get_sysctl_value "net.ipv4.tcp_congestion_control")"
    rmem_max="$(get_sysctl_value "net.core.rmem_max")"
    wmem_max="$(get_sysctl_value "net.core.wmem_max")"
    rmem_default="$(get_sysctl_value "net.core.rmem_default")"
    wmem_default="$(get_sysctl_value "net.core.wmem_default")"
    tcp_rmem="$(get_sysctl_value "net.ipv4.tcp_rmem")"
    tcp_wmem="$(get_sysctl_value "net.ipv4.tcp_wmem")"

    if [[ " ${bbr_available} " == *" bbr "* ]]; then
        report_item "BBR 支持" "${GREEN}已支持${NC}"
    else
        report_item "BBR 支持" "${RED}未检测到${NC}"
    fi
    if [[ "${qdisc}" == "fq" ]]; then
        report_item "默认队列规则" "${GREEN}fq${NC}"
    else
        report_item "默认队列规则" "${YELLOW}${qdisc:-未知}${NC}"
    fi
    report_item "当前拥塞控制" "${congestion_control:-未知}"
    report_item "TCP 接收缓冲（最小/默认/最大）" "${tcp_rmem:-未知} 字节"
    report_item "TCP 发送缓冲（最小/默认/最大）" "${tcp_wmem:-未知} 字节"
    report_item "核心接收缓冲（默认/最大）" "${rmem_default:-未知} / ${rmem_max:-未知} 字节"
    report_item "核心发送缓冲（默认/最大）" "${wmem_default:-未知} / ${wmem_max:-未知} 字节"

    print_section "网卡与连接健康度"
    interface="$(get_default_interface || true)"
    if [[ -z "${interface}" ]]; then
        report_item "默认出站网卡" "${YELLOW}未检测到${NC}"
    else
        link_speed="$(cat "/sys/class/net/${interface}/speed" 2>/dev/null || true)"
        if [[ "${link_speed}" =~ ^[0-9]+$ ]] && (( link_speed > 0 )); then
            link_speed="${link_speed} Mb/s"
        else
            link_speed="未知（虚拟网卡通常不报告速率）"
        fi

        rx_queue_count=0
        for queue in "/sys/class/net/${interface}/queues"/rx-*; do
            [[ -d "${queue}" ]] || continue
            (( rx_queue_count += 1 ))
        done

        rx_errors="$(get_interface_stat "${interface}" "rx_errors")"
        tx_errors="$(get_interface_stat "${interface}" "tx_errors")"
        rx_dropped="$(get_interface_stat "${interface}" "rx_dropped")"
        tx_dropped="$(get_interface_stat "${interface}" "tx_dropped")"
        report_item "默认出站网卡" "${interface}"
        report_item "链路速率" "${link_speed}"
        report_item "接收队列数" "${rx_queue_count}"
        report_item "网卡错误 / 丢包" "RX: ${rx_errors}/${rx_dropped}  TX: ${tx_errors}/${tx_dropped}"
    fi

    tcp_retrans="$(get_tcp_stat "RetransSegs")"
    tcp_out_segs="$(get_tcp_stat "OutSegs")"
    if [[ "${tcp_retrans}" =~ ^[0-9]+$ ]] && [[ "${tcp_out_segs}" =~ ^[0-9]+$ ]] && (( tcp_out_segs > 0 )); then
        retrans_ratio="$(awk -v retrans="${tcp_retrans}" -v out="${tcp_out_segs}" 'BEGIN { printf "%.3f%%", (retrans / out) * 100 }')"
    else
        retrans_ratio="未知"
    fi

    report_item "TCP 发出段（启动以来）" "${tcp_out_segs:-未知}"
    report_item "TCP 重传段（启动以来）" "${tcp_retrans:-未知}"
    report_item "累计重传比例" "${retrans_ratio}"
    report_item "统计说明" "请记录前后发出段与重传段，再用增量计算重传比例。"

    print_section "针对当前主机的建议"
    if [[ " ${bbr_available} " == *" bbr "* ]] && [[ "${qdisc}" == "fq" ]]; then
        print_green "BBR 与 fq 均可用，可保持当前组合。"
    else
        print_yellow "BBR 或 fq 未完全就绪；先解决该项，再评估吞吐与重传。"
    fi

    if (( mem_kib > 0 && mem_kib < 1048576 )); then
        print_yellow "内存低于 1 GiB：256 MiB 是单连接上限，不是固定分配；应限制高并发连接数。"
    fi

    if [[ "${cpu_count}" == "1" ]]; then
        print_yellow "单核主机容易被 softirq 限制；多线程速度可能先受 CPU 而非 TCP 参数限制。"
    fi

    if [[ "${interface:-}" != "" ]] && [[ "${rx_dropped}" =~ ^[0-9]+$ ]] && [[ "${tx_dropped}" =~ ^[0-9]+$ ]]; then
        total_drops=$(( rx_dropped + tx_dropped ))
        if (( total_drops > 0 )); then
            print_yellow "网卡自开机以来累计丢包 ${total_drops} 个；请在压测前后观察增量，不能仅凭累计值判断故障。"
        else
            print_green "未检测到网卡累计丢包。"
        fi
    fi

    print_blue "压测请分别记录单连接与多连接结果，并同时观察 CPU、重传与网卡丢包。"
}

apply_tuning() {
    print_section "应用 TCP 网络调优"
    check_debian_version
    check_bbr_available
    backup_existing_sysctl_files
    if ! write_tuning_file; then
        print_red "写入 ${K2_TUNE_FILE} 失败，正在回滚本次备份。"
        rollback_backups_created_this_run
        exit 1
    fi

    print_blue "正在执行 sysctl --system..."
    if ! sysctl --system; then
        print_yellow "警告：sysctl --system 返回非零状态，可能有参数不被当前内核支持。"
        print_yellow "继续逐项检查已成功应用的参数。"
    fi
    if ! verify_tuning; then
        print_red "TCP 调优应用结束，但校验未全部通过；请根据上方失败项检查内核支持情况。"
        return 1
    fi

    print_green "TCP 调优应用成功，所有目标参数均已生效。"
}

restore_backup_files() {
    local failed=0

    if [[ -f "${SYSCTL_CONF}.bak" ]]; then
        restore_file "${SYSCTL_CONF}.bak" || failed=1
    else
        print_yellow "未发现 ${SYSCTL_CONF}.bak，跳过恢复。"
    fi

    local backup_files=()
    local file
    for file in "${SYSCTL_DIR}"/*.conf.bak; do
        [[ -e "${file}" ]] || continue
        backup_files+=("${file}")
    done

    if (( ${#backup_files[@]} == 0 )); then
        print_yellow "未发现 ${SYSCTL_DIR}/*.conf.bak，跳过恢复。"
    fi

    for file in "${backup_files[@]}"; do
        restore_file "${file}" || failed=1
    done

    return "${failed}"
}

remove_k2_tune_file() {
    if [[ -f "${K2_TUNE_FILE}" ]]; then
        rm -f "${K2_TUNE_FILE}"
        print_green "已删除：${K2_TUNE_FILE}"
    else
        print_yellow "未发现：${K2_TUNE_FILE}"
    fi
}

restore_backup_and_apply() {
    print_section "恢复备份配置"
    remove_k2_tune_file
    if ! restore_backup_files; then
        print_red "恢复备份文件失败，已停止执行 sysctl --system。"
        exit 1
    fi
    print_blue "正在执行 sysctl --system..."
    sysctl --system
    print_green "备份参数已恢复并应用。"
}

remove_tune_file_only() {
    print_section "删除调优配置"
    remove_k2_tune_file
    print_yellow "未恢复 .bak 备份文件，也未执行 sysctl --system。"
    cat <<'MANUAL'
如需手动恢复，请根据实际存在的备份文件执行：
  mv -n -- /etc/sysctl.conf.bak /etc/sysctl.conf
  mv -n -- /etc/sysctl.d/xxx.conf.bak /etc/sysctl.d/xxx.conf
  sysctl --system
MANUAL
}

show_menu() {
    printf "\n"
    printf "%b\n" "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf "%b\n" "${CYAN}${BOLD}  K2 CLOUD${NC}"
    printf "%b\n" "${BOLD}  TCP PERFORMANCE TUNING CONSOLE${NC}"
    printf "%b\n" "${GRAY}  Debian 12 / 13  ·  BBR + FQ  ·  Adaptive TCP Buffers${NC}"
    printf "%b\n" "${DIM}  Profile: 256 MiB per-connection ceiling · Root required${NC}"
    printf "%b\n" "${DIM}──────────────────────────────────────────────────────────────${NC}"
    printf "%b\n" "${GRAY}${BOLD}  操作菜单${NC}"
    print_menu_item "${GREEN}" "1" "应用并校验 TCP 调优参数" "创建备份、写入配置并逐项验证"
    print_menu_item "${YELLOW}" "2" "恢复原始 sysctl 配置" "删除调优文件，恢复备份并立即应用"
    print_menu_item "${PURPLE}" "3" "仅删除调优配置" "保留备份，供后续人工检查与恢复"
    print_menu_item "${CYAN}" "4" "运行环境检测与建议" "只读检查 CPU、内存、网卡、BBR 与重传"
    printf "%b\n" "${DIM}──────────────────────────────────────────────────────────────${NC}"
    printf "%b\n" "${GRAY}  安全提示：执行 [1] 前会备份现有 sysctl 配置。${NC}"
    printf "%b\n" "${RED}${BOLD}  [0]${NC}${RED}  退出控制台${NC}"
    printf "%b\n" "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf "%b" "${YELLOW}${BOLD}  请选择操作 [0-4]  ›  ${NC}"
}

main() {
    require_root
    show_menu
    read -r choice

    case "${choice}" in
        1) apply_tuning ;;
        2) restore_backup_and_apply ;;
        3) remove_tune_file_only ;;
        4) show_environment_report ;;
        0) print_blue "已退出。" ;;
        *) print_red "无效选项。"; exit 1 ;;
    esac
}

main "$@"
