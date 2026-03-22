# skill_dependencies.rs 研究文档

## 场景与职责

`skill_dependencies.rs` 是 Codex 项目中 MCP 模块的 Skill 依赖管理子模块，负责处理 Skill（技能）声明的 MCP 服务器依赖的自动检测、提示安装和配置持久化。它是连接 Skill 系统与 MCP 系统的桥梁，实现了"使用 Skill 时自动安装所需 MCP 服务器"的用户体验。

### 核心职责
1. **依赖检测**：分析 Skill 声明的 MCP 依赖，检测哪些尚未安装
2. **用户提示**：在适当时候询问用户是否安装缺失的 MCP 服务器
3. **自动安装**：将缺失的 MCP 服务器添加到全局配置
4. **OAuth 登录**：为新安装的 MCP 服务器执行 OAuth 认证流程
5. **服务器刷新**：安装完成后刷新 MCP 连接管理器

---

## 功能点目的

### 1. Skill MCP 依赖检测 (`collect_missing_mcp_dependencies`)

**目的**：识别用户提到的 Skill 中声明但尚未安装的 MCP 服务器。

**关键逻辑**：
- 解析 Skill 的 `dependencies.tools` 字段
- 筛选 `type == "mcp"` 的工具依赖
- 使用规范键（canonical key）匹配已安装服务器
- 支持 `streamable_http` 和 `stdio` 两种传输类型

### 2. 用户提示决策 (`should_install_mcp_dependencies`)

**目的**：根据当前执行模式决定是否提示用户，以及以何种方式提示。

**决策逻辑**：
- **Full Access 模式**：直接安装，不提示用户
- **其他模式**：显示交互式提示，让用户选择安装或跳过

### 3. 依赖安装流程 (`maybe_install_mcp_dependencies`)

**目的**：将缺失的 MCP 服务器持久化到全局配置，并执行必要的认证。

**执行步骤**：
1. 加载全局 MCP 服务器配置
2. 添加缺失的服务器配置
3. 持久化到配置文件
4. 对每个新服务器执行 OAuth 登录（如需要）
5. 刷新 MCP 连接管理器

### 4. OAuth 登录与重试

**目的**：处理 MCP 服务器的 OAuth 认证，包括 Scope 协商和错误重试。

**重试策略**：
- 首次尝试使用解析后的 Scope
- 如果失败且 Scope 来源为 `Discovered`，则尝试无 Scope 登录
- 记录失败日志但不阻塞其他服务器

---

## 具体技术实现

### 关键数据结构

```rust
// Skill 工具依赖（来自 skills/model.rs）
pub struct SkillToolDependency {
    pub r#type: String,      // "mcp" 或其他类型
    pub value: String,       // 依赖标识（如服务器名）
    pub description: Option<String>,
    pub transport: Option<String>,  // "streamable_http" 或 "stdio"
    pub command: Option<String>,    // stdio 类型使用
    pub url: Option<String>,        // streamable_http 类型使用
}

// Skill 依赖集合
pub struct SkillDependencies {
    pub tools: Vec<SkillToolDependency>,
}

// Skill 元数据
pub struct SkillMetadata {
    pub name: String,
    pub description: String,
    pub dependencies: Option<SkillDependencies>,
    // ... 其他字段
}
```

### 规范键（Canonical Key）系统

用于唯一标识 MCP 服务器，支持别名匹配：

