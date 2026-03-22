# NetworkProxySpec 研究文档

## 场景与职责

`NetworkProxySpec` 是 Codex 核心配置模块中的网络代理规范组件，负责将用户配置、管理约束和沙箱策略整合为统一的网络代理配置。它作为网络代理的"配置中枢"，在以下场景中发挥作用：

1. **沙箱化网络访问**：在受限沙箱模式（ReadOnly/WorkspaceWrite）下，控制哪些域名可以访问
2. **企业/托管环境**：支持托管策略（managed requirements）对网络访问的严格限制
3. **动态策略调整**：允许执行策略（exec policy）在运行时修改网络规则
4. **审计与合规**：传递审计元数据到网络代理层，用于日志记录

## 功能点目的

### 1. 配置整合与约束应用 (`from_config_and_constraints`)
将三种输入源整合为统一的代理配置：
- **基础配置** (`NetworkProxyConfig`)：用户定义的代理设置
- **管理约束** (`NetworkConstraints`)：来自 MDM/云端的强制要求
- **沙箱策略** (`SandboxPolicy`)：当前会话的安全级别

### 2. 域名列表管理
- **Allowlist（允许列表）**：控制哪些域名可以访问
- **Denylist（拒绝列表）**：明确禁止访问的域名
- **列表合并策略**：用户配置与管理配置的合并逻辑

### 3. 托管模式支持 (`managed_allowed_domains_only`)
当启用此模式时：
- 仅允许访问托管策略明确列出的域名
- 用户自定义的允许列表被忽略
- 未匹配的请求将被硬拒绝（hard deny）

### 4. 执行策略集成 (`with_exec_policy_network_rules`)
允许执行策略在运行时动态添加网络规则，用于：
- 临时允许特定域名访问
- 根据代码审查结果动态调整网络权限

### 5. 代理启动 (`start_proxy`)
根据配置启动网络代理，支持：
- 策略决策器（Policy Decider）注入
- 被阻止请求观察器（Blocked Request Observer）
- 网络审批流程（Network Approval Flow）

## 具体技术实现

### 关键数据结构

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetworkProxySpec {
    config: NetworkProxyConfig,           // 实际代理配置
    constraints: NetworkProxyConstraints, // 应用的约束记录
    hard_deny_allowlist_misses: bool,     // 是否硬拒绝未匹配请求
}

pub struct StartedNetworkProxy {
    proxy: NetworkProxy,
    _handle: NetworkProxyHandle,  // 保持代理运行的句柄
}
```

### 配置合并流程

```
用户配置 + 管理约束 + 沙箱策略
        ↓
apply_requirements()
        ↓
┌─────────────────────────────────────────────────────────┐
│ 1. 检查 allowlist_expansion_enabled                     │
│    - ReadOnly/WorkspaceWrite 模式: 允许扩展             │
│    - DangerFullAccess 模式: 不允许扩展                  │
│    - managed_allowed_domains_only: 不允许扩展           │
│                                                         │
│ 2. 合并域名列表                                         │
│    - 托管列表作为基线                                   │
│    - 如允许扩展，追加用户配置中不重复的域名             │
│    - 如不允许扩展，仅使用托管列表                       │
│                                                         │
│ 3. 应用其他约束                                         │
│    - enabled, proxy_url, socks_url                      │
│    - allow_upstream_proxy                               │
│    - allow_unix_sockets, allow_local_binding            │
└─────────────────────────────────────────────────────────┘
        ↓
validate_policy_against_constraints()  // 验证配置有效性
```

### 列表合并算法

```rust
fn merge_domain_lists(mut managed: Vec<String>, user_entries: &[String]) -> Vec<String> {
    for entry in user_entries {
        // 大小写不敏感比较，避免重复
        if !managed.iter().any(|e| e.eq_ignore_ascii_case(entry)) {
            managed.push(entry.clone());
        }
    }
    managed
}
```

### 执行策略规则应用

```rust
fn apply_exec_policy_network_rules(config: &mut NetworkProxyConfig, exec_policy: &Policy) {
    let (allowed_domains, denied_domains) = exec_policy.compiled_network_domains();
    
    // 添加到允许列表，同时从拒绝列表中移除
    upsert_network_domains(
        &mut config.network.allowed_domains,
        &mut config.network.denied_domains,
        allowed_domains,
    );
    
    // 添加到拒绝列表，同时从允许列表中移除（拒绝优先）
    upsert_network_domains(
        &mut config.network.denied_domains,
        &mut config.network.allowed_domains,
        denied_domains,
    );
}
```

### 静态配置重载器

```rust
struct StaticNetworkProxyReloader {
    state: ConfigState,
}

#[async_trait]
impl ConfigReloader for StaticNetworkProxyReloader {
    async fn maybe_reload(&self) -> anyhow::Result<Option<ConfigState>> {
        Ok(None)  // 静态配置，永不自动重载
    }
    
