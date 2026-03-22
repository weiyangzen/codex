# openai-docs Skill 深度研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 定位

`openai-docs` 是 Codex CLI 内置的系统级 Skill（位于 `codex-rs/skills/src/assets/samples/openai-docs`），属于 **Codex Skills 体系** 中的预装示例 Skill。它作为**官方 OpenAI 文档查询助手**，专门处理用户关于 OpenAI 产品、API、模型选择和升级指导的询问。

### 核心职责

1. **官方文档查询**：通过 OpenAI Developer Docs MCP 服务器提供权威、最新的官方文档访问
2. **模型选择指导**：帮助用户根据用例选择最适合的 OpenAI 模型
3. **GPT-5.4 升级支持**：提供模型升级指导和提示词迁移建议
4. **MCP 工具集成**：演示 Skill 如何声明和依赖外部 MCP 服务器

### 使用场景

| 场景类型 | 触发条件 | 处理方式 |
|---------|---------|---------|
| 通用文档查询 | 用户询问 OpenAI API/产品使用方法 | 调用 MCP 搜索/获取文档 |
| 模型选择 | 用户询问"应该用什么模型" | 加载 `latest-model.md` 参考 |
| GPT-5.4 升级 | 用户明确请求升级指导 | 加载 `upgrading-to-gpt-5p4.md` |
| 提示词升级 | 复杂工作流需要提示词调整 | 加载 `gpt-5p4-prompting-guide.md` |

---

## 功能点目的

### 1. 渐进式信息披露架构

该 Skill 遵循 Codex Skills 的**三级加载系统**：

```
┌─────────────────────────────────────────────────────────────┐
│  Level 1: Metadata (YAML Frontmatter)                        │
│  - name: "openai-docs"                                       │
│  - description: 触发条件描述 (~100 words)                     │
│  - 始终存在于上下文中                                         │
├─────────────────────────────────────────────────────────────┤
│  Level 2: SKILL.md Body                                      │
│  - 使用指南、工作流程、质量规则                               │
│  - Skill 触发后加载 (<5k words)                              │
├─────────────────────────────────────────────────────────────┤
│  Level 3: Bundled References                                 │
│  - references/latest-model.md                               │
│  - references/upgrading-to-gpt-5p4.md                       │
│  - references/gpt-5p4-prompting-guide.md                    │
│  - 按需加载 (unlimited)                                      │
└─────────────────────────────────────────────────────────────┘
```

### 2. MCP 依赖声明与自动安装

该 Skill 是 **MCP 工具依赖** 的示例实现：

```yaml
# agents/openai.yaml
dependencies:
  tools:
    - type: "mcp"
      value: "openaiDeveloperDocs"
      description: "OpenAI Developer Docs MCP server"
      transport: "streamable_http"
      url: "https://developers.openai.com/mcp"
```

当 Skill 被触发时，系统会：
1. 检查 MCP 服务器是否已安装
2. 如未安装，提示用户安装（或通过 `SkillMcpDependencyInstall` 功能自动安装）
3. 安装后自动进行 OAuth 认证流程

### 3. 参考文档映射

| 参考文件 | 用途 | 加载时机 |
|---------|------|---------|
| `latest-model.md` | 模型选择建议表 | 模型选择请求 |
| `upgrading-to-gpt-5p4.md` | GPT-5.4 升级工作流 | 明确升级请求 |
| `gpt-5p4-prompting-guide.md` | 提示词迁移模式 | 复杂升级场景 |

---

## 具体技术实现

### 1. Skill 文件结构

```
codex-rs/skills/src/assets/samples/openai-docs/
├── SKILL.md                          # 主技能定义（YAML Frontmatter + Markdown）
├── agents/
│   └── openai.yaml                   # UI 元数据和 MCP 依赖声明
├── assets/
│   ├── openai-small.svg              # UI 小图标
│   └── openai.png                    # UI 大图标
├── references/
│   ├── latest-model.md               # 模型选择参考
│   ├── upgrading-to-gpt-5p4.md       # 升级指导参考
│   └── gpt-5p4-prompting-guide.md    # 提示词迁移参考
└── LICENSE.txt                       # Apache 2.0 许可证
```

