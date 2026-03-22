# skill_dependencies_tests.rs 研究文档

## 场景与职责

`skill_dependencies_tests.rs` 是 `codex-rs/core/src/mcp/skill_dependencies.rs` 模块的单元测试文件，负责验证 Skill MCP 依赖管理的核心逻辑，特别是规范键（Canonical Key）匹配系统和依赖去重机制。这些测试确保 Skill 声明的 MCP 依赖能够正确识别已安装的服务器，即使它们使用不同的别名。

### 核心职责
1. **规范键匹配测试**：验证按 URL/Command 而非名称匹配已安装服务器的逻辑
2. **依赖去重测试**：验证相同底层服务器的多个别名只安装一次
3. **边界场景覆盖**：测试空依赖、重复依赖等边界情况

---

## 功能点目的

### 1. 规范键匹配测试 (`collect_missing_respects_canonical_installed_key`)

**目的**：验证依赖检测使用规范键（transport + identifier）而非服务器名称进行匹配。

**业务场景**：
- 用户已安装名为 "alias" 的 MCP 服务器，指向 `https://example.com/mcp`
- Skill 声明依赖名为 "github" 的 MCP 服务器，同样指向 `https://example.com/mcp`
- 期望：识别为同一服务器，不提示安装

**测试意义**：允许用户使用自定义名称配置 MCP 服务器，同时仍能使用依赖相同端点的 Skill。

### 2. 依赖去重测试 (`collect_missing_dedupes_by_canonical_key_but_preserves_original_name`)

**目的**：验证多个 Skill 或同一 Skill 中声明的相同服务器（不同别名）只安装一次。

**业务场景**：
- Skill A 声明依赖 "alias-one" → `https://example.com/one`
- Skill B 声明依赖 "alias-two" → `https://example.com/one`（相同 URL）
- 期望：只安装一次，使用第一个遇到的名称（"alias-one"）

**测试意义**：避免重复安装相同的 MCP 服务器，减少用户干扰和配置冗余。

---

## 具体技术实现

### 测试辅助函数

```rust
// 创建包含工具依赖的 Skill 元数据
fn skill_with_tools(tools: Vec<SkillToolDependency>) -> SkillMetadata {
    SkillMetadata {
        name: "skill".to_string(),
        description: "skill".to_string(),
        short_description: None,
        interface: None,
        dependencies: Some(SkillDependencies { tools }),
        policy: None,
        permission_profile: None,
        managed_network_override: None,
        path_to_skills_md: PathBuf::from("skill"),
        scope: SkillScope::User,
    }
}
```

### 测试用例详解

#### 1. 规范键匹配测试

```rust
#[test]
fn collect_missing_respects_canonical_installed_key() {
    // 已安装的服务器配置
    let url = "https://example.com/mcp".to_string();
    let skills = vec![skill_with_tools(vec![SkillToolDependency {
        r#type: "mcp".to_string(),
        value: "github".to_string(),      // Skill 中声明的名称
        description: None,
        transport: Some("streamable_http".to_string()),
        command: None,
        url: Some(url.clone()),
    }])];
    
    // 用户配置的服务器，使用不同名称但相同 URL
    let installed = HashMap::from([(
        "alias".to_string(),  // 用户自定义名称
        McpServerConfig {
            transport: McpServerTransportConfig::StreamableHttp {
                url,  // 相同的 URL
                bearer_token_env_var: None,
                http_headers: None,
                env_http_headers: None,
            },
            enabled: true,
            required: false,
            disabled_reason: None,
            startup_timeout_sec: None,
            tool_timeout_sec: None,
            enabled_tools: None,
            disabled_tools: None,
            scopes: None,
            oauth_resource: None,
        },
    )]);

    // 验证：虽然名称不同（github vs alias），但 URL 相同，不应视为缺失
    assert_eq!(
        collect_missing_mcp_dependencies(&skills, &installed),
        HashMap::new()  // 空结果表示没有缺失的依赖
    );
}
```

