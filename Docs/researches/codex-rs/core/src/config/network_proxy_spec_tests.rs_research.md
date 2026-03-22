# NetworkProxySpec Tests 研究文档

## 场景与职责

本测试文件是 `network_proxy_spec.rs` 的配套单元测试，位于 `#[cfg(test)]` 模块中。它负责验证网络代理规范的核心行为，特别是：

1. **托管策略与用户配置的交互**：验证企业/托管环境下的配置合并逻辑
2. **沙箱策略影响**：验证不同沙箱模式（ReadOnly/WorkspaceWrite/DangerFullAccess）对网络权限的影响
3. **审计元数据传递**：验证审计信息正确传递到网络代理层
4. **边界条件处理**：验证空列表、缺失配置等边界情况

## 功能点目的

### 1. 审计元数据测试
验证 `NetworkProxyAuditMetadata` 正确传递到 `NetworkProxyState`：
- 会话 ID、应用版本、用户账户 ID 等字段

### 2. 允许列表合并策略测试
验证三种场景下的允许列表行为：
- **默认模式**：托管基线 + 用户扩展
- **DangerFullAccess 模式**：仅使用托管基线，忽略用户扩展
- **ManagedOnly 模式**：仅使用托管列表，硬拒绝未匹配请求

### 3. 拒绝列表合并策略测试
验证拒绝列表的合并行为与允许列表类似

### 4. 边界条件测试
- 空托管列表 + managed_only 模式
- 不同沙箱策略组合

## 具体技术实现

### 测试结构

```rust
#[test]
fn requirements_allowed_domains_are_a_baseline_for_user_allowlist() {
    // 1. 准备基础配置（用户配置）
    let mut config = NetworkProxyConfig::default();
    config.network.allowed_domains = vec!["api.example.com".to_string()];
    
    // 2. 准备管理约束
    let requirements = NetworkConstraints {
        allowed_domains: Some(vec!["*.example.com".to_string()]),
        ..Default::default()
    };
    
    // 3. 创建 Spec（使用 ReadOnly 沙箱策略）
    let spec = NetworkProxySpec::from_config_and_constraints(
        config,
        Some(requirements),
        &SandboxPolicy::new_read_only_policy(),
    ).expect("config should stay within the managed allowlist");
    
    // 4. 验证结果
    assert_eq!(
        spec.config.network.allowed_domains,
        vec!["*.example.com".to_string(), "api.example.com".to_string()]
    );
    assert_eq!(
        spec.constraints.allowed_domains,
        Some(vec!["*.example.com".to_string()])
    );
    assert_eq!(spec.constraints.allowlist_expansion_enabled, Some(true));
}
```

### 关键测试用例分析

| 测试函数 | 验证场景 | 预期行为 |
|---------|---------|---------|
| `build_state_with_audit_metadata_threads_metadata_to_state` | 审计元数据传递 | 元数据完整传递到 state |
| `requirements_allowed_domains_are_a_baseline_for_user_allowlist` | 默认模式列表合并 | 托管基线 + 用户扩展 |
| `danger_full_access_keeps_managed_allowlist_and_denylist_fixed` | DangerFullAccess 模式 | 仅使用托管基线，禁用扩展 |
| `managed_allowed_domains_only_disables_default_mode_allowlist_expansion` | ManagedOnly 模式 | 禁用扩展，硬拒绝未匹配 |
| `managed_allowed_domains_only_ignores_user_allowlist_and_hard_denies_misses` | ManagedOnly + 用户配置 | 忽略用户配置，硬拒绝 |
| `managed_allowed_domains_only_without_managed_allowlist_blocks_all_user_domains` | ManagedOnly + 空托管列表 | 允许列表为空，全部拒绝 |
| `managed_allowed_domains_only_blocks_all_user_domains_in_full_access_without_managed_list` | ManagedOnly + DangerFullAccess + 空列表 | 同上，不受沙箱策略影响 |
| `requirements_denied_domains_are_a_baseline_for_default_mode` | 拒绝列表合并 | 与允许列表相同逻辑 |

### 沙箱策略与扩展启用关系

