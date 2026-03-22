# 研究文档：codex-rs/skills/src/assets/samples/openai-docs/references

## 目录结构概览

```
codex-rs/skills/src/assets/samples/openai-docs/references/
├── latest-model.md              # 模型选择参考指南
├── upgrading-to-gpt-5p4.md      # GPT-5.4 升级指南
└── gpt-5p4-prompting-guide.md   # GPT-5.4 提示词优化指南
```

---

## 1. 场景与职责

### 1.1 定位与目标

`references/` 目录是 **openai-docs Skill** 的核心参考文档集合，专门用于支持以下用户场景：

| 场景 | 目标用户 | 解决的问题 |
|------|----------|------------|
| **模型选择** | 需要选择合适 OpenAI 模型的开发者 | 提供模型能力对照表，帮助选择最优模型 |
| **模型升级** | 需要将现有集成升级到 GPT-5.4 的开发者 | 提供安全、窄范围的升级路径 |
| **提示词优化** | 需要针对 GPT-5.4 优化提示词的开发者 | 提供针对性的提示词模式和最佳实践 |

### 1.2 在 Skill 体系中的角色

```
openai-docs Skill 架构:
┌─────────────────────────────────────────────────────────┐
│  SKILL.md (主入口)                                       │
│  - 定义 Skill 元数据                                      │
│  - 描述使用场景和工作流程                                  │
│  - 声明 MCP 工具依赖                                      │
├─────────────────────────────────────────────────────────┤
│  agents/openai.yaml (接口定义)                           │
│  - 声明 MCP 工具依赖 (openaiDeveloperDocs)               │
├─────────────────────────────────────────────────────────┤
│  references/ (本研究目录)                                 │
│  - latest-model.md         → 模型选择决策支持             │
│  - upgrading-to-gpt-5p4.md → 升级流程指导                 │
│  - gpt-5p4-prompting-guide.md → 提示词工程指南            │
├─────────────────────────────────────────────────────────┤
│  assets/ (品牌资源)                                       │
│  - openai.png, openai-small.svg                          │
└─────────────────────────────────────────────────────────┘
```

### 1.3 调用触发条件

根据 `SKILL.md` 中的定义，这些参考文档在以下情况被加载：

1. **模型选择请求** → 加载 `references/latest-model.md`
2. **明确的 GPT-5.4 升级请求** → 加载 `references/upgrading-to-gpt-5p4.md`
3. **提示词升级需求**（研究密集型、工具密集型、编码导向、多智能体或长时运行工作流）→ 同时加载 `references/gpt-5p4-prompting-guide.md`

---

## 2. 功能点目的

### 2.1 latest-model.md — 模型选择参考

**核心功能**：提供 OpenAI 模型 ID 与使用场景的映射表

**内容结构**：
- **模型映射表**：18 种模型 ID 及其推荐使用场景
  - 文本+推理类：`gpt-5.4`, `gpt-5.4-pro`, `gpt-5-mini`, `gpt-5-nano`
  - 纯文本类（无推理）：`gpt-4.1-mini`, `gpt-4.1-nano`
  - 编码专用：`gpt-5.3-codex`, `gpt-5.1-codex-mini`
  - 图像生成：`gpt-image-1.5`, `gpt-image-1-mini`
  - 语音处理：`gpt-4o-mini-tts`, `gpt-4o-mini-transcribe`
  - 实时多模态：`gpt-realtime-1.5`, `gpt-realtime-mini`
  - 嵌入模型：`text-embedding-3-large`, `text-embedding-3-small`
  - 视频生成：`sora-2`, `sora-2-pro`
  - 内容审核：`omni-moderation-latest`

**关键约束**：
> "Every recommendation here must be verified against current OpenAI docs before it is repeated to a user."
> 
> "If this file conflicts with current docs, the docs win."

### 2.2 upgrading-to-gpt-5p4.md — 升级指南

**核心功能**：提供从旧模型迁移到 GPT-5.4 的标准化流程

**升级策略分类**：

| 升级类别 | 适用条件 | 操作范围 |
|----------|----------|----------|
| `model string only` | 提示词已简洁明确、任务边界清晰、非研究/工具密集型 | 仅替换模型字符串 |
| `model string + light prompt rewrite` | 旧提示词补偿弱指令跟随、需要更强完整性/引用/验证 | 替换模型字符串 + 1-2 个针对性提示词块 |
| `blocked` | 需要 API 表面变更、参数重写、工具定义变更 | 标记为阻塞，不进行升级 |