**测试逻辑**：
1. 创建 Skill，声明依赖 "github" 服务器，URL 为 `https://example.com/mcp`
2. 创建已安装服务器映射，键为 "alias"，URL 相同
3. 调用 `collect_missing_mcp_dependencies`
4. 验证返回空映射（无缺失依赖）

**关键断言**：
- 规范键生成：`mcp__streamable_http__https://example.com/mcp`
- 安装检测：通过规范键匹配，而非服务器名称

#### 2. 依赖去重测试

```rust
#[test]
fn collect_missing_dedupes_by_canonical_key_but_preserves_original_name() {
    let url = "https://example.com/one".to_string();
    
    // 同一 Skill 声明两个依赖，指向相同 URL
    let skills = vec![skill_with_tools(vec![
        SkillToolDependency {
            r#type: "mcp".to_string(),
            value: "alias-one".to_string(),  // 第一个名称
            description: None,
            transport: Some("streamable_http".to_string()),
            command: None,
            url: Some(url.clone()),
        },
        SkillToolDependency {
            r#type: "mcp".to_string(),
            value: "alias-two".to_string(),  // 第二个名称（相同 URL）
            description: None,
            transport: Some("streamable_http".to_string()),
            command: None,
            url: Some(url.clone()),
        },
    ])];

    // 期望结果：只保留第一个名称
    let expected = HashMap::from([(
        "alias-one".to_string(),  // 使用第一个遇到的名称
        McpServerConfig {
            transport: McpServerTransportConfig::StreamableHttp {
                url,
                bearer_token_env_var: None,
                http_headers: None,
                env_http_headers: None,
            },
            enabled: true,
            required: false,
            disabled_reason: None,
            startup_timeout_sec: None,
            tool_timeout_sec: None,
            enabled_tools: None,
            disabled_tools: None,
            scopes: None,
            oauth_resource: None,
        },
    )]);

    // 验证：虽然声明了两个依赖，但只返回一个（去重）
    assert_eq!(
        collect_missing_mcp_dependencies(&skills, &HashMap::new()),
        expected
    );
}
```

**测试逻辑**：
1. 创建 Skill，声明两个 MCP 依赖，URL 相同但名称不同
2. 调用 `collect_missing_mcp_dependencies`，传入空的已安装映射
3. 验证返回结果只包含一个服务器配置
4. 验证使用第一个遇到的名称（"alias-one"）

**关键断言**：
- 去重机制：`seen_canonical_keys` HashSet 确保同一规范键只处理一次
- 名称保留：使用第一个遇到的 `tool.value` 作为服务器名称

---

## 关键代码路径与文件引用

### 被测试代码路径

| 测试函数 | 被测试代码 | 所在文件 |
|---------|-----------|---------|
| `collect_missing_respects_canonical_installed_key` | `collect_missing_mcp_dependencies` | `skill_dependencies.rs:349-404` |
| `collect_missing_dedupes_by_canonical_key_but_preserves_original_name` | `collect_missing_mcp_dependencies` | `skill_dependencies.rs:349-404` |

### 规范键相关代码

```rust
// skill_dependencies.rs:310-328

// 基础规范键生成
fn canonical_mcp_key(transport: &str, identifier: &str, fallback: &str) -> String {
    let identifier = identifier.trim();
    if identifier.is_empty() {
        fallback.to_string()
    } else {
        format!("mcp__{transport}__{identifier}")
    }
}

// 从已安装配置生成规范键
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

### 依赖收集核心逻辑

```rust
// skill_dependencies.rs:349-404