```rust
// 格式: mcp__<transport>__<identifier>
fn canonical_mcp_key(transport: &str, identifier: &str, fallback: &str) -> String {
    let identifier = identifier.trim();
    if identifier.is_empty() {
        fallback.to_string()
    } else {
        format!("mcp__{transport}__{identifier}")
    }
}

// 从配置生成规范键
fn canonical_mcp_server_key(name: &str, config: &McpServerConfig) -> String {
    match &config.transport {
        McpServerTransportConfig::Stdio { command, .. } => {
            canonical_mcp_key("stdio", command, name)
        }
        McpServerTransportConfig::StreamableHttp { url, .. } => {
            canonical_mcp_key("streamable_http", url, name)
        }
    }
}

// 从 Skill 依赖生成规范键
fn canonical_mcp_dependency_key(dependency: &SkillToolDependency) -> Result<String, String> {
    let transport = dependency.transport.as_deref().unwrap_or("streamable_http");
    if transport.eq_ignore_ascii_case("streamable_http") {
        let url = dependency.url.as_ref()
            .ok_or_else(|| "missing url for streamable_http dependency".to_string())?;
        return Ok(canonical_mcp_key("streamable_http", url, &dependency.value));
    }
    if transport.eq_ignore_ascii_case("stdio") {
        let command = dependency.command.as_ref()
            .ok_or_else(|| "missing command for stdio dependency".to_string())?;
        return Ok(canonical_mcp_key("stdio", command, &dependency.value));
    }
    Err(format!("unsupported transport {transport}"))
}
```

### 关键流程

#### 1. 依赖检测流程
```
collect_missing_mcp_dependencies(mentioned_skills, installed)
  ├── 构建已安装服务器的规范键集合
  ├── 遍历每个 Skill 的 dependencies.tools
  │   ├── 筛选 type == "mcp"
  │   ├── 生成依赖的规范键
  │   ├── 检查是否已安装（按规范键匹配）
  │   └── 生成 McpServerConfig
  └── 返回缺失服务器映射
```

#### 2. 用户提示流程
```
should_install_mcp_dependencies(sess, turn_context, missing, cancellation_token)
  ├── 检查是否为 Full Access 模式
  │   └── 是 → 直接返回 true
  └── 构建并发送 RequestUserInput
      ├── 等待用户响应
      ├── 处理取消信号
      └── 记录已提示的依赖（避免重复提示）
```

#### 3. 安装流程
```
maybe_install_mcp_dependencies(sess, turn_context, config, mentioned_skills)
  ├── 检查 Feature::SkillMcpDependencyInstall 是否启用
  ├── 加载全局 MCP 服务器配置
  ├── 添加缺失的服务器
  ├── 持久化配置（ConfigEditsBuilder）
  ├── 对每个新服务器执行 OAuth 登录
  │   ├── 探测 OAuth 支持
  │   ├── 解析 Scope
  │   ├── 执行 perform_oauth_login
  │   └── 失败时尝试无 Scope 重试
  └── 刷新 MCP 连接管理器
```

### 用户提示常量

```rust
const SKILL_MCP_DEPENDENCY_PROMPT_ID: &str = "skill_mcp_dependency_install";
const MCP_DEPENDENCY_OPTION_INSTALL: &str = "Install";
const MCP_DEPENDENCY_OPTION_SKIP: &str = "Continue anyway";
```

---

## 关键代码路径与文件引用

### 模块结构

```
codex-rs/core/src/mcp/
├── mod.rs
├── auth.rs                    # OAuth 相关
│   ├── oauth_login_support()
│   ├── resolve_oauth_scopes()
│   └── should_retry_without_scopes()
├── skill_dependencies.rs      # 本文件
│   ├── maybe_prompt_and_install_mcp_dependencies()  # 主入口
│   ├── maybe_install_mcp_dependencies()
│   ├── should_install_mcp_dependencies()
│   ├── collect_missing_mcp_dependencies()
│   └── canonical_mcp_*_key()  # 规范键函数
└── skill_dependencies_tests.rs # 测试
```

### 调用关系

```
maybe_prompt_and_install_mcp_dependencies (主入口)
├── 检查 is_first_party_originator (仅支持第一方客户端)
├── 检查 Feature::SkillMcpDependencyInstall
├── sess.services.mcp_manager.configured_servers()
├── collect_missing_mcp_dependencies()
├── filter_prompted_mcp_dependencies() (避免重复提示)
├── should_install_mcp_dependencies()
│   ├── is_full_access_mode()
│   └── sess.request_user_input() (用户交互)
└── maybe_install_mcp_dependencies()
    ├── load_global_mcp_servers()
    ├── ConfigEditsBuilder::replace_mcp_servers()
    ├── oauth_login_support() (来自 auth.rs)
    ├── resolve_oauth_scopes() (来自 auth.rs)
    ├── perform_oauth_login() (来自 codex_rmcp_client)
    ├── should_retry_without_scopes() (来自 auth.rs)
    └── sess.refresh_mcp_servers_now()
```

