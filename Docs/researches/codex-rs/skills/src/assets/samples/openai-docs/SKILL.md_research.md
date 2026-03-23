# SKILL.md 研究文档

## 文件基本信息

- **文件路径**: `codex-rs/skills/src/assets/samples/openai-docs/SKILL.md`
- **文件大小**: 5,120 bytes
- **文件类型**: Markdown (Skill 定义文件)
- **所属 Skill**: openai-docs

---

## 场景与职责

### 1.1 文件定位

SKILL.md 是 **OpenAI Docs Skill** 的核心定义文件，属于 Codex CLI 的**系统内置 Skill**。它定义了 Skill 的元数据、功能描述、使用场景和工作流程。该 Skill 专门用于回答用户关于 OpenAI 产品、API 和文档的问题。

### 1.2 核心职责

1. **功能定义**: 定义 Skill 的名称、描述和用途
2. **触发条件**: 明确何时应该激活此 Skill
3. **工作流指导**: 提供使用 OpenAI 文档 MCP 服务器的详细步骤
4. **产品快照**: 列出主要 OpenAI 产品及其用途
5. **质量规则**: 定义回答质量和引用规范

### 1.3 在 Skill 系统中的角色

```
Skill 加载层级 (由高到低优先级):
┌─────────────────────────────────────┐
│  Repo Scope (.agents/skills/)       │  ← 项目级 Skill
├─────────────────────────────────────┤
│  User Scope (~/.agents/skills/)     │  ← 用户级 Skill
├─────────────────────────────────────┤
│  System Scope (.system/)            │  ← 本 Skill 所在层级
├─────────────────────────────────────┤
│  Admin Scope (/etc/codex/skills/)   │  ← 系统管理员 Skill
└─────────────────────────────────────┘

openai-docs 作为系统 Skill，位于 ~/.codex/skills/.system/openai-docs/
```

---

## 功能点目的

### 2.1 YAML Frontmatter

```yaml
---
name: "openai-docs"
description: "Use when the user asks how to build with OpenAI products or APIs..."
---
```

| 字段 | 值 | 用途 |
|------|-----|------|
| `name` | `openai-docs` | Skill 唯一标识符 |
| `description` | 长描述文本 | 帮助 AI 决定何时使用此 Skill |

### 2.2 触发条件分析

Skill 应在以下场景激活：

1. **OpenAI 产品/API 使用问题**
   - "如何使用 GPT-5.4?"
   - "Chat Completions API 怎么用?"

2. **模型选择建议**
   - "我应该用哪个模型?"
   - "gpt-5-mini 和 gpt-5.4 有什么区别?"

3. **GPT-5.4 升级指导**
   - "帮我升级到 GPT-5.4"
   - "迁移到 GPT-5.4 需要什么改动?"

4. **需要官方文档引用**
   - 用户需要权威、最新的 OpenAI 文档信息

### 2.3 核心功能模块

#### 2.3.1 MCP 工具集成

| 工具 | 用途 | 使用场景 |
|------|------|----------|
| `mcp__openaiDeveloperDocs__search_openai_docs` | 搜索文档 | 查找相关文档页面 |
| `mcp__openaiDeveloperDocs__fetch_openai_doc` | 获取文档内容 | 读取具体章节 |
| `mcp__openaiDeveloperDocs__list_openai_docs` | 列出文档 | 浏览可用页面 |

#### 2.3.2 参考文档映射

| 参考文件 | 用途 | 加载时机 |
|----------|------|----------|
| `references/latest-model.md` | 模型选择建议 | 模型选择请求 |
| `references/upgrading-to-gpt-5p4.md` | GPT-5.4 升级 | 显式升级请求 |
| `references/gpt-5p4-prompting-guide.md` | 提示词升级 | 需要提示词修改时 |

#### 2.3.3 OpenAI 产品快照