**关键流程**：
1. 清点当前模型使用情况
2. 将模型使用与提示词表面对应
3. 分类源模型家族（gpt-4o/gpt-4.1、o1/o3/o4-mini、早期 gpt-5、后期 gpt-5.x）
4. 决定升级类别
5. 运行无代码兼容性检查
6. 提供结构化建议

**输出要求**：
- 必须输出 `reasoning_effort_recommendation`
- 如果仓库暴露了当前推理设置，优先保留
- 否则使用源家族起始映射

### 2.3 gpt-5p4-prompting-guide.md — 提示词优化指南

**核心功能**：提供 GPT-5.4 特定的提示词模式和最佳实践

**行为差异说明**：

| GPT-5.4 优势 | 仍需提示词指导的场景 |
|--------------|---------------------|
| 更强的个性和语气遵循 | 检索密集型工作流 |
| 更好的长时程和智能体工作流耐力 | 研究和引用规范 |
| 更强的表格、财务和格式化任务 | 不可逆操作前的验证 |
| 更高效的工具选择 | 终端和工具工作流规范 |
| 更强的结构化生成可靠性 | 默认行为和隐含跟进 |
| | 输出冗长控制 |

**提示词块库（19 个可复用块）**：

1. `output_verbosity_spec` — 输出冗长度控制
2. `default_follow_through_policy` — 默许执行策略
3. `instruction_priority` — 指令优先级
4. `tool_persistence_rules` — 工具持久化规则
5. `dig_deeper_nudge` — 深入挖掘引导
6. `dependency_checks` — 依赖检查
7. `parallel_tool_calling` — 并行工具调用
8. `completeness_contract` — 完整性契约
9. `empty_result_handling` — 空结果处理
10. `verification_loop` — 验证循环
11. `missing_context_gating` — 缺失上下文门控
12. `action_safety` — 操作安全框架
13. `citation_rules` — 引用规则
14. `research_mode` — 研究模式
15. `structured_output_contract` — 结构化输出契约
16. `bbox_extraction_spec` — 边界框提取规范
17. `terminal_tool_hygiene` — 终端工具规范
18. `user_updates_spec` — 用户更新规范

**升级配置示例**：
- **长时程智能体**：`gpt-5.4` + `medium` 推理 + `tool_persistence_rules` + `completeness_contract` + `verification_loop`
- **研究工作流**：`gpt-5.4` + `medium` 推理 + `research_mode` + `citation_rules` + `empty_result_handling` + `tool_persistence_rules`
- **编码工作流**：`gpt-5.4` + `terminal_tool_hygiene` + `verification_loop` + `dependency_checks`

---

## 3. 具体技术实现

### 3.1 文件格式规范

所有参考文档遵循标准 Markdown 格式，使用 YAML Frontmatter：

```yaml
---
name: "openai-docs"
description: "Use when the user asks how to build with OpenAI products..."
---
```

### 3.2 嵌入与分发机制

参考文档作为 **系统 Skill** 的一部分，通过 `codex-skills` crate 嵌入到二进制中：

**嵌入流程**：
```rust
// codex-rs/skills/src/lib.rs
const SYSTEM_SKILLS_DIR: Dir = include_dir::include_dir!("$CARGO_MANIFEST_DIR/src/assets/samples");
```

**安装流程**：
```rust
pub fn install_system_skills(codex_home: &Path) -> Result<(), SystemSkillsError> {
    // 1. 计算嵌入目录的指纹
    let expected_fingerprint = embedded_system_skills_fingerprint();
    
    // 2. 检查标记文件，如果指纹匹配则跳过
    if marker_matches { return Ok(()); }
    
    // 3. 清理现有系统技能目录
    // 4. 写入嵌入目录到磁盘
    // 5. 写入标记文件
}
```

**目标路径**：`$CODEX_HOME/skills/.system/openai-docs/references/`

### 3.3 指纹计算机制