### 依赖的外部模块

| 模块 | 功能 |
|------|------|
| `crate::codex::Session` | 会话管理、用户输入请求、后台事件通知 |
| `crate::codex::TurnContext` | 当前回合上下文（策略、配置等） |
| `crate::config::Config` | 配置访问 |
| `crate::config::edit::ConfigEditsBuilder` | 配置持久化 |
| `crate::config::load_global_mcp_servers` | 加载全局 MCP 配置 |
| `crate::default_client::is_first_party_originator` | 第一方客户端检测 |
| `crate::features::Feature` | 特性开关 |
| `crate::skills::SkillMetadata` | Skill 元数据 |
| `crate::skills::model::SkillToolDependency` | Skill 工具依赖 |
| `codex_protocol::request_user_input::*` | 用户输入请求协议 |
| `codex_rmcp_client::perform_oauth_login` | OAuth 登录执行 |

---

## 依赖与外部交互

### 与 Skill 系统的交互

```rust
// 从 Skill 元数据提取 MCP 依赖
for skill in mentioned_skills {
    let Some(dependencies) = skill.dependencies.as_ref() else { continue };
    for tool in &dependencies.tools {
        if !tool.r#type.eq_ignore_ascii_case("mcp") { continue; }
        // 处理 MCP 依赖...
    }
}
```

### 与 MCP 管理器的交互

```rust
// 获取已配置的服务器
let installed = sess.services.mcp_manager.configured_servers(config);

// 刷新服务器连接
sess.refresh_mcp_servers_now(turn_context, refresh_servers, store_mode).await;
```

### 与用户交互系统的交互

```rust
// 构建用户提示
let question = RequestUserInputQuestion {
    id: SKILL_MCP_DEPENDENCY_PROMPT_ID.to_string(),
    header: "Install MCP servers?".to_string(),
    question: format!("The following MCP servers are required... {server_list}"),
    options: Some(vec![
        RequestUserInputQuestionOption {
            label: MCP_DEPENDENCY_OPTION_INSTALL.to_string(),
            description: "Install and enable...".to_string(),
        },
        RequestUserInputQuestionOption {
            label: MCP_DEPENDENCY_OPTION_SKIP.to_string(),
            description: "Skip installation...".to_string(),
        },
    ]),
};

// 发送请求并等待响应
let response_fut = sess.request_user_input(turn_context, call_id, args);
let response = tokio::select! {
    biased;
    _ = cancellation_token.cancelled() => { /* 处理取消 */ }
    response = response_fut => response,
};
```

### 与 OAuth 系统的交互

```rust
// 探测 OAuth 支持
let oauth_config = match oauth_login_support(&server_config.transport).await {
    McpOAuthLoginSupport::Supported(config) => config,
    McpOAuthLoginSupport::Unsupported => continue,
    McpOAuthLoginSupport::Unknown(err) => { warn!(...); continue; }
};

// 解析 Scope
let resolved_scopes = resolve_oauth_scopes(
    /*explicit_scopes*/ None,
    server_config.scopes.clone(),
    oauth_config.discovered_scopes.clone(),
);

// 执行登录
let first_attempt = perform_oauth_login(
    &name, &oauth_config.url, store_mode,
    oauth_config.http_headers.clone(),
    oauth_config.env_http_headers.clone(),
    &resolved_scopes.scopes,
    server_config.oauth_resource.as_deref(),
    config.mcp_oauth_callback_port,
    config.mcp_oauth_callback_url.as_deref(),
).await;
```

---

## 风险、边界与改进建议

### 已知风险

