# K2 CLOUD TCP Kernel Tuning

面向 Debian 12 / 13 的交互式 TCP 内核调优脚本。

> 以 `fq + bbr` 和 TCP 自动缓冲为核心，在兼顾 1C1G 低配 VPS 稳定性的前提下，为单连接与多连接 TCP 传输提供一套克制、可验证、可恢复的通用基线。

---

## 项目概览

| 项目 | 当前状态 |
| --- | --- |
| 目标系统 | Debian 12 / Debian 13 |
| 运行权限 | root |
| 适用机器 | 约 1C1G ～ 8C8G |
| 适用带宽 | 约 1 Gbps ～ 10 Gbps |
| 核心组合 | `fq` + `bbr` |
| TCP 缓冲 | 4 KiB / 256 KiB / 256 MiB 自动调节 |
| 配置文件 | `/etc/sysctl.d/99-k2-tcp-tune.conf` |
| 主脚本 | `k2_tcp_tune.sh` |

本项目提供的是 Linux TCP 参数基线，不是带宽扩容工具。最终速度仍受云厂商限速、CPU 单核能力、虚拟网卡、offload、对端性能、RTT、丢包和公网路由影响。

## 核心特点

- 使用 `fq` 队列规则与 `bbr` 拥塞控制，提供发送 pacing 和现代拥塞控制能力。
- TCP 与核心收发缓冲支持自动调节，单连接最大上限为 256 MiB。
- 默认值保持 256 KiB，避免低内存主机和高并发连接产生过高初始内存占用。
- 保留 SACK、时间戳、窗口扩大、MTU 探测、TCP Fast Open 等 TCP 能力。
- 保留现有 IPv4 / IPv6 转发行为。
- 提供备份、恢复、仅删除配置和严格逐项校验。
- 提供完全只读的运行环境检测。
- TTY 中使用统一状态颜色；非 TTY 或设置 `NO_COLOR` 时自动输出纯文本。

> [!IMPORTANT]
> `sysctl` 无法突破云厂商、单核 CPU、网卡、对端或公网路径限制。请不要将本项目描述为可以保证跑满所有 1 Gbps / 10 Gbps 端口。

## 系统要求

- Debian 12 或 Debian 13
- root 权限
- 支持 BBR 的 Linux 内核
- Bash、`sysctl`、`iproute2` 等基础组件

脚本不会安装内核或软件包，也不会修改防火墙规则。

## 快速运行

### 克隆运行

请以 root 身份登录目标 VPS：

```bash
git clone https://github.com/Koribls/K2-Network-Optimizer.git
cd K2-Network-Optimizer
chmod +x k2_tcp_tune.sh
./k2_tcp_tune.sh
```

也可以直接使用 Bash：

```bash
bash k2_tcp_tune.sh
```

### 在线运行

确认已使用 root 身份登录目标 VPS，并已阅读下方的备份与配置影响后，再执行最新主分支脚本：

```bash
bash <(curl -sL https://raw.githubusercontent.com/Koribls/K2-Network-Optimizer/main/k2_tcp_tune.sh)
```

> [!WARNING]
> 在线执行会直接运行远程脚本。生产环境建议优先克隆仓库、审阅脚本内容，再在维护窗口内运行。

## 菜单功能

| 选项 | 名称 | 行为 |
| ---: | --- | --- |
| `1` | 应用并校验 TCP 调优参数 | 检查系统与 BBR，备份 sysctl，写入配置，执行 `sysctl --system`，逐项验证 |
| `2` | 恢复原始 sysctl 配置 | 删除 K2 配置，恢复 `.bak` 备份，并重新应用 sysctl |
| `3` | 仅删除调优配置 | 删除 K2 配置，保留备份；不恢复备份，也不重新应用 sysctl |
| `4` | 环境检测与建议 | 完全只读，检查 CPU、内存、BBR/fq、TCP 缓冲、网卡和重传统计 |
| `0` | 退出 | 不做任何修改 |

## 当前调优配置

菜单 `1` 当前写入并校验以下 17 项参数：

```ini
net.core.default_qdisc = fq

net.core.rmem_max = 268435456
net.core.wmem_max = 268435456
net.core.rmem_default = 262144
net.core.wmem_default = 262144

net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_rmem = 4096 262144 268435456
net.ipv4.tcp_wmem = 4096 262144 268435456
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1

net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
```

### 缓冲区策略

| 缓冲层级 | 最小值 | 默认值 | 最大值 |
| --- | ---: | ---: | ---: |
| TCP 接收缓冲 `tcp_rmem` | 4 KiB | 256 KiB | 256 MiB |
| TCP 发送缓冲 `tcp_wmem` | 4 KiB | 256 KiB | 256 MiB |
| 核心接收缓冲 | — | 256 KiB | 256 MiB |
| 核心发送缓冲 | — | 256 KiB | 256 MiB |

256 MiB 是单连接自动扩容上限，不是每条连接启动时的固定分配。`tcp_moderate_rcvbuf = 1` 允许内核根据实际带宽、RTT、收发压力和全局内存压力自动调整接收缓冲；窗口扩大保证高带宽时延积连接可以使用更大的 TCP 窗口。

项目不固定 `net.ipv4.tcp_mem`，由内核根据实际内存动态管理。

### 参数取舍

