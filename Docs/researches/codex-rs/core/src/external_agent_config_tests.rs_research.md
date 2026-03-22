# external_agent_config_tests.rs 研究文档

## 场景与职责

本文件是 `external_agent_config.rs` 模块的单元测试文件，负责测试从 Claude Code 配置迁移到 Codex 配置的核心功能。主要覆盖以下场景：

1. **配置检测 (detect)**：识别需要迁移的配置项
2. **配置导入 (import)**：执行实际的配置迁移操作
3. **技能迁移**：从 Claude 的 skills 目录复制到 Codex 的 skills 目录
4. **AGENTS.md 迁移**：将 CLAUDE.md 内容改写为 AGENTS.md

## 功能点目的

### 1. 配置迁移检测 (`detect` 方法测试)

测试目标：验证系统能够正确识别需要迁移的配置项类型：

- **Config 类型**：检测 `settings.json` 中可迁移的配置字段
- **Skills 类型**：检测需要复制的技能目录
- **AgentsMd 类型**：检测需要导入的 CLAUDE.md 文件

关键测试用例：
- `detect_home_lists_config_skills_and_agents_md`：验证 home 目录下的完整检测
- `detect_repo_lists_agents_md_for_each_cwd`：验证仓库级别的 AGENTS.md 检测
- `detect_home_skips_config_when_target_already_has_supported_fields`：跳过已存在的配置
- `detect_home_skips_skills_when_all_skill_directories_exist`：跳过已存在的技能目录
- `detect_repo_prefers_non_empty_dot_claude_agents_source`：优先使用 `.claude/CLAUDE.md`

### 2. 配置导入 (`import` 方法测试)

测试目标：验证迁移操作的正确执行：

- `import_home_migrates_supported_config_fields_skills_and_agents_md`：完整迁移测试
  - 验证 `env` 字段转换为 `shell_environment_policy`
  - 验证 `sandbox.enabled` 转换为 `sandbox_mode`
  - 验证技能目录复制
  - 验证 CLAUDE.md → AGENTS.md 的改写

- `import_home_skips_empty_config_migration`：跳过空配置
- `import_repo_agents_md_rewrites_terms_and_skips_non_empty_targets`：术语改写与非空跳过
- `import_repo_agents_md_overwrites_empty_targets`：空目标文件覆盖
- `import_repo_uses_non_empty_dot_claude_agents_source`：优先使用 `.claude/` 下的源文件

### 3. 技能导入测试

- `import_skills_returns_only_new_skill_directory_count`：仅返回新复制的技能数量
- `migration_metric_tags_for_skills_include_skills_count`：验证指标标签生成

## 具体技术实现

### 测试基础设施

```rust
// 测试辅助函数：创建临时目录结构
fn fixture_paths() -> (TempDir, PathBuf, PathBuf) {
    let root = TempDir::new().expect("create tempdir");
    let claude_home = root.path().join(".claude");
    let codex_home = root.path().join(".codex");
    (root, claude_home, codex_home)
}

// 创建测试服务实例
fn service_for_paths(claude_home: PathBuf, codex_home: PathBuf) -> ExternalAgentConfigService {
    ExternalAgentConfigService::new_for_test(codex_home, claude_home)
}
```

### 关键测试模式

1. **临时文件系统操作**：使用 `tempfile::TempDir` 创建隔离的测试环境
2. **文件内容断言**：使用 `fs::read_to_string` 验证生成的文件内容
3. **精确匹配断言**：使用 `pretty_assertions::assert_eq` 进行详细差异比较

### 配置转换验证

测试验证了以下 JSON → TOML 的转换：

```json
{
  "model": "claude",
  "permissions": {"ask": ["git push"]},
  "env": {"FOO": "bar", "CI": false, "MAX_RETRIES": 3},
  "sandbox": {"enabled": true, "network": {"allowLocalBinding": true}}
}
```

转换为：

```toml
sandbox_mode = "workspace-write"

[shell_environment_policy]
inherit = "core"

[shell_environment_policy.set]
CI = "false"
FOO = "bar"
MAX_RETRIES = "3"
```

注意：
- `permissions` 和 `model` 字段被过滤（不迁移）
- 环境变量值统一转为字符串
- `sandbox.enabled: true` 映射为 `sandbox_mode = "workspace-write"`

