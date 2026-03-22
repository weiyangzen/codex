# codex-cli/scripts/init_firewall.sh 研究文档

## 场景与职责

`init_firewall.sh` 是一个网络隔离初始化脚本，专为 Codex CLI 的容器化安全沙箱设计。该脚本在 Docker 容器启动时执行，建立严格的出站网络访问控制，确保：

1. **最小权限原则**: 容器只能访问明确允许的域名（默认仅 `api.openai.com`）
2. **数据泄露防护**: 防止敏感代码或数据被传输到未授权的外部服务
3. **供应链安全**: 限制容器内进程只能与可信端点通信

该脚本服务于以下场景：
- **容器首次启动**: `run_in_container.sh` 在创建容器后调用此脚本
- **安全沙箱初始化**: 为 AI 代码执行环境建立网络边界
- **合规要求**: 满足企业安全策略对 AI 工具的网络限制

## 功能点目的

### 核心安全目标

| 目标 | 实现方式 |
|------|----------|
| 出站限制 | 默认 DROP 所有出站流量，仅允许白名单域名 |
| 域名解析 | 使用 `ipset` 存储解析后的 IP，支持动态 DNS |
| 本地通信 | 允许容器与宿主机网络（默认路由网段）的通信 |
| DNS 可用 | 允许 UDP 53 端口的 DNS 查询和响应 |
| 快速失败 | 对未授权连接返回 TCP reset / ICMP 不可达 |

### 配置来源

脚本支持两种域名配置方式：

1. **配置文件** (`/etc/codex/allowed_domains.txt`)
   - 由 `run_in_container.sh` 在容器创建时写入
   - 每行一个域名
   - 可通过 `OPENAI_ALLOWED_DOMAINS` 环境变量自定义

2. **默认回退**
   - 如果配置文件不存在，默认仅允许 `api.openai.com`

## 具体技术实现

### 脚本头与安全选项

```bash
#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
```

- `IFS=$'\n\t'`: 严格的字段分隔符，防止文件名中包含空格导致的解析错误

### 防火墙规则构建流程

```
1. 读取域名配置
2. 清空现有规则（iptables -F/-X, ipset destroy）
3. 允许 DNS 和 localhost
4. 创建 ipset 集合
5. 解析域名并添加到 ipset
6. 检测宿主机网络
7. 设置默认策略 DROP
8. 允许已建立连接
9. 允许到白名单 IP 的出站
10. 添加 REJECT 规则
11. 验证防火墙效果
```

### 关键命令详解

#### 1. 规则清空 (行 26-32)

```bash
iptables -F          # 清空所有链的规则
iptables -X          # 删除自定义链
iptables -t nat -F   # 清空 NAT 表
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true
```

**设计要点**：
- 清理所有表（filter, nat, mangle），确保无残留规则
- `ipset destroy` 失败不退出（`|| true`），因为可能不存在

#### 2. DNS 和本地回环允许 (行 35-41)

```bash
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
```

**顺序关键**：这些规则必须在默认 DROP 之前添加，否则 DNS 解析将失败。

#### 3. ipset 创建与填充 (行 44-62)

```bash
ipset create allowed-domains hash:net

for domain in "${ALLOWED_DOMAINS[@]}"; do
    ips=$(dig +short A "$domain")
    while read -r ip; do
        if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "ERROR: Invalid IP from DNS for $domain: $ip"
            exit 1
        fi
        ipset add allowed-domains "$ip"
    done < <(echo "$ips")
done
```

**技术细节**：
- `hash:net` 类型支持 CIDR 表示法（如 `1.2.3.0/24`）
- `dig +short A` 仅获取 A 记录（IPv4），忽略 CNAME 链
- IP 格式验证使用正则表达式，防止 DNS 污染或异常响应

#### 4. 宿主机网络检测 (行 65-73)

```bash
HOST_IP=$(ip route | grep default | cut -d" " -f3)
HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
```

**假设**：默认网关位于 `/24` 子网。这在 Docker 默认网桥模式下通常成立。

#### 5. 默认策略与规则顺序 (行 79-89)

```bash
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT
```

**规则优先级**：
1. ESTABLISHED,RELATED（已批准的连接响应）
2. 白名单 IP 匹配（新连接）
3. 默认 DROP（隐式）

#### 6. 主动拒绝 (行 92-98)

```bash
iptables -A INPUT -p tcp -j REJECT --reject-with tcp-reset
iptables -A INPUT -p udp -j REJECT --reject-with icmp-port-unreachable
iptables -A OUTPUT -p tcp -j REJECT --reject-with tcp-reset
```

**设计理由**：
- REJECT 比 DROP 更友好，立即告知客户端连接失败
- TCP reset 模拟端口未监听的行为
- ICMP port unreachable 是 UDP 的标准拒绝方式

#### 7. 功能验证 (行 101-115)

```bash
# 负向验证：example.com 应该不可达
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed"
    exit 1
fi

# 正向验证：api.openai.com 必须可达
if ! curl --connect-timeout 5 https://api.openai.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed"
    exit 1
fi
```

**双重验证**：
- 负向：确保未授权域名被阻断
- 正向：确保授权服务可访问
- 任一失败都导致脚本退出（`set -e`）

## 关键代码路径与文件引用

### 上游调用方

**`run_in_container.sh`** (行 82-86)
```bash
# 在容器内以 root 执行防火墙初始化
docker exec --user root "$CONTAINER_NAME" bash -c "/usr/local/bin/init_firewall.sh"
# 执行后删除脚本（安全清理）
docker exec --user root "$CONTAINER_NAME" bash -c "rm -f /usr/local/bin/init_firewall.sh"
```

