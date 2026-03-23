# state.rs 研究文档

## 场景与职责

`state.rs` 负责网络代理配置状态的构建、验证和约束管理。它是配置管理系统的核心，确保配置变更符合管理策略，防止用户绕过安全限制。

### 核心职责

1. **配置状态构建**：从 `NetworkProxyConfig` 构建运行时 `ConfigState`
2. **约束验证**：验证配置是否符合管理基线约束
3. **域名模式验证**：防止危险的通配符模式（如 `*`）
4. **配置重导出**：将运行时模块的关键类型重新导出

## 功能点目的

### 1. 配置状态构建

```rust
pub fn build_config_state(
    config: NetworkProxyConfig,
    constraints: NetworkProxyConstraints,
) -> anyhow::Result<ConfigState>
```

**构建流程**：
1. 验证 Unix socket 路径
2. 验证域名模式（防止全局通配符）
3. 编译 allowlist 和 denylist 的 globset
4. 初始化 MITM 状态（如果启用）
5. 创建空的阻止请求缓冲区

### 2. 约束验证系统

```rust
pub fn validate_policy_against_constraints(
    config: &NetworkProxyConfig,
    constraints: &NetworkProxyConstraints,
) -> Result<(), NetworkProxyConstraintError>
```

**约束类型**：
- `enabled`：是否允许启用代理
- `mode`：最大允许的网络模式（Limited < Full）
- `allow_upstream_proxy`：是否允许上游代理
- `dangerously_allow_non_loopback_proxy`：是否允许非环回绑定
- `dangerously_allow_all_unix_sockets`：是否允许所有 Unix socket
- `allowed_domains`：允许的域名基线
- `allowlist_expansion_enabled`：是否允许扩展 allowlist
- `denied_domains`：拒绝的域名基线
- `denylist_expansion_enabled`：是否允许扩展 denylist
- `allow_unix_sockets`：允许的 Unix socket 路径
- `allow_local_binding`：是否允许本地绑定

### 3. 域名列表管理约束

**Allowlist 约束模式**：

| 约束设置 | 行为 |
|----------|------|
| `allowlist_expansion_enabled = Some(true)` | 允许添加新域名，但必须包含所有基线域名 |
| `allowlist_expansion_enabled = Some(false)` | 域名列表必须与基线完全一致 |
| `allowlist_expansion_enabled = None` | 允许子集，每个域名必须被基线模式覆盖 |

**Denylist 约束模式**：

| 约束设置 | 行为 |
|----------|------|
| `denylist_expansion_enabled = Some(false)` | 域名列表必须与基线完全一致 |
| `denylist_expansion_enabled = Some(true)` / `None` | 允许添加新域名，但必须包含所有基线域名 |

### 4. 全局通配符防护

```rust
fn validate_domain_patterns(
    field_name: &'static str,
    patterns: &[String],
) -> Result<(), NetworkProxyConstraintError>
```

**禁止的模式**：
- `*` - 匹配所有域名
- `[*]` - 括号包裹的全局通配符
- `**.[*]` - 双通配符前缀 + 括号全局通配符

**目的**：防止配置错误导致的安全漏洞

## 具体技术实现

### 关键数据结构

#### NetworkProxyConstraints

```rust
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct NetworkProxyConstraints {
    pub enabled: Option<bool>,
    pub mode: Option<NetworkMode>,
    pub allow_upstream_proxy: Option<bool>,
    pub dangerously_allow_non_loopback_proxy: Option<bool>,
    pub dangerously_allow_all_unix_sockets: Option<bool>,
    pub allowed_domains: Option<Vec<String>>,
    pub allowlist_expansion_enabled: Option<bool>,
    pub denied_domains: Option<Vec<String>>,
    pub denylist_expansion_enabled: Option<bool>,
    pub allow_unix_sockets: Option<Vec<String>>,
    pub allow_local_binding: Option<bool>,
}
```

**设计原则**：
- 所有字段为 `Option`，表示"未约束"
- `None` 表示该维度不受管理控制
- 与 `NetworkProxySettings` 字段一一对应

#### PartialNetworkProxyConfig / PartialNetworkConfig

```rust
#[derive(Debug, Clone, Deserialize)]
pub struct PartialNetworkProxyConfig {
    #[serde(default)]
    pub network: PartialNetworkConfig,
}

#[derive(Debug, Default, Clone, Deserialize)]
pub struct PartialNetworkConfig {
    pub enabled: Option<bool>,
    pub mode: Option<NetworkMode>,
    // ... 所有字段都是 Option
}
```

**用途**：
- 支持部分配置更新（PATCH 语义）
- 与完整配置区分，明确表达"未设置"状态

#### NetworkProxyConstraintError

```rust
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum NetworkProxyConstraintError {
    #[error("invalid value for {field_name}: {candidate} (allowed {allowed})")]
    InvalidValue {
        field_name: &'static str,
        candidate: String,
        allowed: String,
    },
}
```

### 约束验证实现细节

#### 网络模式排名

```rust
fn network_mode_rank(mode: NetworkMode) -> u8 {
    match mode {
        NetworkMode::Limited => 0,
        NetworkMode::Full => 1,
    }
}
```

- 数值越大，权限越宽松
- 验证时比较排名，确保不会放宽限制

#### Allowlist 子集验证（无显式扩展标志时）