### 2. YAML Frontmatter 结构

```yaml
---
name: "openai-docs"
description: "Use when the user asks how to build with OpenAI products or APIs..."
---
```

**关键字段说明**（由 `codex-rs/core/src/skills/loader.rs` 解析）：

| 字段 | 必填 | 用途 | 长度限制 |
|-----|------|------|---------|
| `name` | 是 | Skill 标识符 | 64 字符 |
| `description` | 是 | 触发条件描述 | 1024 字符 |
| `metadata.short-description` | 否 | 简短描述 | 1024 字符 |

### 3. agents/openai.yaml 结构

```yaml
interface:
  display_name: "OpenAI Docs"                    # UI 显示名称
  short_description: "Reference official OpenAI docs..."
  icon_small: "./assets/openai-small.svg"        # 相对 assets 路径
  icon_large: "./assets/openai.png"
  default_prompt: "Look up official OpenAI docs..."

dependencies:
  tools:
    - type: "mcp"                                 # 工具类型: mcp
      value: "openaiDeveloperDocs"                # MCP 服务器标识
      description: "OpenAI Developer Docs MCP server"
      transport: "streamable_http"                # 传输方式
      url: "https://developers.openai.com/mcp"    # MCP 服务器 URL
```

### 4. MCP 依赖解析流程

```rust
// codex-rs/core/src/skills/loader.rs
fn resolve_dependencies(dependencies: Option<Dependencies>) -> Option<SkillDependencies> {
    let dependencies = dependencies?;
    let tools: Vec<SkillToolDependency> = dependencies
        .tools
        .into_iter()
        .filter_map(resolve_dependency_tool)
        .collect();
    // ...
}

fn resolve_dependency_tool(tool: DependencyTool) -> Option<SkillToolDependency> {
    let r#type = resolve_required_str(tool.kind, ...)?;  // "mcp"
    let value = resolve_required_str(tool.value, ...)?;  // "openaiDeveloperDocs"
    let transport = resolve_str(tool.transport, ...);    // "streamable_http"
    let url = resolve_str(tool.url, ...);                // MCP URL
    // ...
}
```

### 5. MCP 依赖自动安装机制

```rust
// codex-rs/core/src/mcp/skill_dependencies.rs
pub(crate) async fn maybe_prompt_and_install_mcp_dependencies(
    sess: &Session,
    turn_context: &TurnContext,
    cancellation_token: &CancellationToken,
    mentioned_skills: &[SkillMetadata],
) {
    // 1. 收集缺失的 MCP 依赖
    let missing = collect_missing_mcp_dependencies(mentioned_skills, &installed);
    
    // 2. 过滤已提示过的依赖
    let unprompted_missing = filter_prompted_mcp_dependencies(sess, &missing).await;
    
    // 3. 询问用户是否安装
    if should_install_mcp_dependencies(...).await {
        maybe_install_mcp_dependencies(...).await;
    }
}
```

### 6. 指纹缓存机制

系统 Skills 通过指纹机制避免不必要的重复安装：

```rust
// codex-rs/skills/src/lib.rs
fn embedded_system_skills_fingerprint() -> String {
    let mut items = Vec::new();
    collect_fingerprint_items(&SYSTEM_SKILLS_DIR, &mut items);
    items.sort_unstable_by(|(a, _), (b, _)| a.cmp(b));

    let mut hasher = DefaultHasher::new();
    SYSTEM_SKILLS_MARKER_SALT.hash(&mut hasher);  // "v1"
    for (path, contents_hash) in items {
        path.hash(&mut hasher);
        contents_hash.hash(&mut hasher);
    }
    format!("{:x}", hasher.finish())
}
```

