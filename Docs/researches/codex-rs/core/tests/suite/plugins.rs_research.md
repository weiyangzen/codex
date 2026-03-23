# plugins.rs 研究文档

## 场景与职责

`plugins.rs` 是 Codex Core 的集成测试套件，专门测试 **Plugins（插件系统）** 功能。该功能允许用户安装和启用第三方插件，扩展 Codex 的能力，包括：

- **Skills**: 插件提供的 SKILL.md 文件，增强 AI 的上下文知识
- **MCP Servers**: 插件提供的 Model Context Protocol 服务器，暴露额外工具
- **Apps**: 插件提供的应用连接器（如 Google Calendar）

插件系统的设计目标是创建一个可扩展的生态系统，同时保持安全性和用户控制。

## 功能点目的

### 1. 插件能力渲染验证
测试确认插件的能力（skills、MCP、apps）是否正确渲染到开发者消息中，按正确顺序（Apps → Skills → Plugins）呈现。

### 2. 显式插件提及处理
当用户通过 `@plugin://` 语法显式提及插件时，系统应：
- 注入插件特定的指导信息
- 使插件的工具对该轮对话可见
- 在工具描述中添加插件来源标记

### 3. 插件使用分析
验证插件使用时是否正确发送分析事件（`codex_plugin_used`），包含：
- 插件 ID、名称、市场来源
- 能力使用情况（skills、MCP、apps）
- 模型和会话元数据

### 4. MCP 工具列表
验证插件提供的 MCP 工具是否正确注册和可发现。

## 具体技术实现

### 插件目录结构

```
CODEX_HOME/
├── plugins/
│   └── cache/
│       └── {marketplace}/
│           └── {plugin_name}/
│               └── local/
│                   ├── .codex-plugin/
│                   │   └── plugin.json       # 插件清单
│                   ├── .mcp.json             # MCP 配置（可选）
│                   ├── .app.json             # 应用配置（可选）
│                   └── skills/
│                       └── {skill-name}/
│                           └── SKILL.md      # 技能定义
└── config.toml
```

### 测试插件创建

```rust
// 创建示例插件
fn write_sample_plugin_manifest_and_config(home: &TempDir) -> std::path::PathBuf {
    let plugin_root = home.path().join("plugins/cache/test/sample/local");
    
    // 创建清单文件
    std::fs::write(
        plugin_root.join(".codex-plugin/plugin.json"),
        r#"{"name":"sample","description":"inspect sample data"}"#
    );
    
    // 启用插件
    std::fs::write(
        home.path().join("config.toml"),
        "[features]\nplugins = true\n\n[plugins.\"sample@test\"]\nenabled = true\n"
    );
}

// 添加技能
fn write_plugin_skill_plugin(home: &TempDir) -> std::path::PathBuf {
    let skill_dir = plugin_root.join("skills/sample-search");
    std::fs::write(
        skill_dir.join("SKILL.md"),
        "---\ndescription: inspect sample data\n---\n\n# body\n"
    );
}

// 添加 MCP 配置
fn write_plugin_mcp_plugin(home: &TempDir, command: &str) {
    std::fs::write(
        plugin_root.join(".mcp.json"),
        format!(r#"{{"mcpServers": {{"sample": {{"command": "{}"}}}}}}"#, command)
    );
}
```

### 核心测试流程

#### 1. 能力分区顺序测试

```rust
async fn capability_sections_render_in_developer_message_in_order() {
    // 设置：启用 Apps 功能，创建包含 skills 和 apps 的插件
    // 触发：发送用户输入
    // 验证：开发者消息中 Apps → Skills → Plugins 的顺序
    // 验证：插件名称和描述正确显示
    // 验证：技能命名指导（plugin_name:skill-name）存在
}
```

#### 2. 显式提及测试

```rust
async fn explicit_plugin_mentions_inject_plugin_guidance() {
    // 设置：创建包含 skills、MCP、apps 的插件
    // 触发：发送 UserInput::Mention { path: "plugin://sample@test" }
    // 验证：
    // - 开发者消息包含 "Skills from this plugin"
    // - 开发者消息包含 "MCP servers from this plugin"
    // - 开发者消息包含 "Apps from this plugin"
    // - 请求工具列表包含插件 MCP 工具
    // - 工具描述包含 "This tool is part of plugin `sample`."
}
```

#### 3. 分析事件测试

