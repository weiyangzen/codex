# Research: skill-installer/agents/openai.yaml

## 文件信息
- **目标文件**: `codex-rs/skills/src/assets/samples/skill-installer/agents/openai.yaml`
- **文件类型**: YAML 配置文件（Skill 元数据）
- **所属 Skill**: `skill-installer`
- **研究时间**: 2026-03-23

---

## 1. 场景与职责

### 1.1 文件定位

`openai.yaml` 是 **Skill Installer** 技能的元数据配置文件，位于 `agents/` 子目录下。该文件是 OpenAI Codex 平台技能体系中的标准化元数据文件，用于描述技能的接口信息、依赖关系和策略配置。

### 1.2 所属 Skill 的职责

**Skill Installer** 是一个系统级技能（System Skill），其核心职责是：

1. **技能列表查询**: 从 GitHub 仓库（默认 `openai/skills`）获取可安装的技能列表
2. **技能安装**: 支持从以下来源安装技能：
   - OpenAI 官方 curated 技能列表（`skills/.curated`）
   - 实验性技能（`skills/.experimental`）
   - 任意 GitHub 仓库的指定路径
3. **安装方式**: 
   - 直接下载（public repos）
   - Git sparse checkout（private repos 或下载失败时）

### 1.3 文件作用域

该 `openai.yaml` 文件被 Codex 核心加载器解析，用于：
- 在 UI 中显示技能的友好名称和描述
- 提供技能图标资源路径
- 定义技能的默认行为和依赖关系

---

## 2. 功能点目的

### 2.1 YAML 内容解析

```yaml
interface:
  display_name: "Skill Installer"
  short_description: "Install curated skills from openai/skills or other repos"
  icon_small: "./assets/skill-installer-small.svg"
  icon_large: "./assets/skill-installer.png"
```

#### 字段说明

| 字段 | 值 | 目的 |
|------|-----|------|
| `display_name` | "Skill Installer" | 用户界面显示的技能名称，支持空格和大小写 |
| `short_description` | "Install curated skills from openai/skills or other repos" | 25-64 字符的简短描述，用于技能列表快速浏览 |
| `icon_small` | "./assets/skill-installer-small.svg" | 小图标路径（400px 左右），用于技能芯片/列表项 |
| `icon_large` | "./assets/skill-installer.png" | 大图标路径，用于技能详情页 |

### 2.2 与其他 Skill 的对比

| Skill | display_name | short_description | 特殊字段 |
|-------|-------------|-------------------|----------|
| **skill-installer** | "Skill Installer" | Install curated skills from openai/skills or other repos | 基础 interface 配置 |
| skill-creator | "Skill Creator" | Create or update a skill | 基础 interface 配置 |
| openai-docs | "OpenAI Docs" | Reference official OpenAI docs... | 包含 `default_prompt` 和 `dependencies` |

**注意**: `skill-installer` 和 `skill-creator` 的 `openai.yaml` 仅包含基础 `interface` 配置，而 `openai-docs` 包含更复杂的 `dependencies` 配置（MCP 工具依赖）。

---

## 3. 具体技术实现

### 3.1 文件加载流程

```
Skill 加载流程（由 codex-rs/core/src/skills/loader.rs 实现）

1. 扫描技能根目录（System/User/Repo/Admin Scope）
   ↓
2. 查找 SKILL.md 文件
   ↓
3. 解析 SKILL.md 的 YAML Frontmatter
   ↓
4. 查找同目录下的 agents/openai.yaml
   ↓
5. 解析 openai.yaml → SkillMetadataFile 结构
   ↓
6. 合并到 SkillMetadata 对象
```

### 3.2 核心数据结构

#### 3.2.1 YAML 解析结构（loader.rs）

```rust
#[derive(Debug, Default, Deserialize)]
struct SkillMetadataFile {
    #[serde(default)]
    interface: Option<Interface>,
    #[serde(default)]
    dependencies: Option<Dependencies>,
    #[serde(default)]
    policy: Option<Policy>,
    #[serde(default)]
    permissions: Option<SkillPermissionProfile>,
}

#[derive(Debug, Default, Deserialize)]
struct Interface {
    display_name: Option<String>,
    short_description: Option<String>,
    icon_small: Option<PathBuf>,
    icon_large: Option<PathBuf>,
    brand_color: Option<String>,
    default_prompt: Option<String>,
}
```

#### 3.2.2 运行时模型（model.rs）