---

## 关键代码路径与文件引用

### 核心代码路径

| 路径 | 职责 |
|-----|------|
| `codex-rs/skills/src/lib.rs` | 系统 Skills 安装与指纹缓存 |
| `codex-rs/skills/build.rs` | 构建时监控 Skill 文件变更 |
| `codex-rs/core/src/skills/loader.rs` | Skill 文件解析与元数据加载 |
| `codex-rs/core/src/skills/manager.rs` | Skills 生命周期管理 |
| `codex-rs/core/src/skills/model.rs` | Skill 数据结构定义 |
| `codex-rs/core/src/skills/system.rs` | 系统 Skills 安装/卸载 |
| `codex-rs/core/src/mcp/skill_dependencies.rs` | MCP 依赖自动安装 |
| `codex-rs/protocol/src/protocol.rs` | Skill 相关协议定义 |

### 数据流

```
用户询问 OpenAI 相关话题
        │
        ▼
┌───────────────────┐
│  Skill 触发判断    │ ← 基于 name + description 匹配
└───────────────────┘
        │
        ▼
┌───────────────────┐
│  加载 SKILL.md    │ ← 解析 YAML Frontmatter + Markdown Body
└───────────────────┘
        │
        ▼
┌───────────────────┐
│  检查 MCP 依赖    │ ← 读取 agents/openai.yaml dependencies
└───────────────────┘
        │
        ├── 已安装 ──→ 直接使用 MCP 工具
        │
        └── 未安装 ──→ 提示/自动安装 ──→ OAuth 认证
        │
        ▼
┌───────────────────┐
│  按需加载 References │ ← latest-model.md / upgrading-to-gpt-5p4.md
└───────────────────┘
        │
        ▼
┌───────────────────┐
│  调用 MCP 工具    │ ← mcp__openaiDeveloperDocs__search_openai_docs
└───────────────────┘
```

### 协议定义

```rust
// codex-rs/protocol/src/protocol.rs
#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema, TS, PartialEq, Eq)]
pub struct SkillToolDependency {
    #[serde(rename = "type")]
    #[ts(rename = "type")]
    pub r#type: String,              // "mcp"
    pub value: String,               // "openaiDeveloperDocs"
    pub description: Option<String>,
    pub transport: Option<String>,   // "streamable_http"
    pub command: Option<String>,     // stdio 类型使用
    pub url: Option<String>,         // streamable_http URL
}

#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema, TS, PartialEq, Eq)]
pub struct SkillDependencies {
    pub tools: Vec<SkillToolDependency>,
}
```

---

## 依赖与外部交互

### 内部依赖

| 依赖 | 用途 |
|-----|------|
| `codex-skills` crate | 系统 Skills 安装与管理 |
| `codex-core` crate | Skill 加载、MCP 依赖处理 |
| `codex-protocol` crate | Skill 数据结构协议定义 |
| `include_dir` | 编译时嵌入 Skill 文件 |

### 外部依赖

| 依赖 | 类型 | 用途 |
|-----|------|------|
| OpenAI Developer Docs MCP | MCP 服务器 | 官方文档查询 |
| `https://developers.openai.com/mcp` | HTTP Endpoint | MCP Streamable HTTP 传输 |

### MCP 工具接口

该 Skill 依赖的 MCP 工具（由 OpenAI Developer Docs MCP 提供）：

```
mcp__openaiDeveloperDocs__search_openai_docs   # 搜索文档
mcp__openaiDeveloperDocs__fetch_openai_doc     # 获取具体页面
mcp__openaiDeveloperDocs__list_openai_docs     # 列出可用页面
```

### 安装命令

```bash
# 手动安装 MCP 服务器（Skill 中提到的安装方式）
codex mcp add openaiDeveloperDocs --url https://developers.openai.com/mcp
```

---

## 风险、边界与改进建议

### 已知风险