```rust
let managed_patterns: Vec<DomainPattern> = allowed_domains
    .iter()
    .map(|entry| DomainPattern::parse_for_constraints(entry))
    .collect();
validate(config.network.allowed_domains.clone(), move |candidate| {
    let mut invalid = Vec::new();
    for entry in candidate {
        let candidate_pattern = DomainPattern::parse_for_constraints(entry);
        if !managed_patterns
            .iter()
            .any(|managed| managed.allows(&candidate_pattern))
        {
            invalid.push(entry.clone());
        }
    }
    ...
})?;
```

**逻辑**：
- 将管理基线解析为 `DomainPattern`
- 检查每个候选域名是否被至少一个基线模式覆盖
- 支持通配符匹配（如基线 `*.example.com` 允许候选 `api.example.com`）

### 重导出机制

```rust
pub use crate::runtime::BlockedRequest;
pub use crate::runtime::BlockedRequestArgs;
pub use crate::runtime::NetworkProxyAuditMetadata;
pub use crate::runtime::NetworkProxyState;
#[cfg(test)]
pub(crate) use crate::runtime::network_proxy_state_for_policy;
```

**设计目的**：
- `state` 模块作为配置管理的入口
- 将运行时类型重导出，方便调用方统一使用
- 测试辅助函数仅在 test 配置下导出

## 关键代码路径与文件引用

### 主要函数

| 函数 | 行号 | 说明 |
|------|------|------|
| `build_config_state` | 57-84 | 构建配置状态 |
| `validate_policy_against_constraints` | 86-365 | 约束验证主函数 |
| `validate_domain_patterns` | 367-383 | 域名模式验证 |
| `network_mode_rank` | 401-406 | 网络模式排名 |

### 约束验证代码结构（行 86-365）

```rust
pub fn validate_policy_against_constraints(config, constraints) -> Result<(), NetworkProxyConstraintError> {
    // 1. 验证域名模式格式
    validate_domain_patterns("network.allowed_domains", ...)?;
    validate_domain_patterns("network.denied_domains", ...)?;
    
    // 2. 验证 enabled 约束
    if let Some(max_enabled) = constraints.enabled { ... }
    
    // 3. 验证 mode 约束
    if let Some(max_mode) = constraints.mode { ... }
    
    // 4. 验证 allow_upstream_proxy 约束
    ...
    
    // 5. 验证 dangerously_allow_non_loopback_proxy 约束
    ...
    
    // 6. 验证 dangerously_allow_all_unix_sockets 约束
    ...
    
    // 7. 验证 allow_local_binding 约束
    ...
    
    // 8. 验证 allowed_domains 约束（复杂逻辑）
    if let Some(allowed_domains) = &constraints.allowed_domains { ... }
    
    // 9. 验证 denied_domains 约束
    if let Some(denied_domains) = &constraints.denied_domains { ... }
    
    // 10. 验证 allow_unix_sockets 约束
    if let Some(allow_unix_sockets) = &constraints.allow_unix_sockets { ... }
    
    Ok(())
}
```

### 关键辅助函数

```rust
// 行 90-107：验证辅助函数
fn invalid_value(field_name, candidate, allowed) -> NetworkProxyConstraintError
fn validate<T>(candidate, validator) -> Result<(), NetworkProxyConstraintError>
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::config::*` | 配置结构定义 |
| `crate::mitm::MitmState` | MITM 状态初始化 |
| `crate::policy::*` | 域名模式解析和 globset 编译 |
| `crate::runtime::ConfigState` | 运行时状态结构 |

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `anyhow` | 错误处理 |
| `globset` | Glob 模式匹配 |
| `serde::Deserialize` | 部分配置反序列化 |

### 调用方

- `runtime.rs`：`build_config_state()`, `validate_policy_against_constraints()`
- 外部 crate：通过 `lib.rs` 公开的重导出

## 风险、边界与改进建议

### 潜在风险

1. **约束绕过风险**
   - 当前约束验证在配置变更时执行
   - 如果直接修改配置文件并重启，可能绕过约束
   - 建议：在启动时也执行约束验证

2. **通配符语义复杂**
   - `*`、`*.`、`**.`、`[*]` 等多种通配符形式
   - 用户可能误解语义，导致意外开放访问
   - 建议：添加配置时警告/确认机制

3. **大小写敏感问题**
   - 域名比较使用 `to_ascii_lowercase()`
   - 但某些国际化域名可能有特殊规则
   - 建议：使用 IDNA 规范处理国际化域名

### 边界情况

1. **空约束**
   - `NetworkProxyConstraints::default()` 所有字段为 `None`
   - 表示完全无约束，允许任何配置
   - 适用于非托管场景

2. **空 allowlist**
   - 配置中 `allowed_domains = []`
   - 表示拒绝所有域名访问
   - 与全局通配符 `*` 不同（后者被禁止）

3. **约束变更竞争**
   - `runtime.rs` 使用乐观并发控制
   - 约束可能在验证和提交之间变更
   - 已实现 CAS 重试机制处理

### 改进建议

1. **配置验证增强**
   - 添加启动时约束验证
   - 支持配置警告（非致命）
   - 添加配置变更预览功能

2. **错误信息改进**
   - 当前错误信息较技术化
   - 建议添加用户友好的错误说明
   - 提供配置修复建议

3. **性能优化**
   - `DomainPattern::parse_for_constraints` 可能被重复调用
   - 建议缓存解析结果

4. **功能扩展**
   - 支持时间窗口约束（如只允许工作时间访问）
   - 支持速率限制约束
   - 支持按用户/角色的差异化约束

5. **代码质量**
   - `validate_policy_against_constraints` 函数较长（~280 行）
   - 建议按约束类型拆分为子函数
   - 添加更多单元测试覆盖边界情况