```rust
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

**用途**：避免不必要的文件写入，仅在 Skill 内容变更时重新安装。

### 3.4 Skill 加载与解析

**加载入口**：`codex-rs/core/src/skills/loader.rs`

```rust
pub(crate) fn load_skills_from_roots<I>(roots: I) -> SkillLoadOutcome
where
    I: IntoIterator<Item = SkillRoot>,
{
    // 1. 遍历所有 SkillRoot
    // 2. 发现每个根目录下的技能
    // 3. 去重（按路径）
    // 4. 排序（按作用域优先级 + 名称 + 路径）
}
```

**发现机制**：
- 扫描深度：最大 6 层 (`MAX_SCAN_DEPTH`)
- 目录限制：每根目录最多 2000 个技能目录 (`MAX_SKILLS_DIRS_PER_ROOT`)
- 符号链接：Repo/User/Admin 作用域跟随，System 作用域不跟随

**解析流程**：
1. 读取 `SKILL.md` 文件
2. 提取 YAML Frontmatter（`---` 包围）
3. 解析 `SkillFrontmatter` 结构
4. 加载元数据（`agents/openai.yaml`）
5. 验证字段长度限制
6. 构建 `SkillMetadata`

### 3.5 作用域与优先级

Skill 作用域优先级（从高到低）：

```rust
fn scope_rank(scope: SkillScope) -> u8 {
    match scope {
        SkillScope::Repo => 0,    // 最高优先级
        SkillScope::User => 1,
        SkillScope::System => 2,  // 本目录 Skill 的作用域
        SkillScope::Admin => 3,
    }
}
```

**系统 Skill 的特殊性**：
- 安装在 `$CODEX_HOME/skills/.system/` 下
- 作用域为 `SkillScope::System`
- 可通过配置 `skills.bundled.enabled = false` 禁用

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件引用图

```
codex-rs/skills/src/assets/samples/openai-docs/references/
│
├── latest-model.md ─────────────────────────────────────────────────┐
│   └─ 被加载时机：                                                    │
│      - codex-rs/core/src/skills/manager.rs:skills_for_config()      │
│      - 当用户请求涉及模型选择时                                       │
│                                                                      │
├── upgrading-to-gpt-5p4.md ─────────────────────────────────────────┤
│   └─ 被加载时机：                                                    │
│      - 当用户明确请求 GPT-5.4 升级时                                  │
│      - 由 LLM 根据 SKILL.md 工作流决定                               │
│                                                                      │
└── gpt-5p4-prompting-guide.md ──────────────────────────────────────┘
    └─ 被加载时机：
       - 当升级需要提示词变更时
       - 研究工作流、工具密集型工作流、编码工作流等

嵌入与加载链：
┌─────────────────────────────────────────────────────────────────────┐
│ codex-rs/skills/build.rs                                            │
│ └── 生成 cargo:rerun-if-changed 指令，监控 src/assets/samples 变更   │
├─────────────────────────────────────────────────────────────────────┤
│ codex-rs/skills/src/lib.rs                                          │
│ ├── SYSTEM_SKILLS_DIR: 嵌入目录常量                                  │
│ ├── install_system_skills(): 安装系统 Skill 到磁盘                   │
│ └── embedded_system_skills_fingerprint(): 计算内容指纹               │
├─────────────────────────────────────────────────────────────────────┤
│ codex-rs/core/src/skills/system.rs                                  │
│ ├── install_system_skills (re-export)                               │
│ └── uninstall_system_skills(): 清理系统 Skill                        │
├─────────────────────────────────────────────────────────────────────┤
│ codex-rs/core/src/skills/manager.rs                                 │
│ ├── SkillsManager::new(): 初始化时安装/卸载系统 Skill                │
│ └── bundled_skills_enabled_from_stack(): 检查是否启用捆绑 Skill      │
├─────────────────────────────────────────────────────────────────────┤
│ codex-rs/core/src/skills/loader.rs                                  │
│ ├── load_skills_from_roots(): 从根目录加载所有 Skill                 │
│ ├── discover_skills_under_root(): 发现技能目录                       │
│ └── parse_skill_file(): 解析 SKILL.md 文件                           │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.2 关键代码路径详解

**路径 1：Skill 初始化安装**

```rust
// codex-rs/core/src/skills/manager.rs:38-57
impl SkillsManager {
    pub fn new(codex_home: PathBuf, plugins_manager: Arc<PluginsManager>, bundled_skills_enabled: bool) -> Self {
        let manager = Self { ... };
        if !bundled_skills_enabled {
            uninstall_system_skills(&manager.codex_home);  // 清理
        } else if let Err(err) = install_system_skills(&manager.codex_home) {
            tracing::error!("failed to install system skills: {err}");  // 安装
        }
        manager
    }
}
```

**路径 2：Skill 根目录解析**