```
1. Apps SDK - ChatGPT 应用开发
2. Responses API - 有状态多模态交互
3. Chat Completions API - 对话生成
4. Codex - 编程助手
5. gpt-oss - 开源推理模型 (Apache 2.0)
6. Realtime API - 低延迟语音对话
7. Agents SDK - 智能体工具包
```

---

## 具体技术实现

### 3.1 文件解析流程

```rust
// codex-rs/core/src/skills/loader.rs

fn parse_skill_file(path: &Path, scope: SkillScope) -> Result<SkillMetadata, SkillParseError> {
    let contents = fs::read_to_string(path).map_err(SkillParseError::Read)?;
    
    // 1. 提取 YAML Frontmatter
    let frontmatter = extract_frontmatter(&contents)
        .ok_or(SkillParseError::MissingFrontmatter)?;
    
    // 2. 解析 Frontmatter
    let parsed: SkillFrontmatter = serde_yaml::from_str(&frontmatter)
        .map_err(SkillParseError::InvalidYaml)?;
    
    // 3. 构建 SkillMetadata
    Ok(SkillMetadata {
        name,
        description,
        short_description,
        interface,           // 从 agents/openai.yaml 加载
        dependencies,        // 从 agents/openai.yaml 加载
        policy,
        permission_profile,
        path_to_skills_md: resolved_path,
        scope,
    })
}
```

### 3.2 Frontmatter 提取逻辑

```rust
fn extract_frontmatter(contents: &str) -> Option<String> {
    let mut lines = contents.lines();
    
    // 必须以 --- 开头
    if !matches!(lines.next(), Some(line) if line.trim() == "---") {
        return None;
    }
    
    let mut frontmatter_lines: Vec<&str> = Vec::new();
    let mut found_closing = false;
    
    // 收集直到下一个 ---
    for line in lines.by_ref() {
        if line.trim() == "---" {
            found_closing = true;
            break;
        }
        frontmatter_lines.push(line);
    }
    
    // 必须非空且有闭合标记
    if frontmatter_lines.is_empty() || !found_closing {
        return None;
    }
    
    Some(frontmatter_lines.join("\n"))
}
```

### 3.3 元数据扩展加载

SKILL.md 的扩展元数据从 `agents/openai.yaml` 加载：

```yaml
# agents/openai.yaml
interface:
  display_name: "OpenAI Docs"
  short_description: "Reference official OpenAI docs..."
  icon_small: "./assets/openai-small.svg"
  icon_large: "./assets/openai.png"
  default_prompt: "Look up official OpenAI docs..."

dependencies:
  tools:
    - type: "mcp"
      value: "openaiDeveloperDocs"
      description: "OpenAI Developer Docs MCP server"
      transport: "streamable_http"
      url: "https://developers.openai.com/mcp"
```

### 3.4 依赖解析流程

```rust
fn resolve_dependencies(dependencies: Option<Dependencies>) -> Option<SkillDependencies> {
    let dependencies = dependencies?;
    let tools: Vec<SkillToolDependency> = dependencies
        .tools
        .into_iter()
        .filter_map(resolve_dependency_tool)
        .collect();
    
    if tools.is_empty() {
        None
    } else {
        Some(SkillDependencies { tools })
    }
}
```

### 3.5 MCP 依赖处理

```rust
// codex-rs/core/src/mcp/skill_dependencies.rs

pub fn mcp_server_configs_from_skill_dependencies(
    skills: &[SkillMetadata],
) -> Vec<McpServerConfig> {
    skills
        .iter()
        .filter_map(|skill| {
            skill.dependencies.as_ref().map(|deps| {
                deps.tools
                    .iter()
                    .filter(|tool| tool.r#type == "mcp")
                    .map(|tool| McpServerConfig {
                        name: tool.value.clone(),
                        transport: parse_transport(tool.transport.as_deref()),
                        command: tool.command.clone(),
                        url: tool.url.clone(),
                    })
                    .collect::<Vec<_>>()
            })
        })
        .flatten()
        .collect()
}
```

---

## 关键代码路径与文件引用

### 4.1 直接引用