```
┌─────────────────────┬──────────────────────┬─────────────────────┐
│    沙箱策略          │ managed_allowed_only │ allowlist_expansion │
├─────────────────────┼──────────────────────┼─────────────────────┤
│ ReadOnly            │ false                │ true                │
│ WorkspaceWrite      │ false                │ true                │
│ DangerFullAccess    │ false                │ false               │
│ ReadOnly            │ true                 │ false               │
│ WorkspaceWrite      │ true                 │ false               │
│ DangerFullAccess    │ true                 │ false               │
└─────────────────────┴──────────────────────┴─────────────────────┘
```

## 关键代码路径与文件引用

### 本文件测试函数

| 函数 | 行号 | 测试目标 |
|------|------|---------|
| `build_state_with_audit_metadata_threads_metadata_to_state` | 5-22 | 审计元数据传递 |
| `requirements_allowed_domains_are_a_baseline_for_user_allowlist` | 24-49 | 默认模式允许列表合并 |
| `danger_full_access_keeps_managed_allowlist_and_denylist_fixed` | 51-79 | DangerFullAccess 模式行为 |
| `managed_allowed_domains_only_disables_default_mode_allowlist_expansion` | 81-103 | ManagedOnly 禁用扩展 |
| `managed_allowed_domains_only_ignores_user_allowlist_and_hard_denies_misses` | 105-132 | ManagedOnly 硬拒绝 |
| `managed_allowed_domains_only_without_managed_allowlist_blocks_all_user_domains` | 134-154 | 空托管列表边界 |
| `managed_allowed_domains_only_blocks_all_user_domains_in_full_access_without_managed_list` | 156-176 | DangerFullAccess + 空列表 |
| `requirements_denied_domains_are_a_baseline_for_default_mode` | 178-202 | 拒绝列表合并 |

### 被测代码

- `network_proxy_spec.rs` 第 74-298 行的核心逻辑
- 特别是 `from_config_and_constraints`、`apply_requirements`、`allowlist_expansion_enabled`

## 依赖与外部交互

### 测试依赖

```rust
use super::*;  // 导入被测模块
use pretty_assertions::assert_eq;  // 更好的 diff 输出
```

### 外部类型使用

| 类型 | 来源 | 用途 |
|------|------|------|
| `NetworkProxyConfig` | `codex_network_proxy` | 基础配置 |
| `NetworkConstraints` | `config_loader` | 管理约束 |
| `SandboxPolicy` | `codex_protocol` | 沙箱策略 |
| `NetworkProxyAuditMetadata` | `codex_network_proxy` | 审计元数据 |

## 风险、边界与改进建议

### 测试覆盖缺口

1. **执行策略规则测试缺失**
   - 没有测试 `with_exec_policy_network_rules` 方法
   - 建议：添加执行策略动态修改网络规则的测试

2. **SOCKS5 配置测试缺失**
   - 没有测试 `socks_enabled`、`proxy_host_and_port` 等方法
   - 建议：添加 SOCKS5 相关配置测试

3. **错误处理测试缺失**
   - 没有测试配置验证失败的情况
   - `validate_policy_against_constraints` 的错误路径未覆盖

4. **并发安全测试缺失**
   - `StartedNetworkProxy` 的线程安全性未测试

### 测试改进建议

1. **参数化测试**
   ```rust
   // 建议使用 rstest 或类似框架
   #[rstest]
   #[case(SandboxPolicy::ReadOnly, true)]
   #[case(SandboxPolicy::WorkspaceWrite, true)]
   #[case(SandboxPolicy::DangerFullAccess, false)]
   fn test_allowlist_expansion(#[case] policy: SandboxPolicy, #[case] expected: bool) {
       // ...
   }
   ```

2. **属性测试（Property Testing）**
   ```rust
   // 使用 proptest 验证域名合并的交换律、结合律
   proptest! {
       #[test]
       fn merge_is_commutative(a in domain_list(), b in domain_list()) {
           assert_eq!(
               merge_domain_lists(a.clone(), &b),
               merge_domain_lists(b, &a)
           );
       }
   }
   ```

3. **集成测试补充**
   - 当前测试仅验证 Spec 创建，未验证代理实际启动
   - 建议：添加使用 `start_proxy` 的异步集成测试

### 边界情况验证

当前测试已覆盖的边界：
- ✅ 空托管列表 + ManagedOnly
- ✅ 空用户列表
- ✅ 大小写混合的域名

建议补充的边界：
- 通配符域名（`*.example.com`）的匹配行为
- 国际化域名（IDN）处理
- 超长域名列表的性能
