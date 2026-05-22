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

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_green() { printf "%b\n" "${GREEN}$*${NC}"; }
print_yellow() { printf "%b\n" "${YELLOW}$*${NC}"; }
print_red() { printf "%b\n" "${RED}$*${NC}"; }
print_blue() { printf "%b\n" "${BLUE}$*${NC}"; }

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
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.optmem_max = 65536
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 250000

net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_rmem = 4096 1048576 268435456
net.ipv4.tcp_wmem = 4096 1048576 268435456
net.ipv4.tcp_mem = 786432 1048576 26777216
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_no_metrics_save = 1
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
        print_yellow "⚠️  ${key} 不存在或当前内核不支持，目标值：${expected}"
        return
    fi

    local normalized_current normalized_expected
    normalized_current="$(normalize_sysctl_value "${current}")"
    normalized_expected="$(normalize_sysctl_value "${expected}")"

    if [[ "${normalized_current}" == "${normalized_expected}" ]]; then
        print_green "✅️ ${key} = ${current}"
    else
        print_red "❌ ${key} 当前值：${current}，目标值：${expected}"
    fi
}

verify_tuning() {
    print_blue "正在检查调优参数应用结果..."

    check_one_param "net.core.default_qdisc" "fq"
    check_one_param "net.core.rmem_max" "268435456"
    check_one_param "net.core.wmem_max" "268435456"
    check_one_param "net.core.rmem_default" "1048576"
    check_one_param "net.core.wmem_default" "1048576"
    check_one_param "net.core.optmem_max" "65536"
    check_one_param "net.core.somaxconn" "65535"
    check_one_param "net.core.netdev_max_backlog" "250000"
    check_one_param "net.ipv4.tcp_congestion_control" "bbr"
    check_one_param "net.ipv4.tcp_rmem" "4096 1048576 268435456"
    check_one_param "net.ipv4.tcp_wmem" "4096 1048576 268435456"
    check_one_param "net.ipv4.tcp_mem" "786432 1048576 26777216"
    check_one_param "net.ipv4.tcp_max_syn_backlog" "65535"
    check_one_param "net.ipv4.tcp_max_tw_buckets" "2000000"
    check_one_param "net.ipv4.tcp_fin_timeout" "10"
    check_one_param "net.ipv4.tcp_keepalive_time" "600"
    check_one_param "net.ipv4.tcp_keepalive_intvl" "30"
    check_one_param "net.ipv4.tcp_keepalive_probes" "5"
    check_one_param "net.ipv4.tcp_fastopen" "3"
    check_one_param "net.ipv4.tcp_mtu_probing" "1"
    check_one_param "net.ipv4.tcp_slow_start_after_idle" "0"
    check_one_param "net.ipv4.tcp_no_metrics_save" "1"
    check_one_param "net.ipv4.tcp_window_scaling" "1"
    check_one_param "net.ipv4.tcp_sack" "1"
    check_one_param "net.ipv4.tcp_timestamps" "1"
    check_one_param "net.ipv4.ip_local_port_range" "1024 65535"
    check_one_param "net.ipv4.ip_forward" "1"
    check_one_param "net.ipv6.conf.all.forwarding" "1"
    check_one_param "net.ipv6.conf.default.forwarding" "1"
}

check_bbr_available() {
    local available
    available="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"

    if [[ " ${available} " != *" bbr "* ]]; then
        print_yellow "警告：当前内核可用拥塞控制算法：${available:-unknown}"
        print_yellow "如果不包含 bbr，net.ipv4.tcp_congestion_control = bbr 将无法应用。"
    fi
}

apply_tuning() {
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
    verify_tuning
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
    cat <<'MENU'

========================================
 K2 CLOUD TCP Kernel Tuning Script
 Target: Debian 12/13
========================================
1) 一键运行调优参数并检查应用结果
2) 删除当前调优参数文件 | 恢复备份参数并应用
3) 删除当前调优参数文件 | 不恢复备份，用户手动恢复
0) 退出
MENU
    printf "请选择 [0-3]: "
}

main() {
    require_root
    show_menu
    read -r choice

    case "${choice}" in
        1) apply_tuning ;;
        2) restore_backup_and_apply ;;
        3) remove_tune_file_only ;;
        0) print_blue "已退出。" ;;
        *) print_red "无效选项。"; exit 1 ;;
    esac
}

main "$@"