### 术语改写验证

测试验证了以下术语替换：
- `claude.md` → `AGENTS.md`
- `claude code` / `claude-code` / `claude_code` / `claudecode` / `claude` → `Codex`

## 关键代码路径与文件引用

### 被测试的主要方法

| 测试函数 | 被测方法 | 功能描述 |
|---------|---------|---------|
| `detect_*` | `ExternalAgentConfigService::detect` | 检测可迁移项 |
| `import_*` | `ExternalAgentConfigService::import` | 执行迁移 |
| `import_skills_*` | `ExternalAgentConfigService::import_skills` | 技能迁移 |

### 核心数据结构

```rust
// 迁移项类型
pub enum ExternalAgentConfigMigrationItemType {
    Config,
    Skills,
    AgentsMd,
    McpServerConfig,
}

// 迁移项
pub struct ExternalAgentConfigMigrationItem {
    pub item_type: ExternalAgentConfigMigrationItemType,
    pub description: String,
    pub cwd: Option<PathBuf>,
}

// 检测选项
pub struct ExternalAgentConfigDetectOptions {
    pub include_home: bool,
    pub cwds: Option<Vec<PathBuf>>,
}
```

### 文件路径约定

**Claude 侧（源）：**
- Home: `~/.claude/settings.json`
- Home: `~/.claude/CLAUDE.md`
- Home: `~/.claude/skills/`
- Repo: `<repo>/.claude/settings.json`
- Repo: `<repo>/CLAUDE.md` 或 `<repo>/.claude/CLAUDE.md`
- Repo: `<repo>/.claude/skills/`

**Codex 侧（目标）：**
- Home: `~/.codex/config.toml`
- Home: `~/.codex/AGENTS.md`
- Home: `~/.agents/skills/`
- Repo: `<repo>/.codex/config.toml`
- Repo: `<repo>/AGENTS.md`
- Repo: `<repo>/.agents/skills/`

## 依赖与外部交互

### 直接依赖

| 依赖 | 用途 |
|-----|------|
| `tempfile::TempDir` | 创建临时测试目录 |
| `std::fs` | 文件系统操作 |
| `pretty_assertions::assert_eq` | 测试断言 |

### 被测试模块的依赖

| 依赖 | 用途 |
|-----|------|
| `serde_json` | 解析 Claude 的 settings.json |
| `toml` | 生成 Codex 的 config.toml |
| `codex_otel::metrics` | 迁移指标上报 |

### 测试隔离策略

1. **文件系统隔离**：每个测试使用独立的 `TempDir`
2. **服务实例隔离**：通过 `new_for_test` 构造器注入路径
3. **无实际网络/指标**：指标上报在测试中被忽略（`global()` 返回 `None`）

## 风险、边界与改进建议

### 当前风险点

1. **路径硬编码**：测试中的路径拼接逻辑与生产代码耦合
2. **时序依赖**：`detect_repo_lists_agents_md_for_each_cwd` 测试依赖特定顺序的输出
3. **平台差异**：路径分隔符在 Windows 上可能产生问题（未测试）

### 边界情况覆盖

| 边界情况 | 测试覆盖 |
|---------|---------|
| 空源文件 | `detect_repo_prefers_non_empty_dot_claude_agents_source` |
| 空目标文件 | `import_repo_agents_md_overwrites_empty_targets` |
| 非空目标文件 | `import_repo_agents_md_rewrites_terms_and_skips_non_empty_targets` |
| 部分技能已存在 | `import_skills_returns_only_new_skill_directory_count` |
| 配置字段已存在 | `detect_home_skips_config_when_target_already_has_supported_fields` |

### 改进建议

1. **增加错误路径测试**：当前测试主要覆盖成功路径，建议增加：
   - 无效 JSON 格式的处理
   - 文件权限不足的场景
   - 磁盘空间不足的场景

2. **并发安全测试**：`import` 方法涉及文件系统操作，建议测试并发调用场景

3. **性能基准测试**：对于大型技能目录的迁移，建议增加性能测试

4. **平台兼容性测试**：增加 Windows 路径处理的专门测试

5. **指标验证**：当前测试不验证指标上报，建议增加 mock 验证