pub(crate) fn collect_missing_mcp_dependencies(
    mentioned_skills: &[SkillMetadata],
    installed: &HashMap<String, McpServerConfig>,
) -> HashMap<String, McpServerConfig> {
    let mut missing = HashMap::new();
    
    // 1. 构建已安装服务器的规范键集合
    let installed_keys: HashSet<String> = installed
        .iter()
        .map(|(name, config)| canonical_mcp_server_key(name, config))
        .collect();
    
    // 2. 追踪已处理的依赖（去重）
    let mut seen_canonical_keys = HashSet::new();

    for skill in mentioned_skills {
        let Some(dependencies) = skill.dependencies.as_ref() else { continue };

        for tool in &dependencies.tools {
            // 3. 只处理 MCP 类型依赖
            if !tool.r#type.eq_ignore_ascii_case("mcp") { continue; }
            
            // 4. 生成依赖的规范键
            let dependency_key = match canonical_mcp_dependency_key(tool) {
                Ok(key) => key,
                Err(err) => { warn!(...); continue; }
            };
            
            // 5. 检查是否已安装或已处理
            if installed_keys.contains(&dependency_key)
                || seen_canonical_keys.contains(&dependency_key)
            {
                continue;
            }

            // 6. 转换为服务器配置
            let config = match mcp_dependency_to_server_config(tool) {
                Ok(config) => config,
                Err(err) => { warn!(...); continue; }
            };

            // 7. 记录为缺失依赖
            missing.insert(tool.value.clone(), config);
            seen_canonical_keys.insert(dependency_key);
        }
    }

    missing
}
```

---

## 依赖与外部交互

### 测试依赖类型

```rust
// 被测试模块
use super::*;

// Skill 模型
use crate::skills::model::SkillDependencies;
use codex_protocol::protocol::SkillScope;

// 测试工具
use pretty_assertions::assert_eq;
use std::path::PathBuf;
```

### 与 Skill 模型的关系

```rust
// 测试使用的 Skill 结构
SkillMetadata {
    name: String,
    description: String,
    dependencies: Option<SkillDependencies>,  // 测试重点
    scope: SkillScope,  // 测试中使用 SkillScope::User
    // ...
}

SkillDependencies {
    tools: Vec<SkillToolDependency>,  // 测试重点
}