1. **第一方客户端限制**
   ```rust
   if !is_first_party_originator(originator_value.as_str()) {
       // Only support first-party clients for now.
       return;
   }
   ```
   - 第三方客户端无法使用 Skill MCP 依赖自动安装功能
   - **建议**：评估是否开放给第三方，或提供替代方案

2. **OAuth 登录失败处理**
   - 登录失败仅记录警告，不影响其他服务器
   - 用户可能不知道某些服务器认证失败
   - **建议**：向用户展示失败的认证尝试

3. **重复提示机制局限**
   ```rust
   async fn filter_prompted_mcp_dependencies(...) -> HashMap<String, McpServerConfig> {
       let prompted = sess.mcp_dependency_prompted().await;
       // ...
   }
   ```
   - 仅基于会话级别的去重
   - 重启后会再次提示
   - **建议**：考虑持久化用户跳过选择

4. **Full Access 模式自动安装**
   ```rust
   fn is_full_access_mode(turn_context: &TurnContext) -> bool {
       matches!(turn_context.approval_policy.value(), AskForApproval::Never)
           && matches!(turn_context.sandbox_policy.get(), 
               SandboxPolicy::DangerFullAccess | SandboxPolicy::ExternalSandbox { .. })
   }
   ```
   - 在 Full Access 模式下自动安装，用户无感知
   - 可能安装用户不期望的服务器

### 边界情况

| 场景 | 当前行为 | 评估 |
|------|---------|------|
| Skill 依赖格式错误 | 记录警告，跳过该依赖 | ✅ 合理 |
| 不支持的传输类型 | 返回错误，跳过 | ✅ 合理 |
| 全局配置加载失败 | 记录警告，中止安装 | ⚠️ 可考虑降级处理 |
| OAuth 登录超时 | 记录警告，继续其他 | ✅ 合理 |
| 配置持久化失败 | 记录警告，已添加的服务器不生效 | ⚠️ 不一致状态 |
| 所有服务器已提示过 | 直接返回，无提示 | ✅ 合理 |

### 改进建议

1. **增强错误报告**
   ```rust
   // 建议：收集安装结果并报告
   struct McpDependencyInstallResult {
       server_name: String,
       status: InstallStatus,  // Success | AlreadyInstalled | Failed(Error)
   }
   
   // 向用户展示摘要
   sess.notify_background_event(turn_context, format!(
       "MCP dependencies installed: {success}/{total}"
   )).await;
   ```

2. **支持依赖版本约束**
   ```rust
   // SkillToolDependency 扩展
   pub struct SkillToolDependency {
       // ... 现有字段
       pub min_version: Option<String>,
       pub max_version: Option<String>,
   }
   ```

3. **批量 OAuth 登录优化**
   ```rust
   // 建议：并行执行独立的 OAuth 登录
   let login_futures: Vec<_> = added.iter().map(|(name, config)| {
       async move { (name.clone(), perform_oauth_login(...).await) }
   }).collect();
   let results = futures::future::join_all(login_futures).await;
   ```

4. **配置变更预览**
   ```rust
   // 建议：在安装前向用户展示将要添加的服务器
   let preview = format!("Will install: {}", 
       added.iter().map(|(n, _)| n).join(", "));
   ```

5. **回滚机制**
   ```rust
   // 建议：如果后续服务器安装失败，提供回滚选项
   if let Err(e) = perform_oauth_login(...) {
       // 提供 "Remove installed servers" 选项
   }
   ```

6. **Scope 验证**
   ```rust
   // 建议：在登录前验证 Scope 格式
   for scope in &resolved_scopes.scopes {
       if !is_valid_scope(scope) {
           warn!("Invalid scope format: {}", scope);
       }
   }
   ```

### 测试覆盖

当前测试（`skill_dependencies_tests.rs`）：
- ✅ 规范键匹配逻辑
- ✅ 重复依赖去重

建议补充：
- OAuth 登录成功/失败路径
- 用户提示交互流程
- 配置持久化验证
- 取消信号处理
- Full Access 模式自动安装