    async fn reload_now(&self) -> anyhow::Result<ConfigState> {
        Ok(self.state.clone())  // 返回当前状态
    }
}
```

## 关键代码路径与文件引用

### 本文件核心函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `from_config_and_constraints` | 87-116 | 主入口：从配置和约束创建 Spec |
| `apply_requirements` | 188-264 | 应用管理约束到配置 |
| `start_proxy` | 118-155 | 启动网络代理 |
| `with_exec_policy_network_rules` | 157-170 | 应用执行策略网络规则 |
| `build_state_with_audit_metadata` | 172-186 | 构建带审计元数据的状态 |
| `merge_domain_lists` | 287-297 | 合并域名列表 |
| `apply_exec_policy_network_rules` | 300-312 | 应用执行策略规则 |
| `upsert_network_domains` | 314-333 | 更新域名列表（去重+移除冲突） |

### 调用方

| 文件 | 调用点 | 用途 |
|------|--------|------|
| `codex-rs/core/src/config/mod.rs` | `ConfigBuilder` 构建流程 | 创建网络代理配置 |
| `codex-rs/core/src/codex.rs` | 会话初始化 | 启动网络代理 |
| `codex-rs/core/src/guardian/review_session.rs` | 审查会话 | 应用执行策略规则 |
| `codex-rs/tui/src/debug_config.rs` | 调试输出 | 显示代理配置 |

### 被调用方/依赖

| 模块 | 来源 | 用途 |
|------|------|------|
| `codex_network_proxy` | 外部 crate | 网络代理核心实现 |
| `codex_execpolicy::Policy` | 外部 crate | 执行策略规则 |
| `codex_protocol::protocol::SandboxPolicy` | 协议 crate | 沙箱策略枚举 |
| `NetworkConstraints` | `config_loader` | 管理约束定义 |

## 依赖与外部交互

### 外部 Crate 依赖

```rust
// 网络代理核心
use codex_network_proxy::{
    NetworkProxy, NetworkProxyConfig, NetworkProxyConstraints,
    NetworkProxyHandle, NetworkProxyState, NetworkPolicyDecider,
    BlockedRequestObserver, NetworkDecision, ConfigReloader,
    ConfigState, build_config_state, host_and_port_from_network_addr,
    normalize_host, validate_policy_against_constraints,
};

// 执行策略
use codex_execpolicy::Policy;

// 协议定义
use codex_protocol::protocol::SandboxPolicy;
```

### 配置层交互

```
┌─────────────────────────────────────────────────────────────┐
│                    ConfigLayerStack                          │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐ │
│  │  MDM/System │ │  User Config │ │  Project (.codex/)      │ │
│  │  (最高优先级)│ │              │ │                         │ │
│  └─────────────┘ └─────────────┘ └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│              NetworkProxySpec::from_config_and_constraints   │
│                    (本文件核心逻辑)                          │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│              NetworkProxy::builder()...build()               │
│                    (codex-network-proxy)                     │
└─────────────────────────────────────────────────────────────┘
```

## 风险、边界与改进建议

### 已知风险

1. **硬拒绝模式绕过风险**
   - `hard_deny_allowlist_misses` 仅在 `managed_allowed_domains_only` 时启用
   - 如果沙箱策略判断错误，可能导致安全策略被绕过
   - 代码位置：`from_config_and_constraints` 第 92-94 行

2. **域名大小写敏感性问题**
   - 合并列表时使用 `eq_ignore_ascii_case` 进行大小写不敏感比较
   - 但实际代理层可能使用不同的比较逻辑，导致不一致

3. **静态重载器限制**
   - `StaticNetworkProxyReloader` 永不自动重载配置
   - 长时间运行的会话无法动态响应配置变更

### 边界情况

1. **空托管列表 + managed_allowed_domains_only**
   - 结果：允许列表为空，所有请求被拒绝
   - 测试覆盖：`managed_allowed_domains_only_without_managed_allowlist_blocks_all_user_domains`

2. **DangerFullAccess 模式**
   - 忽略用户扩展，仅使用托管基线
   - 测试覆盖：`danger_full_access_keeps_managed_allowlist_and_denylist_fixed`

3. **执行策略规则冲突**
   - 同时存在于允许和拒绝列表的域名，拒绝优先
   - 通过 `upsert_network_domains` 实现

### 改进建议

1. **配置热重载支持**
   ```rust
   // 建议：实现动态重载器
   struct DynamicNetworkProxyReloader {
       config_path: PathBuf,
       last_modified: SystemTime,
   }
   ```

2. **更细粒度的审计**
   - 当前仅传递静态审计元数据
   - 建议：记录每次策略决策的上下文

3. **域名规范化增强**
   - 当前仅使用 `normalize_host` 进行基础规范化
   - 建议：增加 IDN (国际化域名) 支持

4. **测试覆盖**
   - 增加对 `with_exec_policy_network_rules` 的单元测试
   - 增加对 SOCKS5 配置的测试

### 相关测试文件

- `network_proxy_spec_tests.rs`：本文件的单元测试
- `codex-rs/core/src/config/config_tests.rs`：集成测试
- `codex-rs/core/src/codex_tests.rs`：端到端测试
