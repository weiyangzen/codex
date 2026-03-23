# policy.rs 深度研究文档

## 场景与职责

`policy.rs` 是 Codex 网络代理的策略核心模块，负责域名/主机策略的解析、归一化和匹配。该模块实现了：

1. **主机名归一化**：处理各种格式的主机名（IPv6 括号、端口、大小写、尾部点号等）
2. **IP 地址分类**：识别本地/私有/非公共 IP 地址，防止 SSRF 攻击
3. **域名模式匹配**：支持通配符模式（`*.example.com`、`**.example.com`）的解析和匹配
4. **GlobSet 编译**：将域名模式编译为高效的匹配结构

该模块是网络安全策略的基础，确保域名黑白名单能够正确、高效地匹配。

## 功能点目的

### 1. 主机名封装 (`Host`)

安全的、已归一化的主机名字符串封装：
- 通过 `Host::parse()` 确保主机名经过归一化处理
- 防止未归一化的主机名直接进入策略匹配流程

### 2. 回环主机检测 (`is_loopback_host`)

检测主机名是否为本地回环地址：
- `localhost` 及其变体
- IPv4 回环地址（127.0.0.1/8）
- IPv6 回环地址（::1）
- 支持范围 ID（如 `fe80::1%lo0`）

### 3. 非公共 IP 检测 (`is_non_public_ip`)

全面的私有/非公共 IP 地址检测，防止 SSRF 攻击：

**IPv4 非公共范围**：
- 回环（127.0.0.0/8）
- 私有网络（10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16）
- 链路本地（169.254.0.0/16）
- 未指定（0.0.0.0/8）
- 多播（224.0.0.0/4）
- 广播（255.255.255.255）
- CGNAT（100.64.0.0/10）
- 测试网络（192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24）
- 基准测试（198.18.0.0/15）
- 保留（240.0.0.0/4）

**IPv6 非公共范围**：
- 回环（::1）
- 唯一本地（fc00::/7）
- 链路本地（fe80::/10）
- 未指定（::）
- 多播（ff00::/8）

### 4. 主机名归一化 (`normalize_host`)

处理各种主机名格式：
- 去除首尾空白
- 去除方括号（IPv6）
- 去除端口号（host:port 格式）
- 转换为小写
- 去除尾部点号（FQDN）

### 5. 域名模式解析 (`DomainPattern`)

解析和比较域名模式：
- `Exact`：精确匹配（如 `example.com`）
- `SubdomainsOnly`：仅子域名（如 `*.example.com`，不匹配 apex）
- `ApexAndSubdomains`：Apex 和子域名（如 `**.example.com`）

支持模式间的包含关系检查（`allows` 方法）。

### 6. GlobSet 编译 (`compile_globset`)

将域名模式列表编译为高效的 GlobSet：
- 支持 `*.example.com` → `?*.example.com` 转换
- 支持 `**.example.com` → `example.com` + `?*.example.com` 转换
- 拒绝全局通配符 `*`（安全风险）
- 大小写不敏感匹配

## 具体技术实现

### IP 地址分类实现

```rust
fn is_non_public_ipv4(ip: Ipv4Addr) -> bool {
    ip.is_loopback()
        || ip.is_private()
        || ip.is_link_local()
        || ip.is_unspecified()
        || ip.is_multicast()
        || ip.is_broadcast()
        || ipv4_in_cidr(ip, [100, 64, 0, 0], 10)  // CGNAT
        || ipv4_in_cidr(ip, [192, 0, 2, 0], 24)  // TEST-NET-1
        // ... 其他范围
}
```

使用 CIDR 检查实现：
```rust
fn ipv4_in_cidr(ip: Ipv4Addr, base: [u8; 4], prefix: u8) -> bool {
    let ip = u32::from(ip);
    let base = u32::from(Ipv4Addr::from(base));
    let mask = if prefix == 0 { 0 } else { u32::MAX << (32 - prefix) };
    (ip & mask) == (base & mask)
}
```

### 主机名归一化流程

```rust
pub fn normalize_host(host: &str) -> String {
    let host = host.trim();
    
    // 处理方括号 IPv6: [::1] → ::1
    if host.starts_with('[') && let Some(end) = host.find(']') {
        return normalize_dns_host(&host[1..end]);
    }
    
    // 处理 host:port（只有一个冒号）
    if host.bytes().filter(|b| *b == b':').count() == 1 {
        let host = host.split(':').next().unwrap_or_default();
        return normalize_dns_host(host);
    }
    
    // 保留未括号 IPv6，归一化 DNS 主机
    normalize_dns_host(host)
}

fn normalize_dns_host(host: &str) -> String {
    let host = host.to_ascii_lowercase();
    host.trim_end_matches('.').to_string()
}
```

### 域名模式扩展

```rust
fn expand_domain_pattern(pattern: &str) -> Vec<String> {
    match DomainPattern::parse(pattern) {
        DomainPattern::Exact(domain) => vec![domain],
        DomainPattern::SubdomainsOnly(domain) => {
            vec![format!("?*.{domain}")]
        }
        DomainPattern::ApexAndSubdomains(domain) => {
            vec![domain.clone(), format!("?*.{domain}")]
        }
    }
}
```

### DomainPattern 包含关系

