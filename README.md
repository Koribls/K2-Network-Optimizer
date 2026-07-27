# K2 CLOUD TCP Kernel Tuning

面向 **Debian 12 / 13** 的交互式 TCP 内核调优脚本。它以 BBR + fq 为基础，在兼顾低配 VPS 稳定性的前提下，为单连接与多连接 TCP 吞吐提供高性能的通用基线。

> 适用场景：云服务器、VPS、需要长期运行 TCP 服务或进行跨地区网络传输的 Debian 主机。

## 特性

- 使用 `fq` 队列规则与 `bbr` 拥塞控制。
- TCP 收发缓冲可自动调节，**单连接最大上限为 256 MiB**。
- 保留 SACK、时间戳、窗口扩大、MTU 探测、TCP Fast Open 等现代 TCP 能力。
- 面向低配到高配 VPS：默认缓冲为 256 KiB，不会为每条连接固定分配 256 MiB。
- 提供安全备份、恢复、删除配置和逐项 sysctl 校验。
- 提供只读运行环境检测：CPU、内存、网卡队列、BBR/fq、缓冲区、网卡丢包与 TCP 重传统计。
- 提供专业化中文终端 UI；非交互日志或设置 `NO_COLOR` 时自动输出纯文本。

## 系统要求

- Debian 12 或 Debian 13
- root 权限
- 运行内核支持 BBR（Debian 官方内核通常已包含）
- Bash、`sysctl`、`iproute2` 等 Debian 基础组件

脚本不会安装内核、软件包或修改防火墙规则。

## 快速开始

以 root 身份登录目标 VPS 后执行：

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

## 菜单功能

| 选项 | 功能 | 说明 |
| --- | --- | --- |
| `1` | 应用并校验 TCP 调优参数 | 创建备份、写入 K2 配置、执行 `sysctl --system` 并逐项验证。只有全部目标参数匹配时才显示应用成功。 |
| `2` | 恢复原始 sysctl 配置 | 删除 K2 配置，恢复 `.bak` 备份，并重新应用 sysctl。 |
| `3` | 仅删除调优配置 | 删除 K2 配置文件，但保留备份供人工检查或恢复。 |
| `4` | 环境检测与建议 | 完全只读；展示系统、CPU、内存、TCP 缓冲、BBR/fq、网卡与重传统计。 |
| `0` | 退出 | 不做任何修改。 |

## 调优策略

### 拥塞控制与队列

```ini
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

`fq` 为 BBR 提供 pacing（发送节奏控制）支持；二者是现代 Linux TCP 吞吐优化的核心组合。

### 自适应 TCP 缓冲

```ini
net.core.rmem_max = 268435456
net.core.wmem_max = 268435456
net.core.rmem_default = 262144
net.core.wmem_default = 262144

net.ipv4.tcp_rmem = 4096 262144 268435456
net.ipv4.tcp_wmem = 4096 262144 268435456
net.ipv4.tcp_moderate_rcvbuf = 1
```

| 参数层级 | 最小值 | 默认值 | 最大值 |
| --- | ---: | ---: | ---: |
| TCP 接收缓冲 `tcp_rmem` | 4 KiB | 256 KiB | 256 MiB |
| TCP 发送缓冲 `tcp_wmem` | 4 KiB | 256 KiB | 256 MiB |
| 核心套接字缓冲 | — | 256 KiB | 256 MiB |

256 MiB 是**单连接自动扩容上限**，不是每条连接启动时占用的固定内存。内核会依据带宽、RTT、发送/接收压力和全局内存压力决定实际缓冲大小。

脚本刻意不固定 `net.ipv4.tcp_mem`，避免在 1 GiB VPS 上写入不合理的全局 TCP 内存阈值；该限制由内核根据实际内存动态处理。

### 其他关键项

- `net.ipv4.tcp_mtu_probing = 1`：应对部分路径 MTU 问题，避免盲目强制探测带来的性能损耗。
- `net.ipv4.tcp_sack = 1`、`net.ipv4.tcp_timestamps = 1`：提升丢包恢复与 RTT 估计能力。
- `net.ipv4.tcp_slow_start_after_idle = 0`：减少空闲后重新传输的启动损失。
- `net.ipv4.tcp_no_metrics_save = 0`：保留已学习的路径指标。
- `net.ipv4.tcp_fastopen = 3`：为支持该能力的应用提供更快的建连路径。

## 环境检测

运行菜单 `4` 可在不改变服务器配置的情况下检查：

- Debian 与内核版本、CPU 逻辑核心、物理内存
- BBR 支持情况、当前拥塞控制、默认队列规则
- TCP 收发缓冲的最小/默认/最大值，以及核心缓冲默认/最大值
- 默认出站网卡、链路速率、接收队列、网卡错误与丢包
- TCP 发出段、重传段和累计重传比例

重传与网卡丢包均为自开机累计值。评估某次压测时，请记录压测前后的数值，并使用增量计算：

```text
增量重传率 = (压测后重传段 - 压测前重传段)
           / (压测后发出段 - 压测前发出段)