**Dockerfile** (行 54-56)
```dockerfile
COPY scripts/init_firewall.sh /usr/local/bin/
RUN chmod 500 /usr/local/bin/init_firewall.sh
```

### 配置文件

**`/etc/codex/allowed_domains.txt`**
- 格式：每行一个域名
- 权限：444 (只读)，root:root 所有
- 由 `run_in_container.sh` 在运行时注入

### 依赖工具

| 工具 | 包 | 用途 |
|------|-----|------|
| `iptables` | iptables | 防火墙规则管理 |
| `ipset` | ipset | 高效 IP 集合管理 |
| `dig` | dnsutils | DNS 解析 |
| `ip` | iproute2 | 路由/网络信息 |
| `curl` | curl | 连通性验证 |

## 依赖与外部交互

### 运行时依赖

1. **root 权限**: 脚本需要 CAP_NET_ADMIN 能力来修改 iptables
2. **Docker 能力**: 容器启动时需 `--cap-add=NET_ADMIN --cap-add=NET_RAW`
3. **DNS 可用**: 执行时 DNS 服务必须可访问（用于解析白名单域名）

### 网络假设

| 假设 | 说明 |
|------|------|
| 默认网关可访问 | 用于检测宿主机网络 |
| 子网为 /24 | 宿主机网络范围计算假设 |
| IPv4 环境 | 仅处理 A 记录，无 IPv6 支持 |
| DNS 响应可信 | 不验证 DNSSEC |

### 与 Docker 的集成

```bash
# run_in_container.sh 中的容器启动
docker run --name "$CONTAINER_NAME" -d \
  -e OPENAI_API_KEY \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -v "$WORK_DIR:/app$WORK_DIR" \
  codex \
  sleep infinity
```

**关键能力**：
- `NET_ADMIN`: 允许修改网络配置（iptables, ipset）
- `NET_RAW`: 允许原始套接字（某些网络工具需要）

## 风险、边界与改进建议

### 已知风险

1. **DNS 劫持风险**
   - 脚本依赖 DNS 解析获取 IP，如果 DNS 被污染，可能允许错误 IP
   - **缓解**: IP 格式验证，但无法验证 IP 所有权

2. **CDN IP 变动**
   - `api.openai.com` 使用 CDN，IP 可能动态变化
   - **问题**: 容器运行期间 IP 变化会导致连接失败
   - **缓解**: 短期容器（单次任务）风险较低

3. **IPv6 不支持**
   - 仅处理 A 记录，如果主机优先使用 IPv6，连接可能失败
   - **代码**: `dig +short A` 明确仅查询 IPv4

4. **子网假设硬编码**
   - `sed "s/\.[0-9]*$/.0\/24/"` 假设 /24 子网
   - 如果 Docker 使用非标准子网，规则可能过于宽松或严格

5. **时间竞争条件**
   - DNS 解析和规则应用之间，域名 IP 可能变化
   - 如果解析到多个 IP，可能部分过时

### 边界条件

| 场景 | 行为 |
|------|------|
| 域名解析失败 | 脚本退出（`exit 1`） |
| 无效 IP 格式 | 脚本退出 |
| 无默认路由 | `HOST_IP` 为空，后续命令可能失败 |
| 空域名列表 | 脚本退出（`${#ALLOWED_DOMAINS[@]} -eq 0` 检查） |
| curl 未安装 | 验证失败，脚本退出 |
| example.com 可达 | 防火墙未生效，脚本退出 |
| api.openai.com 不可达 | 网络配置错误，脚本退出 |

### 改进建议

1. **IPv6 支持**
   ```bash
   # 查询 AAAA 记录并添加到 ipset
   ips_v6=$(dig +short AAAA "$domain")
   ```

2. **动态 DNS 刷新**
   ```bash
   # 添加后台任务定期刷新 ipset
   (while true; do
       sleep 300
       # 重新解析并更新 ipset
   done) &
   ```

3. **子网检测增强**
   ```bash
   # 使用 ipcalc 或类似工具正确计算子网
   HOST_NETWORK=$(ip route | grep default | awk '{print $3}' | xargs ipcalc -n)
   ```

4. **日志记录**
   ```bash
   # 添加被阻断连接的日志
   iptables -A OUTPUT -m limit --limit 5/min -j LOG --log-prefix "CODEX-BLOCKED: "
   ```

5. **域名格式验证**
   ```bash
   # 在 run_in_container.sh 验证的基础上，再次验证
   if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,}$ ]]; then
       echo "ERROR: Invalid domain: $domain"
       exit 1
   fi
   ```

6. **备用 DNS**
   ```bash
   # 如果默认 DNS 失败，尝试公共 DNS
   ips=$(dig +short A "$domain" @8.8.8.8)
   ```

7. **配置热重载**
   ```bash
   # 支持 SIGHUP 信号重新加载域名配置
   trap 'reload_domains' SIGHUP
   ```

### 安全加固建议

1. **只读根文件系统**
   ```bash
   # Dockerfile 中设置
   docker run --read-only ...
   ```

2. **能力最小化**
   ```bash
   # 防火墙初始化完成后，丢弃 NET_ADMIN
   capsh --drop=cap_net_admin -- -c "exec su - node"
   ```

3. **审计日志**
   ```bash
   # 记录所有允许的连接
   iptables -A OUTPUT -m set --match-set allowed-domains dst -j LOG --log-prefix "CODEX-ALLOWED: "
   ```

4. **出口端口限制**
   ```bash
   # 除特定端口外全部拒绝（如仅允许 443）
   iptables -A OUTPUT -m set --match-set allowed-domains dst -p tcp --dport 443 -j ACCEPT
   ```