```rust
pub struct SkillMetadata {
    pub name: String,                          // 来自 SKILL.md frontmatter
    pub description: String,                   // 来自 SKILL.md frontmatter
    pub short_description: Option<String>,     // 来自 openai.yaml interface
    pub interface: Option<SkillInterface>,     // 来自 openai.yaml
    pub dependencies: Option<SkillDependencies>,
    pub policy: Option<SkillPolicy>,
    pub permission_profile: Option<PermissionProfile>,
    pub path_to_skills_md: PathBuf,
    pub scope: SkillScope,
}

pub struct SkillInterface {
    pub display_name: Option<String>,
    pub short_description: Option<String>,
    pub icon_small: Option<PathBuf>,
    pub icon_large: Option<PathBuf>,
    pub brand_color: Option<String>,
    pub default_prompt: Option<String>,
}
```

### 3.3 图标路径解析逻辑

```rust
fn resolve_asset_path(
    skill_dir: &Path,
    field: &'static str,
    path: Option<PathBuf>,
) -> Option<PathBuf> {
    // 1. 路径必须是相对路径
    // 2. 路径必须位于 assets/ 目录下
    // 3. 路径不能包含 '..' 组件
    // 4. 最终解析为 skill_dir.join(normalized_path)
}
```

对于 `skill-installer`：
- `icon_small`: `./assets/skill-installer-small.svg` → 实际路径 `{skill_dir}/assets/skill-installer-small.svg`
- `icon_large`: `./assets/skill-installer.png` → 实际路径 `{skill_dir}/assets/skill-installer.png`

### 3.4 系统技能安装机制

`skill-installer` 作为**系统技能**（System Skill），通过 `codex-skills` crate 的嵌入资源机制分发：

```rust
// codex-rs/skills/src/lib.rs
const SYSTEM_SKILLS_DIR: Dir = include_dir::include_dir!("$CARGO_MANIFEST_DIR/src/assets/samples");

pub fn install_system_skills(codex_home: &Path) -> Result<(), SystemSkillsError> {
    // 1. 计算嵌入资源的指纹（基于文件内容哈希）
    // 2. 与本地缓存的指纹对比
    // 3. 如不同，清除旧缓存并写入新资源
    // 4. 写入指纹标记文件
}
```

安装路径：`$CODEX_HOME/skills/.system/skill-installer/`

---

## 4. 关键代码路径与文件引用

### 4.1 直接相关文件

| 文件路径 | 作用 |
|----------|------|
| `codex-rs/skills/src/assets/samples/skill-installer/agents/openai.yaml` | **目标文件**：元数据配置 |
| `codex-rs/skills/src/assets/samples/skill-installer/SKILL.md` | 技能主文档，包含使用说明和脚本调用方式 |
| `codex-rs/skills/src/assets/samples/skill-installer/scripts/install-skill-from-github.py` | 技能安装脚本 |
| `codex-rs/skills/src/assets/samples/skill-installer/scripts/list-skills.py` | 技能列表查询脚本 |
| `codex-rs/skills/src/assets/samples/skill-installer/scripts/github_utils.py` | GitHub API 工具函数 |
| `codex-rs/skills/src/assets/samples/skill-installer/assets/skill-installer-small.svg` | 小图标资源 |
| `codex-rs/skills/src/assets/samples/skill-installer/assets/skill-installer.png` | 大图标资源 |
| `codex-rs/skills/src/assets/samples/skill-installer/LICENSE.txt` | Apache 2.0 许可证 |

### 4.2 核心解析代码

| 文件路径 | 功能 |
|----------|------|
| `codex-rs/core/src/skills/loader.rs` | Skill 加载和元数据解析 |
| `codex-rs/core/src/skills/loader.rs:602-655` | `load_skill_metadata()` 函数，解析 openai.yaml |
| `codex-rs/core/src/skills/loader.rs:693-722` | `resolve_interface()` 函数，解析 interface 字段 |
| `codex-rs/core/src/skills/loader.rs:783-829` | `resolve_asset_path()` 函数，图标路径解析 |
| `codex-rs/core/src/skills/model.rs` | Skill 元数据模型定义 |
| `codex-rs/skills/src/lib.rs` | 系统技能安装逻辑 |
| `codex-rs/skills/build.rs` | 构建脚本，监控资源文件变更 |

### 4.3 调用链