| 文件 | 功能 | 说明 |
|------|------|------|
| `codex-rs/skills/src/lib.rs` | 系统 Skill 安装 | 通过 `include_dir!` 嵌入 |
| `codex-rs/core/src/skills/loader.rs` | Skill 文件解析 | 解析 SKILL.md 和元数据 |
| `codex-rs/core/src/skills/system.rs` | 系统 Skill 管理 | 安装和卸载系统 Skill |

### 4.2 相关文件

| 文件 | 关系 | 说明 |
|------|------|------|
| `agents/openai.yaml` | 元数据扩展 | 界面、依赖配置 |
| `assets/openai.png` | 资源文件 | 大图标 |
| `assets/openai-small.svg` | 资源文件 | 小图标 |
| `references/latest-model.md` | 参考文档 | 模型选择指南 |
| `references/upgrading-to-gpt-5p4.md` | 参考文档 | 升级指南 |
| `references/gpt-5p4-prompting-guide.md` | 参考文档 | 提示词指南 |

### 4.3 调用链

```
用户输入
    ↓
Codex::process_user_turn()
    ↓
SkillManager::get_relevant_skills()
    ↓
SkillLoader::load_skills_from_roots()
    ↓
parse_skill_file(SKILL.md)
    ↓
extract_frontmatter() → serde_yaml 解析
    ↓
load_skill_metadata() → 读取 agents/openai.yaml
    ↓
SkillMetadata 对象
    ↓
注入到系统提示词中
```

---

## 依赖与外部交互

### 5.1 内部依赖

```
codex-skills (crate)
    ├── codex-utils-absolute-path
    ├── include_dir
    └── thiserror

codex-core (crate)
    ├── codex-skills
    ├── serde_yaml (frontmatter 解析)
    ├── toml (metadata 解析)
    └── tracing (日志)
```

### 5.2 外部依赖

| 依赖 | 类型 | 说明 |
|------|------|------|
| OpenAI Developer Docs MCP | MCP Server | 文档查询服务 |
| developers.openai.com | Web | 官方文档源 |
| platform.openai.com | Web | 备用文档源 |

### 5.3 运行时交互

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│   Codex CLI     │────▶│  OpenAI Docs MCP │────▶│ developers.openai.com│
│                 │     │  Server          │     │                     │
│  openai-docs    │◄────│  (streamable_http)│◄────│                     │
│  Skill          │     │                  │     │                     │
└─────────────────┘     └──────────────────┘     └─────────────────────┘
         │
         ▼