```

## 性能边界与压测建议

本项目提供的是 TCP 内核参数基线，不能保证所有机器、所有对端都跑满端口标称带宽。

- 1 Gbps 的跨地区 TCP 连接通常不会受 256 MiB 缓冲上限限制。
- 10 Gbps 单连接在约 200 ms RTT 时，256 MiB 已接近带宽时延积边界；更高 RTT、丢包或对端限制可能导致无法跑满。
- 单 TCP 流通常主要消耗一个 CPU 核。1 vCPU VPS 可能跑满 1 Gbps，但无法保证跑满 10 Gbps；多连接更能利用 2C、4C、8C 主机。
- 云厂商带宽上限、虚拟化争用、网卡 offload、应用 TLS/加密开销、对端性能和公网路由都可能先于 TCP 参数成为瓶颈。

推荐对同一测试对端分别执行单连接与多连接测试：

```bash
iperf3 -c <对端IP> -t 60 -P 1
iperf3 -c <对端IP> -t 60 -P 2
iperf3 -c <对端IP> -t 60 -P 4
```

结合菜单 `4` 的前后统计、CPU 使用率和网卡丢包判断瓶颈位置。不要通过继续堆叠 `sysctl` 参数、强制 Jumbo Frame、忙轮询或已废弃的 `tcp_tw_recycle` 来追求表面速度。

## 备份、恢复与注意事项

> **部署前请仔细阅读。** 菜单 `1` 会将现有 `/etc/sysctl.conf` 和 `/etc/sysctl.d/*.conf` 重命名为对应的 `.bak` 文件，再写入 `/etc/sysctl.d/99-k2-tcp-tune.conf`。请仅在你有权限管理且已理解现有 sysctl 配置的 VPS 上运行。

- 若发现已有 `.bak` 文件，脚本会停止，避免覆盖原始备份。
- 使用菜单 `2` 可删除 K2 配置、恢复备份并执行 `sysctl --system`。
- 使用菜单 `3` 只会删除 K2 配置；不会恢复备份，也不会立即重新应用 sysctl。
- 当前配置包含 IPv4/IPv6 转发相关项。仅在这符合你的服务器角色和网络设计时部署。

## 验证与排障

应用后，脚本会逐项显示目标值与实际值：

- `✓`：参数已正确应用
- `!`：参数不存在或当前内核不支持
- `×`：实际值与目标值不一致
- `i`：流程信息

只有所有目标参数均匹配时，脚本才会显示 TCP 调优应用成功。若失败，请优先检查：

1. `net.ipv4.tcp_available_congestion_control` 是否包含 `bbr`。
2. 当前内核和云厂商容器/虚拟化限制是否允许对应 sysctl。
3. 是否存在需要保留的自定义 sysctl 配置。

## 免责声明

请先在非关键业务主机或维护窗口内验证。网络调优应结合真实业务流量、压测数据和监控指标进行；本项目不对云厂商网络、跨运营商路径或对端系统造成的带宽、延迟和丢包问题作保证。

## 联系方式

- K2 CLOUD
- Email: [Kfcmature@gmail.com](mailto:Kfcmature@gmail.com)