```rust
async fn explicit_plugin_mentions_track_plugin_used_analytics() {
    // 触发：显式提及插件
    // 验证：发送到 /codex/analytics-events/events 的请求包含：
    // {
    //   "event_type": "codex_plugin_used",
    //   "event_params": {
    //     "plugin_id": "sample@test",
    //     "plugin_name": "sample",
    //     "marketplace_name": "test",
    //     "has_skills": true,
    //     "mcp_server_count": 0,
    //     "connector_ids": [],
    //     ...
    //   }
    // }
}
```

### 关键断言模式

```rust
// 验证工具名称
fn tool_names(body: &serde_json::Value) -> Vec<String> {
    body.get("tools")
        .and_then(serde_json::Value::as_array)
        .map(|tools| {
            tools.iter()
                .filter_map(|tool| {
                    tool.get("name")
                        .or_else(|| tool.get("type"))
                        .and_then(serde_json::Value::as_str)
                        .map(str::to_string)
                })
                .collect()
        })
        .unwrap_or_default()
}

// 验证工具描述
fn tool_description(body: &serde_json::Value, tool_name: &str) -> Option<String> {
    // 在 tools 数组中查找指定工具的描述
}
```

## 依赖与外部交互

### 功能标志

```rust
Feature::Plugins        // 主插件功能开关
Feature::Apps           // 应用连接器功能（测试中使用）
```

### 核心模块依赖

| 模块 | 用途 |
|-----|------|
| `codex_core::plugins::*` | 插件管理器、清单解析、渲染 |
| `codex_core::features::Feature` | 功能标志检查 |
| `codex_protocol::protocol::Op::UserInput` | 用户输入操作 |
| `codex_protocol::user_input::UserInput::Mention` | 插件提及 |

### 插件系统架构

```
codex-rs/core/src/plugins/
├── mod.rs              # 模块导出
├── manager.rs          # PluginsManager - 插件生命周期管理
├── manifest.rs         # 插件清单解析
├── store.rs            # 插件存储（安装/卸载）
├── marketplace.rs      # 市场接口
├── render.rs           # 插件能力渲染到开发者消息
├── injection.rs        # 插件内容注入逻辑
├── toggles.rs          # 插件启用/禁用状态
└── ...
```

### 测试辅助工具

```rust
// Apps 测试服务器
core_test_support::apps_test_server::AppsTestServer

// 测试用 MCP stdio 服务器二进制文件
core_test_support::stdio_server_bin()

// 测试 Codex 构建器
core_test_support::test_codex::test_codex()
```

## 风险、边界与改进建议

### 已知边界

1. **平台限制**: 测试文件顶部有 `#![cfg(not(target_os = "windows"))]`，Windows 平台跳过这些测试。

2. **MCP 服务器启动时间**: `plugin_mcp_tools_are_listed` 测试使用 30 秒超时等待 MCP 工具就绪，这在慢速系统上可能不稳定。

3. **测试二进制依赖**: `explicit_plugin_mentions_track_plugin_used_analytics` 依赖 `test_stdio_server` 二进制文件，如果不存在则跳过。

### 安全考虑

1. **插件代码执行**: MCP 服务器通过外部进程执行，存在潜在安全风险。

2. **权限边界**: 测试中使用 `SandboxPolicy::new_read_only_policy()`，但生产环境需要更细粒度的权限控制。

### 改进建议

1. **并行测试优化**: 当前测试使用 `worker_threads = 2`，可以考虑增加以加速测试。

2. **Mock MCP 服务器**: 使用真正的 MCP 服务器二进制文件增加了测试复杂度，考虑使用纯 Mock 实现。

3. **插件隔离测试**: 添加测试验证多个插件同时启用时的隔离性。

4. **插件更新流程**: 当前测试覆盖安装和启用，但缺少插件更新流程的测试。

5. **错误处理**: 添加测试验证插件加载失败时的优雅降级行为。

### 相关文件引用

- 测试文件: `codex-rs/core/tests/suite/plugins.rs` (441 行)
- 插件管理器: `codex-rs/core/src/plugins/manager.rs`
- 插件渲染: `codex-rs/core/src/plugins/render.rs`
- 插件注入: `codex-rs/core/src/plugins/injection.rs`
- 功能定义: `codex-rs/core/src/features.rs` (第 744-749 行)
- 测试支持: `codex-rs/core/src/plugins/test_support.rs`