┌─────────────────┐
│ references/     │
│ 本地参考文档     │
└─────────────────┘
```

---

## 风险、边界与改进建议

### 6.1 潜在风险

| 风险 | 严重程度 | 描述 | 缓解措施 |
|------|----------|------|----------|
| **MCP 服务不可用** | 高 | OpenAI MCP 服务故障或网络问题 | 提供 web 搜索降级方案 |
| **文档过时** | 中 | references/ 中的本地文档可能过期 | 定期同步，优先使用 MCP |
| **幻觉引用** | 中 | AI 可能编造文档引用 | 强制使用 MCP 工具获取准确内容 |
| **许可证冲突** | 低 | Apache 2.0 与某些许可证不兼容 | 确保整体项目许可证兼容 |

### 6.2 边界条件

#### 6.2.1 输入边界

| 边界 | 限制 | 处理 |
|------|------|------|
| Frontmatter 大小 | 无硬性限制 | 建议保持简洁 |
| Description 长度 | 1024 字符 (MAX_DESCRIPTION_LEN) | 超长会被截断 |
| Name 长度 | 64 字符 (MAX_NAME_LEN) | 超长报错 |
| 扫描深度 | 6 层 (MAX_SCAN_DEPTH) | 深层 Skill 不被发现 |
| 目录数量 | 2000 个 (MAX_SKILLS_DIRS_PER_ROOT) | 超出则截断扫描 |

#### 6.2.2 运行时边界

```rust
// 从 loader.rs
const MAX_SCAN_DEPTH: usize = 6;
const MAX_SKILLS_DIRS_PER_ROOT: usize = 2000;
const MAX_NAME_LEN: usize = 64;
const MAX_DESCRIPTION_LEN: usize = 1024;
```

### 6.3 改进建议

#### 6.3.1 功能增强

1. **动态文档更新**
   ```yaml
   # 建议添加到期机制
   metadata:
     expires_at: "2025-06-01"
     update_check_url: "https://developers.openai.com/api/skills/openai-docs/version"
   ```

2. **缓存机制**
   ```rust
   // 建议添加 MCP 响应缓存
   struct OpenAiDocsCache {
       entries: HashMap<String, (Instant, DocContent)>,
       ttl: Duration,
   }
   ```

3. **多语言支持**
   ```
   references/
   ├── en/
   │   ├── latest-model.md
   │   └── upgrading-to-gpt-5p4.md
   ├── zh/
   │   ├── latest-model.md
   │   └── upgrading-to-gpt-5p4.md
   ```

#### 6.3.2 可靠性改进

1. **MCP 健康检查**
   ```rust
   // 在 Skill 激活前检查 MCP 可用性
   async fn check_mcp_health(url: &str) -> Result<bool, Error> {
       // 发送健康检查请求
   }
   ```

2. **优雅降级**
   ```markdown
   ## If MCP server is missing (改进版)
   
   1. 尝试本地缓存查询
   2. 尝试 web 搜索 (限制在官方域名)
   3. 使用 references/ 中的静态文档
   4. 告知用户文档可能不是最新的
   ```

#### 6.3.3 监控与指标

```rust
// 建议添加的指标
struct OpenAiDocsMetrics {
    mcp_queries_total: Counter,
    mcp_errors_total: Counter,
    fallback_to_web_total: Counter,
    cache_hits_total: Counter,
    avg_response_time_ms: Histogram,
}
```

### 6.4 测试建议

| 测试类型 | 覆盖点 | 优先级 |
|----------|--------|--------|
| 单元测试 | Frontmatter 解析 | 高 |
| 集成测试 | MCP 工具调用链 | 高 |
| 端到端测试 | 完整问答流程 | 中 |
| 降级测试 | MCP 不可用场景 | 中 |
| 性能测试 | 大文档加载 | 低 |

---

## 附录：工作流程详解

### A.1 标准查询流程

```
用户: "如何使用 GPT-5.4?"
    ↓
1. 匹配 openai-docs Skill (description 匹配)
    ↓
2. 加载 references/latest-model.md
    ↓
3. 调用 mcp__openaiDeveloperDocs__search_openai_docs("GPT-5.4 usage")
    ↓
4. 获取结果，调用 mcp__openaiDeveloperDocs__fetch_openai_doc(结果 URL)
    ↓
5. 结合本地参考和 MCP 结果生成回答
    ↓
6. 引用文档来源
```

### A.2 GPT-5.4 升级流程

```
用户: "升级到 GPT-5.4"
    ↓
1. 匹配 openai-docs Skill
    ↓
2. 加载 references/upgrading-to-gpt-5p4.md
    ↓
3. 如需提示词修改，加载 references/gpt-5p4-prompting-guide.md
    ↓
4. 搜索当前 OpenAI 文档验证信息
    ↓
5. 执行升级工作流 (inventory → classify → recommend)
    ↓
6. 输出结构化建议
```

---

## 总结

SKILL.md 是 OpenAI Docs Skill 的核心定义文件，通过 YAML Frontmatter 定义 Skill 的基本信息，通过 Markdown 内容定义详细的使用指南和工作流程。它与 `agents/openai.yaml` 配合，共同构成完整的 Skill 定义。该 Skill 的设计体现了以下原则：

1. **权威性优先**: 优先使用 OpenAI 官方 MCP 文档服务
2. **本地辅助**: references/ 目录提供快速参考
3. **优雅降级**: MCP 不可用时提供备选方案
4. **质量保障**: 强制引用验证，避免幻觉