```rust
// codex-rs/core/src/skills/loader.rs:284-289
// 系统 Skill 根目录
roots.push(SkillRoot {
    path: system_cache_root_dir(config_folder.as_path()),  // $CODEX_HOME/skills/.system
    scope: SkillScope::System,
});
```

**路径 3：测试中的路径规范化**

```rust
// codex-rs/core/tests/common/context_snapshot.rs:335-343
// 系统 Skill 路径在测试快照中被规范化
static SYSTEM_SKILL_PATH_RE: OnceLock<Regex> = OnceLock::new();
let system_skill_path_re = SYSTEM_SKILL_PATH_RE.get_or_init(|| {
    Regex::new(r"/[^)\n]*/skills/\.system/([^/\n]+)/SKILL\.md").unwrap()
});
// 替换为: <SYSTEM_SKILLS_ROOT>/$1/SKILL.md
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 组件 | 依赖类型 | 说明 |
|------|----------|------|
| `codex-skills` crate | 宿主 | 提供嵌入和安装机制 |
| `codex-core` crate | 消费者 | 使用 Skill 进行提示词注入 |
| `include_dir` crate | 编译时 | 嵌入目录到二进制 |
| `codex-utils-absolute-path` | 工具 | 安全路径操作 |

### 5.2 外部依赖

| 依赖 | 类型 | 说明 |
|------|------|------|
| OpenAI Developer Docs MCP | 运行时 | 首选文档查询工具 |
| `developers.openai.com` | 网络 | MCP 不可用时回退 |
| `platform.openai.com` | 网络 | 备选官方文档源 |

### 5.3 MCP 工具声明

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

**MCP 工具使用优先级**：
1. `mcp__openaiDeveloperDocs__search_openai_docs` — 搜索文档
2. `mcp__openaiDeveloperDocs__fetch_openai_doc` — 获取具体页面
3. `mcp__openaiDeveloperDocs__list_openai_docs` — 浏览页面列表
4. Web 搜索（仅作为 MCP 失败时的回退）

### 5.4 配置交互

**启用/禁用系统 Skill**：

```toml
# config.toml
[skills.bundled]
enabled = true  # 或 false 以禁用
```

**配置检查路径**：
```rust
// codex-rs/core/src/skills/manager.rs:233-253
pub(crate) fn bundled_skills_enabled_from_stack(config_layer_stack: &ConfigLayerStack) -> bool {
    let effective_config = config_layer_stack.effective_config();
    let Some(skills_value) = effective_config.as_table().and_then(|t| t.get("skills"))
    else { return true; };  // 默认启用
    
    let skills: SkillsConfig = match skills_value.clone().try_into() {
        Ok(skills) => skills,
        Err(err) => { warn!("invalid skills config: {err}"); return true; }
    };
    
    skills.bundled.unwrap_or_default().enabled  // 读取配置
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 风险 1：文档漂移（Document Drift）

**问题**：参考文档可能随 OpenAI 官方文档更新而失效

**现有缓解措施**：
- 文件头部明确声明："This file will drift unless it is periodically re-verified against current OpenAI docs"
- 冲突时官方文档优先原则

**残余风险**：
- 模型推荐可能过时
- 升级指导可能不适用于最新 API 变更

#### 风险 2：硬编码模型 ID

**问题**：模型 ID（如 `gpt-5.4`）在发布候选阶段可能变更

**影响范围**：
- `latest-model.md` 中的模型映射表
- `upgrading-to-gpt-5p4.md` 中的升级目标字符串

**缓解措施**：
- `upgrading-to-gpt-5p4.md` 包含 "Launch-day refresh items" 检查清单

#### 风险 3：指纹碰撞

**问题**：使用 `DefaultHasher` 计算指纹，Rust 版本间可能不兼容

**代码位置**：`codex-rs/skills/src/lib.rs:87-99`

**影响**：升级 Rust 工具链后可能导致不必要的 Skill 重新安装

#### 风险 4：路径遍历（已缓解）

**问题**：Skill 元数据中的资源路径可能存在安全风险

**缓解措施**：
```rust
// codex-rs/core/src/skills/loader.rs:783-829
fn resolve_asset_path(skill_dir: &Path, field: &'static str, path: Option<PathBuf>) -> Option<PathBuf> {
    // 1. 拒绝绝对路径
    // 2. 规范化路径组件（拒绝 ParentDir）
    // 3. 强制要求位于 assets/ 目录下
}
```

### 6.2 边界条件

| 边界 | 限制值 | 说明 |
|------|--------|------|
| 最大扫描深度 | 6 层 | `MAX_SCAN_DEPTH` |
| 每根目录最大技能数 | 2000 | `MAX_SKILLS_DIRS_PER_ROOT` |
| 技能名称最大长度 | 64 字符 | `MAX_NAME_LEN` |
| 描述最大长度 | 1024 字符 | `MAX_DESCRIPTION_LEN` |
| 系统 Skill 符号链接 | 不跟随 | 安全考虑 |

### 6.3 改进建议

#### 建议 1：自动化文档同步检查

**现状**：依赖人工定期验证
**建议**：添加 CI 任务，定期抓取 OpenAI 文档并检测关键差异

```yaml
# 示例 CI 配置
- name: Check OpenAI Docs Sync
  schedule: weekly
  steps:
    - fetch developers.openai.com/models
    - compare with references/latest-model.md
    - create issue if mismatch detected
```

#### 建议 2：版本化参考文档

**现状**：文档与代码版本紧耦合
**建议**：引入版本标签，支持多版本模型指导共存

```
references/
├── v1/
│   ├── latest-model.md
│   └── upgrading-to-gpt-5p4.md
└── v2/
    ├── latest-model.md
    └── upgrading-to-gpt-5.5.md  # 未来版本
```

#### 建议 3：增强指纹算法稳定性

**现状**：使用 `DefaultHasher`，Rust 版本间不稳定
**建议**：改用稳定的哈希算法（如 SHA-256）

```rust
// 建议修改
use sha2::{Sha256, Digest};

fn embedded_system_skills_fingerprint() -> String {
    let mut hasher = Sha256::new();
    // ... 计算稳定指纹
    format!("{:x}", hasher.finalize())
}
```

#### 建议 4：提示词块模板化

**现状**：提示词块为纯文本，难以程序化使用
**建议**：添加结构化格式（如 TOML Frontmatter），便于工具消费

```markdown
---
block_id: "tool_persistence_rules"
applies_to: ["tool-heavy", "research", "multi-agent"]
requires: []
---
<tool_persistence_rules>
...
</tool_persistence_rules>
```

#### 建议 5：升级指南的自动化支持

**现状**：升级指南为人工阅读文档
**建议**：提供程序化接口，支持自动化升级建议生成

```rust
// 建议新增 API
pub struct UpgradeAdvisor {
    source_model: String,
    target_model: String,
    workflow_type: WorkflowType,
}

impl UpgradeAdvisor {
    pub fn recommend(&self) -> UpgradeRecommendation {
        // 基于 references/ 内容生成建议
    }
}
```

#### 建议 6：MCP 工具健康检查

**现状**：MCP 工具失败时回退到 Web 搜索
**建议**：添加 MCP 服务器健康检查，主动报告工具状态

```rust
// 在 Skill 加载时检查 MCP 可用性
async fn check_mcp_health() -> McpStatus {
    // 尝试连接 developers.openai.com/mcp
    // 返回状态用于 UI 提示
}
```

---

## 7. 附录

### 7.1 文件清单

| 文件 | 大小 | 行数 | 最后修改 |
|------|------|------|----------|
| `latest-model.md` | 1.8 KB | 35 | 2025-03-19 |
| `upgrading-to-gpt-5p4.md` | 8.6 KB | 164 | 2025-03-19 |
| `gpt-5p4-prompting-guide.md` | 18.0 KB | 433 | 2025-03-19 |

### 7.2 相关测试

| 测试文件 | 覆盖内容 |
|----------|----------|
| `codex-rs/skills/src/lib.rs` (内联测试) | 指纹遍历嵌套条目 |
| `codex-rs/core/src/skills/loader_tests.rs` | Skill 加载和解析 |
| `codex-rs/core/src/skills/manager_tests.rs` | Skill 管理器功能 |
| `codex-rs/core/tests/common/context_snapshot.rs` | 系统 Skill 路径规范化 |

### 7.3 引用关系

```
被引用方：
- codex-rs/core/src/skills/manager.rs → install_system_skills
- codex-rs/core/src/skills/system.rs → system_cache_root_dir
- codex-rs/core/src/skills/loader.rs → 发现 .system 目录下的 Skill

引用方（作为参考文档）：
- 由 LLM 根据 SKILL.md 工作流加载
- 无直接代码引用，通过文件系统路径访问
```

---

*文档生成时间：2026-03-22*
*研究范围：codex-rs/skills/src/assets/samples/openai-docs/references/*