SkillToolDependency {
    r#type: String,      // 测试中设置为 "mcp"
    value: String,       // 测试中作为服务器名称
    transport: Option<String>,  // 测试中设置为 "streamable_http"
    url: Option<String>, // 测试中作为匹配依据
    command: Option<String>,  // stdio 类型使用
    // ...
}
```

### 与配置类型的关系

```rust
// 测试中构建的期望结果
McpServerConfig {
    transport: McpServerTransportConfig::StreamableHttp {
        url: String,  // 测试中作为匹配依据
        bearer_token_env_var: None,
        http_headers: None,
        env_http_headers: None,
    },
    enabled: true,   // 测试中硬编码
    required: false, // 测试中硬编码
    // ... 其他字段为 None
}
```

---

## 风险、边界与改进建议

### 当前测试覆盖评估

| 测试场景 | 覆盖度 | 说明 |
|---------|-------|------|
| 规范键匹配（streamable_http） | ✅ 完整 | URL 匹配逻辑覆盖 |
| 依赖去重 | ✅ 完整 | 相同 URL 不同名称场景 |
| stdio 传输类型 | ❌ 缺失 | 未测试 command 匹配 |
| 混合传输类型 | ❌ 缺失 | 未测试 http + stdio 混合 |
| 错误处理 | ❌ 缺失 | 未测试无效依赖处理 |
| 空依赖 | ❌ 缺失 | 未测试空 tools 列表 |
| 多 Skill 依赖 | ❌ 缺失 | 未测试多个 Skill 的依赖合并 |

### 缺失测试场景

1. **stdio 传输类型测试**
   ```rust
   #[test]
   fn collect_missing_handles_stdio_transport() {
       let skills = vec![skill_with_tools(vec![SkillToolDependency {
           r#type: "mcp".to_string(),
           value: "local-tool".to_string(),
           transport: Some("stdio".to_string()),
           command: Some("/usr/local/bin/mcp-server".to_string()),
           url: None,
       }])];
       
       let installed = HashMap::from([(
           "my-alias".to_string(),
           McpServerConfig {
               transport: McpServerTransportConfig::Stdio {
                   command: "/usr/local/bin/mcp-server".to_string(),
                   // ...
               },
               // ...
           },
       )]);
       
       assert_eq!(
           collect_missing_mcp_dependencies(&skills, &installed),
           HashMap::new()
       );
   }
   ```

2. **无效依赖处理测试**
   ```rust
   #[test]
   fn collect_missing_skips_invalid_dependencies() {
       let skills = vec![skill_with_tools(vec![
           SkillToolDependency {
               r#type: "mcp".to_string(),
               value: "invalid".to_string(),
               transport: Some("streamable_http".to_string()),
               url: None,  // 缺少必需的 URL
               // ...
           },
           SkillToolDependency {
               r#type: "mcp".to_string(),
               value: "valid".to_string(),
               transport: Some("streamable_http".to_string()),
               url: Some("https://valid.example/mcp".to_string()),
               // ...
           },
       ])];
       
       let missing = collect_missing_mcp_dependencies(&skills, &HashMap::new());
       
       // 验证：无效依赖被跳过，有效依赖被保留
       assert!(!missing.contains_key("invalid"));
       assert!(missing.contains_key("valid"));
   }
   ```

3. **多 Skill 依赖合并测试**
   ```rust
   #[test]
   fn collect_missing_merges_dependencies_from_multiple_skills() {
       let skills = vec![
           skill_with_tools(vec![/* skill1 的依赖 */]),
           skill_with_tools(vec![/* skill2 的依赖 */]),
       ];
       
       // 验证：来自不同 Skill 的依赖被正确合并
       // 验证：重复的依赖被去重
   }
   ```

4. **边界值测试**
   ```rust
   #[test]
   fn collect_missing_handles_empty_inputs() {
       // 空 Skill 列表
       assert_eq!(
           collect_missing_mcp_dependencies(&[], &HashMap::new()),
           HashMap::new()
       );
       
       // Skill 无依赖
       assert_eq!(
           collect_missing_mcp_dependencies(&[skill_with_tools(vec![])], &HashMap::new()),
           HashMap::new()
       );
   }
   ```

### 改进建议

1. **参数化测试**
   ```rust
   // 使用 test_case 减少重复
   #[test_case("streamable_http", "https://example.com/mcp", None)]
   #[test_case("stdio", None, Some("/bin/mcp-server"))]
   fn collect_missing_respects_canonical_key(
       transport: &str,
       url: Option<&str>,
       command: Option<&str>,
   ) {
       // 通用测试逻辑
   }
   ```

2. **快照测试**
   ```rust
   // 对复杂配置使用 insta 快照
   #[test]
   fn collect_missing_produces_expected_config() {
       let missing = collect_missing_mcp_dependencies(...);
       insta::assert_debug_snapshot!(missing);
   }
   ```

3. **属性测试（Property-based Testing）**
   ```rust
   // 使用 proptest 验证属性
   proptest! {
       #[test]
       fn collect_missing_never_returns_installed(
           installed in arbitrary_mcp_servers(),
           skills in arbitrary_skills(),
       ) {
           let missing = collect_missing_mcp_dependencies(&skills, &installed);
           for (name, config) in &missing {
               assert!(!is_installed(name, config, &installed));
           }
       }
   }
   ```

### 潜在风险

1. **测试数据与实现耦合**
   - 测试直接构造 `McpServerConfig`，如果结构变更需要同步更新
   - **建议**：使用构建器模式或工厂函数

2. **硬编码字符串**
   - "mcp", "streamable_http" 等字符串在多处重复
   - **建议**：使用常量或枚举

3. **忽略警告路径**
   - 测试只覆盖成功路径，警告/错误路径未验证
   - **建议**：增加对 `warn!` 日志的断言（可使用 `tracing-test`）

4. **平台相关路径**
   - `PathBuf::from("skill")` 在 Windows 上行为可能不同
   - **建议**：使用 `PathBuf::from_iter` 或临时目录
