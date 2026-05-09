#!/bin/bash
# k2.sh
# K2 BBR + TCP 网络优化脚本（安全稳定版）
# 自动备份 sysctl.conf，应用参数，并检测生效
# 适用于 Debian / Ubuntu / CentOS

set -e

echo "========================================"
echo " K2 Network Optimizer (Stable Edition)"
echo " BBR + TCP Optimization"
echo "========================================"

# 必须 root
if [ "$(id -u)" != "0" ]; then
    echo "请使用 root 权限运行"
    exit 1
fi

echo "[0/6] 备份并清空 /etc/sysctl.conf ..."
SYSCTL_FILE="/etc/sysctl.conf"
BACKUP_FILE="/etc/sysctl.conf.bak_$(date +%F_%H%M%S)"
if [ -f "$SYSCTL_FILE" ]; then
    cp "$SYSCTL_FILE" "$BACKUP_FILE"
    echo "已备份 $SYSCTL_FILE → $BACKUP_FILE"
    > "$SYSCTL_FILE"
fi

echo "[1/6] 加载 BBR 模块..."
modprobe tcp_bbr 2>/dev/null || true
mkdir -p /etc/modules-load.d
echo "tcp_bbr" > /etc/modules-load.d/bbr.conf

echo "[2/6] 写入 sysctl 优化参数..."
SYSCTL_CONF="/etc/sysctl.d/99-k2-bbr.conf"
cat > "$SYSCTL_CONF" << 'EOF'
# =========================
# K2 TCP / BBR Optimizer
# =========================

fs.file-max = 6815744

net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_ecn = 0
net.ipv4.tcp_frto = 0
net.ipv4.tcp_mtu_probing = 0
net.ipv4.tcp_slow_start_after_idle = 0

net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_rfc1337 = 0

net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_adv_win_scale = 1
net.ipv4.tcp_moderate_rcvbuf = 1

net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

net.ipv4.ip_forward = 1
net.ipv4.conf.all.route_localnet = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1

net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

echo "[3/6] 应用 sysctl 配置..."
sysctl -p >/dev/null
sysctl --system >/dev/null 2>&1

echo "[4/6] 强制确保 BBR 生效..."
sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 || true
sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || true

echo "[5/6] 检查关键参数是否生效..."
check_param() {
    local key=$1
    local expected=$2
    local actual
    actual=$(sysctl -n "$key" 2>/dev/null || echo "N/A")

    # 支持多值参数比较（以空格分割）
    IFS=' ' read -r -a arr_expected <<< "$expected"
    IFS=' ' read -r -a arr_actual <<< "$actual"

    if [ "${#arr_expected[@]}" -ne "${#arr_actual[@]}" ]; then
        echo -e "$key = $actual ✘ (期望 $expected)"
        return
    fi

    for i in "${!arr_expected[@]}"; do
        if [ "${arr_expected[$i]}" != "${arr_actual[$i]}" ]; then
            echo -e "$key = $actual ✘ (期望 $expected)"
            return
        fi
    done
    echo -e "$key = $actual ✔"
}

PARAMS=(
"net.ipv4.tcp_congestion_control bbr"
"net.core.default_qdisc fq"
"net.ipv4.tcp_no_metrics_save 1"
"net.ipv4.tcp_ecn 0"
"net.ipv4.tcp_fin_timeout 10"
"net.ipv4.tcp_tw_reuse 1"
"net.core.rmem_max 67108864"
"net.core.wmem_max 67108864"
"net.ipv4.tcp_rmem 4096 87380 67108864"
"net.ipv4.tcp_wmem 4096 65536 67108864"
"net.ipv4.ip_forward 1"
)

for p in "${PARAMS[@]}"; do
    key=$(echo $p | awk '{print $1}')
    val=$(echo $p | cut -d' ' -f2-)
    check_param "$key" "$val"
done

echo ""
echo "=============================="
echo " 优化完成"
echo " 建议重启一次服务器（可选）"
echo "=============================="
