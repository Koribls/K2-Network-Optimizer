#!/bin/bash
# k2.sh
# BBR + TCP 网络优化脚本（安全稳定版）
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

echo "[1/4] 加载 BBR 模块..."

# 加载 BBR（忽略错误）
modprobe tcp_bbr 2>/dev/null || true

# 开机自动加载
mkdir -p /etc/modules-load.d
echo "tcp_bbr" > /etc/modules-load.d/bbr.conf

echo "[2/4] 写入 sysctl 优化参数..."

cat > /etc/sysctl.d/99-k2-bbr.conf << 'EOF'
# =========================
# K2 TCP / BBR Optimizer
# =========================

# 系统限制
fs.file-max = 6815744

# TCP 基础优化
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_ecn = 0
net.ipv4.tcp_frto = 0
net.ipv4.tcp_mtu_probing = 0
net.ipv4.tcp_slow_start_after_idle = 0

# TCP 连接优化
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_rfc1337 = 0

# TCP 行为优化
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_adv_win_scale = 1
net.ipv4.tcp_moderate_rcvbuf = 1

# Buffer 优化
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# 网络转发（代理/中转场景）
net.ipv4.ip_forward = 1
net.ipv4.conf.all.route_localnet = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1

# 队列 & 拥塞控制（关键）
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

echo "[3/4] 应用 sysctl 配置..."

# 统一加载所有 sysctl（推荐方式）
sysctl --system

echo "[4/4] 强制确保 BBR 生效..."

# 强制设置（防止部分系统未切换）
sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 || true
sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || true

echo ""
echo "=============================="
echo " 当前状态检查"
echo "=============================="

echo "拥塞控制:"
sysctl net.ipv4.tcp_congestion_control

echo "队列算法:"
sysctl net.core.default_qdisc

echo ""
echo "BBR模块:"
lsmod | grep tcp_bbr || echo "tcp_bbr 未显示（但可能已内建）"

echo ""
echo "=============================="
echo " 优化完成"
echo " 建议重启一次服务器（可选）"
echo "=============================="