```rust
pub(crate) fn allows(&self, candidate: &DomainPattern) -> bool {
    match self {
        DomainPattern::Exact(domain) => match candidate {
            DomainPattern::Exact(candidate) => domain_eq(candidate, domain),
            _ => false,
        },
        DomainPattern::SubdomainsOnly(domain) => match candidate {
            DomainPattern::Exact(candidate) => is_strict_subdomain(candidate, domain),
            DomainPattern::SubdomainsOnly(candidate) => {
                is_subdomain_or_equal(candidate, domain)
            }
            DomainPattern::ApexAndSubdomains(candidate) => {
                is_strict_subdomain(candidate, domain)
            }
        },
        // ... ApexAndSubdomains 类似
    }
}
```

## 关键代码路径与文件引用

### 核心类型定义

| 类型 | 行号 | 描述 |
|------|------|------|
| `Host` | 16-29 | 归一化主机名封装 |
| `DomainPattern` | 181-186 | 域名模式枚举 |

### 核心函数

| 函数 | 行号 | 描述 |
|------|------|------|
| `is_loopback_host` | 32-42 | 回环主机检测 |
| `is_non_public_ip` | 44-49 | 非公共 IP 检测入口 |
| `is_non_public_ipv4` | 51-69 | IPv4 非公共检测 |
| `is_non_public_ipv6` | 82-97 | IPv6 非公共检测 |
| `normalize_host` | 99-118 | 主机名归一化 |
| `compile_globset` | 154-179 | GlobSet 编译 |
| `DomainPattern::parse` | 193-205 | 模式解析 |
| `DomainPattern::allows` | 230-255 | 模式包含检查 |

### 辅助函数

| 函数 | 行号 | 描述 |
|------|------|------|
| `ipv4_in_cidr` | 71-80 | CIDR 范围检查 |
| `normalize_pattern` | 125-145 | 模式归一化 |
| `expand_domain_pattern` | 277-287 | 模式扩展 |
| `is_subdomain_or_equal` | 297-304 | 子域名检查 |
| `is_strict_subdomain` | 306-310 | 严格子域名检查 |

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::config` | `NetworkMode`（测试用） |

### 外部 crate 依赖

| crate | 用途 |
|-------|------|
| `anyhow` | 错误处理 |
| `globset` | GlobSet 编译和匹配 |
| `url` | URL 主机解析（约束验证） |

### 调用方

1. **`runtime.rs`**：
   - `host_blocked()`：使用 `is_loopback_host`、`is_non_public_ip`
   - DNS 解析后的 IP 分类检查

2. **`state.rs`**：
   - `build_config_state()`：调用 `compile_globset`
   - `validate_policy_against_constraints()`：使用 `DomainPattern`

3. **`network_policy.rs`**：
   - 间接通过 `runtime.rs` 使用

4. **`http_proxy.rs`** / **`socks5.rs`**：
   - `normalize_host()`：归一化请求中的主机名

## 风险、边界与改进建议

### 潜在风险

1. **DNS 重绑定绕过**：
   - 当前实现会解析主机名并检查解析后的 IP
   - 但 DNS 查询有 2 秒超时，攻击者可能利用竞态条件
   - 建议：考虑添加 DNS 结果缓存和 TTL 检查

2. **IPv6 范围 ID 处理**：
   - 范围 ID（如 `%lo0`）在处理时会被分割
   - 需要确保所有代码路径正确处理带范围 ID 的地址
   - 已在 `is_loopback_host` 中处理，但需持续验证

3. **全局通配符拒绝**：
   - `compile_globset` 会拒绝 `*` 模式
   - 但 `*.*` 等变体仍可能被接受，需要检查
   - 建议：添加更严格的模式验证

### 边界情况

1. **空主机名**：
   - `Host::parse()` 会拒绝空主机名
   - 调用方需要处理 `Result`

2. **国际化域名 (IDN)**：
   - 当前实现不处理 Punycode 转换
   - `example.com` 和 `xn--example.com` 被视为不同
   - 建议：添加 IDN 支持

3. **IPv6 双冒号缩写**：
   - `::1` 和 `0:0:0:0:0:0:0:1` 被视为相同（标准库处理）
   - 但归一化后格式可能不同

4. **大写 IPv6**：
   - IPv6 地址中的十六进制字母会被转为小写
   - `2001:DB8::1` → `2001:db8::1`

### 改进建议

1. **性能优化**：
   - `compile_globset` 在配置变更时调用，考虑增量更新
   - 对频繁匹配的主机名添加缓存

2. **安全增强**：
   - 添加对 `0.0.0.0` 的特殊处理（当前已覆盖）
   - 考虑添加对 IPv4 映射 IPv6 地址的额外检查

3. **功能扩展**：
   - 支持 CIDR 格式的 IP 范围（如 `192.168.0.0/16`）
   - 支持正则表达式模式（高级用例）

4. **代码简化**：
   - `DomainPattern` 的 `allows` 方法逻辑复杂，可以添加更多注释
   - 考虑使用属性测试（property-based testing）验证模式匹配

### 测试覆盖

该模块有完善的测试覆盖（约 120 行测试代码），包括：
- 网络模式方法允许检查
- GlobSet 编译和归一化
- 通配符模式（`*.` 和 `**.`）
- IPv6 括号处理
- 回环主机变体
- 非公共 IP 范围
- 主机名归一化各种场景

建议添加：
- IDN/Punycode 测试
- 边界 IP 地址测试（如 100.63.255.255 vs 100.64.0.0）
- 大规模 GlobSet 性能测试