```
UI 层 (TUI/CLI)
    ↓
SkillsManager::skills_for_config() [manager.rs]
    ↓
skill_roots() → 包含 system_cache_root_dir() [loader.rs]
    ↓
load_skills_from_roots()
    ↓
discover_skills_under_root()
    ↓
parse_skill_file() → 解析 SKILL.md frontmatter
    ↓
load_skill_metadata() → 解析 agents/openai.yaml
    ↓
resolve_interface() → 构建 SkillInterface
    ↓
SkillMetadata { interface: SkillInterface { display_name, short_description, icon_small, icon_large } }
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖 | 说明 |
|------|------|
| `codex-skills` crate | 系统技能嵌入和安装 |
| `codex-core` crate | Skill 加载和管理 |
| `include_dir` crate | 编译时嵌入资源文件 |

### 5.2 外部交互（通过脚本）

| 交互对象 | 方式 | 用途 |
|----------|------|------|
| GitHub API | HTTPS + Token | 获取技能列表（`list-skills.py`） |
| GitHub codeload | HTTPS 下载 | 下载技能压缩包（`install-skill-from-github.py`） |
| Git CLI | `git sparse-checkout` | 私有仓库或下载失败时的回退方案 |
| 本地文件系统 | 文件操作 | 安装技能到 `$CODEX_HOME/skills/` |

### 5.3 环境变量依赖

| 变量 | 用途 |
|------|------|
| `CODEX_HOME` | 技能安装根目录（默认 `~/.codex`） |
| `GITHUB_TOKEN` / `GH_TOKEN` | GitHub API 认证（可选，用于私有仓库） |

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 元数据验证风险

**问题**: `openai.yaml` 中的 `short_description` 长度约束（25-64 字符）仅在加载时通过警告日志处理，不会阻止加载。

```rust
// loader.rs:resolve_str()
if value.chars().count() > max_len {
    tracing::warn!("ignoring {field}: exceeds maximum length of {max_len} characters");
    return None;
}
```

**影响**: 超长描述被静默忽略，可能导致 UI 显示不一致。

#### 6.1.2 图标路径安全风险

**当前防护**:
- 禁止绝对路径
- 禁止 `..` 组件
- 强制要求路径以 `assets/` 开头

**潜在风险**: 如果 `assets/` 目录被符号链接到系统敏感路径，可能存在信息泄露风险。

#### 6.1.3 网络依赖风险

**问题**: Skill Installer 的核心功能（列表查询、安装）依赖 GitHub 网络访问。

**影响**: 
- 离线环境无法使用
- GitHub API 限制可能影响用户体验

### 6.2 边界情况

| 场景 | 行为 |
|------|------|
| `openai.yaml` 不存在 | 正常加载，SkillMetadata.interface = None |
| `openai.yaml` YAML 格式错误 | 记录警告，正常加载，interface = None |
| 图标文件不存在 | 路径仍保留在 metadata 中，UI 层需处理缺失 |
| `short_description` 长度非法 | 被忽略，使用 SKILL.md 的 description 作为回退 |
| 系统技能缓存损坏 | 指纹不匹配时自动重新安装 |

### 6.3 改进建议

#### 6.3.1 元数据验证增强

```yaml
# 建议添加 schema 版本控制
version: "1.0"
interface:
  display_name: "Skill Installer"
  # ...
```

#### 6.3.2 离线模式支持

- 预打包 curated 技能列表缓存
- 支持本地路径安装（无需 GitHub）

#### 6.3.3 图标资源校验

```rust
// 建议在构建时验证图标文件存在性
fn validate_assets(skill_dir: &Path, interface: &Interface) -> Result<(), AssetError> {
    if let Some(ref small) = interface.icon_small {
        let path = skill_dir.join(small);
        if !path.exists() {
            return Err(AssetError::Missing(path));
        }
    }
    // ...
}
```

#### 6.3.4 多语言支持

当前 `display_name` 和 `short_description` 仅支持单一语言，未来可考虑：

```yaml
interface:
  display_name:
    en: "Skill Installer"
    zh: "技能安装器"
  short_description:
    en: "Install curated skills from openai/skills or other repos"
    zh: "从 openai/skills 或其他仓库安装精选技能"
```

#### 6.3.5 依赖声明完善

当前 `skill-installer` 的 `openai.yaml` 未声明 `dependencies`，但实际依赖：
- Python 3 运行时
- `urllib`, `zipfile`, `subprocess` 等标准库
- Git CLI（回退场景）

建议添加：

```yaml
dependencies:
  tools:
    - type: "system"
      value: "python3"
      description: "Python 3 runtime for install scripts"
    - type: "system"
      value: "git"
      description: "Git CLI for sparse checkout fallback"
```

---

## 7. 附录

### 7.1 相关文档

- `codex-rs/skills/src/assets/samples/skill-creator/references/openai_yaml.md`: `openai.yaml` 完整字段参考
- `SKILL.md`: Skill Installer 使用文档

### 7.2 测试覆盖

- `codex-rs/core/tests/suite/skill_approval.rs`: 包含技能元数据（含 `openai.yaml` 风格配置）的测试用例
- `codex-rs/core/src/skills/loader_tests.rs`: Skill 加载单元测试

### 7.3 生成工具

- `skill-creator/scripts/generate_openai_yaml.py`: 用于生成标准化的 `openai.yaml` 文件
