#!/bin/bash
# k2.sh
# K2 BBR + TCP 网络优化脚本（最终稳定版）
# 适用于 Debian / Ubuntu / CentOS

set -e

echo "========================================"
echo " K2 Network Optimizer (bbr Only)"
echo "========================================"

# 必须 root
if [ "$(id -u)" != "0" ]; then
    echo "请使用 root 权限运行"
    exit 1
fi

##########################
# 0. 备份并清空 sysctl.conf
##########################
echo "[0/4] 备份并清空 /etc/sysctl.conf ..."

SYSCTL_FILE="/etc/sysctl.conf"
BACKUP_FILE="/etc/sysctl.conf.bak_$(date +%F_%H%M%S)"

if [ -f "$SYSCTL_FILE" ]; then
    cp "$SYSCTL_FILE" "$BACKUP_FILE"
    echo "已备份 $SYSCTL_FILE → $BACKUP_FILE"
    > "$SYSCTL_FILE"
fi

##########################
# 1. 加载 BBR 模块
##########################
echo "[1/4] 检测 BBR 模块..."

if ! modinfo tcp_bbr >/dev/null 2>&1; then
    echo "⚠️ 系统不支持 tcp_bbr，退出脚本"
    exit 1
fi

modprobe tcp_bbr 2>/dev/null || true

mkdir -p /etc/modules-load.d
echo "tcp_bbr" > /etc/modules-load.d/bbr.conf

##########################
# 2. 写入 sysctl 优化参数
##########################
echo "[2/4] 写入 sysctl 优化参数..."

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
net.ipv4.tcp_rfc1337 = 0

net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_fin_timeout = 15

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

chmod 644 "$SYSCTL_CONF"

##########################
# 3. 应用 sysctl 参数
##########################
echo "[3/4] 应用 sysctl 参数..."

sysctl -p >/dev/null 2>&1
sysctl --system >/dev/null

##########################
# 4. 检查参数生效
##########################
echo "[4/4] 检查关键参数..."

check_param() {
    local key=$1
    local expected=$2
    local actual

    actual=$(sysctl -n "$key" 2>/dev/null || echo "N/A")

    # 清理多余空格/tab
    actual=$(echo "$actual" | xargs)
    expected=$(echo "$expected" | xargs)

    if [ "$actual" = "$expected" ]; then
        echo "$key = $actual ✔"
    else
        echo "$key = $actual ✘ (期望 $expected)"
    fi
}

PARAMS=(
"fs.file-max 6815744"

"net.ipv4.tcp_no_metrics_save 1"
"net.ipv4.tcp_ecn 0"
"net.ipv4.tcp_frto 0"
"net.ipv4.tcp_mtu_probing 0"
"net.ipv4.tcp_rfc1337 0"

"net.ipv4.tcp_tw_reuse 1"
"net.ipv4.tcp_timestamps 1"
"net.ipv4.tcp_fin_timeout 15"

"net.ipv4.tcp_sack 1"
"net.ipv4.tcp_fack 1"
"net.ipv4.tcp_window_scaling 1"
"net.ipv4.tcp_adv_win_scale 1"
"net.ipv4.tcp_moderate_rcvbuf 1"

"net.core.rmem_max 67108864"
"net.core.wmem_max 67108864"

"net.ipv4.tcp_rmem 4096 87380 67108864"
"net.ipv4.tcp_wmem 4096 65536 67108864"

"net.ipv4.udp_rmem_min 8192"
"net.ipv4.udp_wmem_min 8192"

"net.ipv4.ip_forward 1"
"net.ipv4.conf.all.route_localnet 1"
"net.ipv4.conf.all.forwarding 1"
"net.ipv4.conf.default.forwarding 1"

"net.ipv6.conf.all.forwarding 1"
"net.ipv6.conf.default.forwarding 1"

"net.core.default_qdisc fq"
"net.ipv4.tcp_congestion_control bbr"
)

for p in "${PARAMS[@]}"; do
    key=$(echo $p | awk '{print $1}')
    val=$(echo $p | cut -d' ' -f2-)
    check_param "$key" "$val"
done

echo ""
echo "=============================="
echo " 优化完成 ✅"
echo " 当前使用拥塞控制: bbr"
echo " 建议重启一次服务器以验证持久化效果"
echo "=============================="