保留的能力：

- `fq + bbr`：现代 Linux TCP 吞吐基线。
- SACK、timestamps、window scaling：服务于丢包恢复、RTT 估计和高 BDP 连接。
- MTU probing：应对部分路径 MTU 黑洞，不强制 Jumbo Frame。
- TCP Fast Open：提供内核能力，但是否真正生效还取决于应用、对端和中间网络。
- IPv4 / IPv6 forwarding：保留项目原有转发语义。

不主动管理的参数：

- `net.core.netdev_max_backlog`、`net.core.optmem_max`、`somaxconn`；
- `tcp_max_syn_backlog`、`tcp_max_tw_buckets`、`tcp_fin_timeout`；
- keepalive 参数、端口范围和空闲慢启动参数；
- `tcp_tw_reuse`、已废弃的 `tcp_tw_recycle`；
- 固定 `tcp_mem`、busy polling、强制 Jumbo Frame；
- 未经实测依据的 `netdev_budget`、RPS/XPS、IRQ 或队列参数。

这些参数可能适合特定应用或连接生命周期管理，但不是本项目的通用 TCP 吞吐基线。

## 备份与恢复

> [!WARNING]
> 菜单 `1` 会将现有 `/etc/sysctl.conf` 和 `/etc/sysctl.d/*.conf` 重命名为对应的 `.bak` 文件，再写入 K2 配置。请确认自己有权限管理这些文件，并已理解现有 sysctl 配置的影响。

### 菜单 `1` 的备份流程

1. 检查对应 `.bak` 是否已存在。
2. 若发现已有备份，停止执行，避免覆盖原始备份。
3. 备份现有 sysctl 文件。
4. 写入 `/etc/sysctl.d/99-k2-tcp-tune.conf`。
5. 执行 `sysctl --system`。
6. 对所有目标参数逐项校验。

如果写入 K2 配置失败，脚本会尝试回滚本次创建的备份。

菜单 `2` 会删除 K2 配置、恢复 `.bak` 备份并重新应用 sysctl。菜单 `3` 只删除 K2 配置，不恢复备份，也不重新应用 sysctl。

## 环境检测

菜单 `4` 完全只读，不会修改 sysctl、网卡、路由或其他系统配置。它会展示：

- Debian 版本、内核版本、CPU 逻辑核心数和物理内存；
- BBR 可用性、当前拥塞控制和默认队列规则；
- TCP 接收/发送缓冲的最小、默认、最大值；
- 核心接收/发送缓冲的默认值和最大值；
- 默认出站网卡、链路速率和接收队列数量；
- 网卡 RX/TX 错误和丢包；
- TCP 发出段、重传段和累计重传比例。

TCP 和网卡统计是自开机累计值。分析某次业务时，应记录前后数值并使用增量：

```text
增量重传率 = (结束重传段 - 开始重传段)
           / (结束发出段 - 开始发出段)
```

累计比例不能直接代表某次业务的真实重传率。脚本也不会根据累计统计自动修改系统参数。

## 性能边界

目标机器约为 `1C1G` 到 `8C8G`，目标带宽约为 `1 Gbps` 到 `10 Gbps`。项目不按亚太、美西、欧洲硬编码不同 sysctl；实际路径的 RTT、丢包、运营商、对端和云厂商限制更重要。

- 1C1G 主机的多连接吞吐可能先受单核 softirq 或虚拟网卡能力限制。
- 多连接通常更容易利用 2C、4C、8C CPU，但仍受对端和路径限制。
- 10Gbps 单连接在高 RTT 下受带宽时延积限制；256 MiB 在约 10Gbps、200ms RTT 时已接近边界。
- TCP 参数不能降低物理传播 RTT，也不能替代 TLS、HTTP/2、HTTP/3、连接池或应用层优化。
- 没有统一、可复现的跨地区压测结果时，不应声称配置一定降低重传或一定提升吞吐。

## 验证与排障

每次修改脚本后至少执行：

```bash
bash -n k2_tcp_tune.sh
```

开发机不得执行菜单 `1`、`2`、`3`，因为这些选项会修改目标系统的 `/etc/sysctl*` 文件。

应用后，菜单 `1` 使用以下状态标识逐项报告：

| 标识 | 含义 |
| --- | --- |
| `✓` | 参数已正确应用 |
| `!` | 参数不存在或当前内核不支持 |
| `×` | 实际值与目标值不一致 |
| `i` | 流程信息 |

只有所有目标参数均匹配时，脚本才会显示应用成功并返回 `0`。排障时优先检查：

1. `net.ipv4.tcp_available_congestion_control` 是否包含 `bbr`；
2. 当前内核和云厂商容器/虚拟化限制是否允许对应 sysctl；
3. 是否存在需要保留的自定义 sysctl 配置；
4. CPU、网卡丢包、softirq、对端性能或公网路径是否先于 TCP 参数成为瓶颈。

## 免责声明

请先在非关键业务主机或维护窗口内验证。网络调优应结合真实业务流量、菜单 `4` 的只读统计和监控指标进行；本项目不对云厂商网络、跨运营商路径、对端系统或公网路由造成的带宽、延迟和丢包问题作保证。

## 联系方式

- K2 CLOUD
- Email: [Kfcmature@gmail.com](mailto:Kfcmature@gmail.com)

