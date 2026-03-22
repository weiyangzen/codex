# network_proxy_loader_tests.rs 深度研究文档

## 场景与职责

`network_proxy_loader_tests.rs` 是 `network_proxy_loader.rs` 的配套测试模块，提供对网络代理配置加载逻辑的单元测试覆盖。测试验证配置层优先级、执行策略规则合并和网络约束应用等核心功能。

## 功能点目的

### 1. 配置层优先级测试 (`higher_precedence_profile_network_beats_lower_profile_network`)
- **目的**：验证高优先级配置层的网络设置覆盖低优先级层
- **测试场景**：低层设置 `lower.example.com`，高层设置 `higher.example.com`，验证最终只有高层配置生效

### 2. 执行策略规则合并测试 (`execpolicy_network_rules_overlay_network_lists`)
- **目的**：验证 execpolicy 的网络规则正确合并到代理配置
- **测试场景**：
  - execpolicy 允许 `blocked.example.com`（从拒绝列表移到允许列表）
  - execpolicy 拒绝 `api.example.com`（添加到拒绝列表）

### 3. Unix Socket 约束测试 (`apply_network_constraints_includes_allow_all_unix_sockets_flag`)
- **目的**：验证 `dangerously_allow_all_unix_sockets` 约束正确提取
- **测试场景**：解析包含该标志的配置，验证约束对象正确设置

## 具体技术实现

### 测试结构

```rust
use super::*;
use codex_execpolicy::Decision;
use codex_execpolicy::NetworkRuleProtocol;
use codex_execpolicy::Policy;
use pretty_assertions::assert_eq;
```

### 测试数据构造模式

```rust
// TOML 配置值构造
let lower_network: toml::Value = toml::from_str(
    r#"
default_permissions = "workspace"

[permissions.workspace.network]
allowed_domains = ["lower.example.com"]
"#,
)
.expect("lower layer should parse");

// 网络代理配置
let mut config = NetworkProxyConfig::default();

// 应用配置层
apply_network_tables(
    &mut config,
    network_tables_from_toml(&lower_network).expect("lower layer should deserialize"),
)
.expect("lower layer should apply");

// 断言验证
assert_eq!(config.network.allowed_domains, vec!["higher.example.com"]);
```

### 执行策略构造

```rust
let mut exec_policy = Policy::empty();
exec_policy
    .add_network_rule(
        "blocked.example.com",
        NetworkRuleProtocol::Https,
        Decision::Allow,
        None,
    )
    .expect("allow rule should be valid");
exec_policy
    .add_network_rule(
        "api.example.com",
        NetworkRuleProtocol::Http,
        Decision::Forbidden,
        None,
    )
    .expect("deny rule should be valid");
```

## 关键代码路径与文件引用

### 测试函数清单

| 测试函数 | 行号 | 测试目标 |
|----------|------|----------|
| `higher_precedence_profile_network_beats_lower_profile_network` | 8-42 | 配置层优先级 |
| `execpolicy_network_rules_overlay_network_lists` | 44-81 | 执行策略规则合并 |
| `apply_network_constraints_includes_allow_all_unix_sockets_flag` | 83-104 | Unix Socket 约束 |

### 被测函数覆盖

| 被测函数 | 测试覆盖 |
|----------|----------|
| `apply_network_tables` | `higher_precedence_profile_network_beats_*` |
| `network_tables_from_toml` | 所有测试 |
| `apply_exec_policy_network_rules` | `execpolicy_network_rules_*` |
| `upsert_network_domain` | `execpolicy_network_rules_*` |
| `selected_network_from_tables` | `apply_network_constraints_*` |
| `apply_network_constraints` | `apply_network_constraints_*` |

## 依赖与外部交互

### 测试依赖

```rust
// 被测模块
use super::*;

// 执行策略
codex_execpolicy::Decision
codex_execpolicy::NetworkRuleProtocol
codex_execpolicy::Policy

// 断言增强
use pretty_assertions::assert_eq;
```

### 隐式依赖

| 依赖 | 来源 | 用途 |
|------|------|------|
| `toml::Value` | toml crate | TOML 解析 |
| `NetworkProxyConfig` | codex_network_proxy | 配置对象 |
| `NetworkProxyConstraints` | codex_network_proxy | 约束对象 |
| `NetworkToml` | crate::config | 网络配置类型 |

## 风险、边界与改进建议

### 当前测试覆盖 gaps

1. **完整配置构建测试缺失**
   - 没有测试 `build_config_state_with_mtimes`
   - 没有测试 `build_network_proxy_state`
   - 没有测试多层配置合并的完整流程

2. **约束验证测试缺失**
   - 没有测试 `enforce_trusted_constraints`
   - 没有测试约束违反的错误处理
   - 没有测试 `is_user_controlled_layer` 的各种场景

3. **重载器测试缺失**
   - 没有测试 `MtimeConfigReloader`
   - 没有测试 `needs_reload` 逻辑
   - 没有测试配置变更检测

4. **错误场景测试缺失**
   - 没有测试无效 TOML 处理
   - 没有测试缺失权限表处理
   - 没有测试 execpolicy 加载失败处理

5. **边界条件测试缺失**
   - 没有测试空域名列表
   - 没有测试重复域名处理
   - 没有测试大量配置层性能

### 改进建议

1. **添加完整构建测试**
```rust
#[tokio::test]
async fn build_config_state_combines_all_layers() {
    // 创建临时目录结构
    // 创建多层配置文件
    // 调用 build_config_state_with_mtimes
    // 验证合并结果
}
```

2. **添加约束验证测试**
```rust
#[test]
fn enforce_trusted_constraints_blocks_user_override() {
    // 创建包含约束的可信层配置
    // 创建违反约束的用户层配置
    // 验证返回错误
}

#[test]
fn is_user_controlled_layer_identifies_correct_layers() {
    // 测试各种 ConfigLayerSource 变体
    // 验证用户控制层正确识别
}
```

3. **添加重载器测试**
```rust
#[tokio::test]
async fn mtime_reloader_detects_file_changes() {
    // 创建临时配置文件
    // 构建 MtimeConfigReloader
    // 修改文件
    // 验证 needs_reload 返回 true
}
```

4. **添加错误处理测试**
```rust
#[test]
fn network_tables_from_toml_handles_invalid_toml() {
    // 测试无效 TOML 的错误处理
}

#[test]
fn selected_network_from_tables_handles_missing_permissions() {
    // 测试缺失权限表的处理
}
```

5. **添加边界条件测试**
```rust
#[test]
fn upsert_network_domain_handles_duplicates() {
    // 测试重复域名处理
    // 验证去重和移动逻辑
}

#[test]
fn apply_network_constraints_handles_empty_lists() {
    // 测试空列表处理
}
```

6. **使用 insta snapshot 测试**
   - 对复杂配置结构进行快照测试
   - 便于检测意外的配置合并行为变化

### 测试代码质量建议

1. **提取公共辅助函数**
```rust
fn create_test_network_toml(allowed_domains: Vec<&str>) -> toml::Value {
    let domains = allowed_domains.join("\", \"");
    toml::from_str(&format!(
        r#"
default_permissions = "workspace"
[permissions.workspace.network]
allowed_domains = ["{}"]
"#,
        domains
    )).unwrap()
}
```

2. **使用参数化测试**
   - 使用 `rstest` 测试多种配置层组合

3. **添加文档注释**
   - 为每个测试添加更详细的说明
   - 解释测试的意图和预期行为

4. **改进断言消息**
   - 添加自定义断言消息，便于调试失败