1. **MCP 服务可用性依赖**
   - 风险：OpenAI Developer Docs MCP 服务不可用时，Skill 功能受限
   - 缓解：SKILL.md 中定义了降级策略（fallback 到 web search）

2. **参考文档时效性**
   - 风险：`references/*.md` 中的模型信息可能过时
   - 缓解：SKILL.md 明确要求"verify against current OpenAI docs"

3. **OAuth 认证失败**
   - 风险：MCP 服务器 OAuth 流程可能因权限/沙箱限制失败
   - 缓解：支持权限升级重试和手动安装指引

### 边界限制

| 限制项 | 说明 |
|-------|------|
| 第一方客户端限制 | MCP 依赖自动安装仅支持第一方客户端 (`is_first_party_originator`) |
| 功能开关控制 | `SkillMcpDependencyInstall` 功能标志控制是否启用自动安装 |
| 传输方式限制 | 仅支持 `streamable_http` 和 `stdio` 两种 MCP 传输 |
| 作用域限制 | 作为 System Skill，优先级低于 User/Repo 级别的同名 Skill |

### 改进建议

1. **参考文档版本化**
   - 当前：静态 markdown 文件
   - 建议：添加版本元数据，与 OpenAI API 版本同步

2. **缓存机制增强**
   - 当前：每次查询实时调用 MCP
   - 建议：对不频繁变更的文档内容添加本地缓存

3. **多语言支持**
   - 当前：仅英文文档
   - 建议：根据用户 locale 加载对应语言参考

4. **提示词模板化**
   - 当前：内联在 SKILL.md 中
   - 建议：将常见查询模式抽取为可复用模板

5. **测试覆盖**
   - 当前：无针对该 Skill 的专项测试
   - 建议：添加 Skill 触发测试、MCP 依赖解析测试

### 相关测试位置

```
codex-rs/core/src/mcp/skill_dependencies_tests.rs    # MCP 依赖安装测试
codex-rs/core/src/skills/loader_tests.rs             # Skill 加载测试
codex-rs/skills/src/lib.rs (tests module)            # 指纹缓存测试
```

---

## 附录：Skill 元数据完整提取

### SKILL.md Frontmatter

```yaml
name: "openai-docs"
description: "Use when the user asks how to build with OpenAI products or APIs and needs up-to-date official documentation with citations, help choosing the latest model for a use case, or explicit GPT-5.4 upgrade and prompt-upgrade guidance; prioritize OpenAI docs MCP tools, use bundled references only as helper context, and restrict any fallback browsing to official OpenAI domains."
```

### agents/openai.yaml 完整内容

```yaml
interface:
  display_name: "OpenAI Docs"
  short_description: "Reference official OpenAI docs, including upgrade guidance"
  icon_small: "./assets/openai-small.svg"
  icon_large: "./assets/openai.png"
  default_prompt: "Look up official OpenAI docs, load relevant GPT-5.4 upgrade references when applicable, and answer with concise, cited guidance."

dependencies:
  tools:
    - type: "mcp"
      value: "openaiDeveloperDocs"
      description: "OpenAI Developer Docs MCP server"
      transport: "streamable_http"
      url: "https://developers.openai.com/mcp"
```

### 模型映射表（来自 latest-model.md）

| Model ID | Use Case |
|---------|----------|
| `gpt-5.4` | Default text plus reasoning |
| `gpt-5.4-pro` | Maximum reasoning/quality |
| `gpt-5-mini` | Cheaper/faster reasoning |
| `gpt-5-nano` | High-throughput simple tasks |
| `gpt-5.3-codex` | Agentic coding workflows |
| `gpt-image-1.5` | Best image generation |
| `gpt-realtime-1.5` | Realtime voice sessions |
| `text-embedding-3-large` | Higher-quality embeddings |

---

*文档生成时间：2026-03-22*
*研究范围：codex-rs/skills/src/assets/samples/openai-docs 及其上下文依赖*
