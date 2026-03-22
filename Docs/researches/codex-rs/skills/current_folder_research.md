# codex-rs/skills 深度研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 模块定位

`codex-rs/skills` 是 Codex CLI 的**系统级技能管理 crate**，负责将嵌入式系统技能（embedded system skills）安装到用户文件系统中，并提供技能发现、加载和缓存的基础设施。

### 1.2 核心职责

| 职责 | 说明 |
|------|------|
| **嵌入式技能分发** | 将编译时嵌入的系统技能（如 skill-creator、skill-installer、openai-docs）安装到 `$CODEX_HOME/skills/.system` |
| **指纹缓存机制** | 通过内容指纹避免不必要的重复安装，提升启动性能 |
| **技能目录管理** | 提供系统技能缓存目录的解析和定位功能 |
| **清理能力** | 支持卸载系统技能（当 bundled_skills_enabled=false 时） |

### 1.3 使用场景

1. **Codex 启动时**：`SkillsManager::new()` 调用 `install_system_skills()` 将嵌入式技能写入磁盘
2. **技能加载流程**：`loader.rs` 通过 `system_cache_root_dir()` 定位系统技能目录
3. **配置切换时**：禁用 bundled skills 时调用 `uninstall_system_skills()` 清理

---

## 功能点目的

### 2.1 嵌入式技能安装 (`install_system_skills`)

**目的**：将编译时嵌入的技能资源释放到用户可访问的文件系统位置。

**关键设计决策**：
- 使用 `include_dir` crate 在编译时将 `src/assets/samples` 目录嵌入二进制
- 目标位置：`$CODEX_HOME/skills/.system/`（默认 `~/.codex/skills/.system/`）
- 采用**指纹标记文件** (`.codex-system-skills.marker`) 避免重复写入

**指纹算法**：
```rust
// 使用 DefaultHasher 对以下内容进行哈希：
// 1. 固定盐值 "v1"
// 2. 每个文件/目录的路径
// 3. 每个文件内容的哈希值
```

### 2.2 系统技能缓存目录 (`system_cache_root_dir`)

**目的**：为其他模块提供统一的系统技能目录定位。

**路径解析优先级**：
1. 尝试将 `codex_home` 解析为 `AbsolutePathBuf`
2. 拼接 `skills/.system` 路径
3. 失败时回退到普通 `PathBuf` 拼接

### 2.3 系统技能卸载 (`uninstall_system_skills`)

**目的**：在 bundled skills 被禁用时清理已安装的系统技能。

**实现**：简单的 `fs::remove_dir_all` 包装。

### 2.4 包含的示例技能

当前 crate 嵌入三个系统技能：

| 技能名称 | 用途 | 关键资源 |
|---------|------|---------|
| **skill-creator** | 指导用户创建新技能 | `init_skill.py`, `quick_validate.py`, `generate_openai_yaml.py` |
| **skill-installer** | 从 GitHub 安装技能 | `install-skill-from-github.py`, `list-skills.py` |
| **openai-docs** | OpenAI 产品文档查询 | `latest-model.md`, `upgrading-to-gpt-5p4.md`, `gpt-5p4-prompting-guide.md` |

---

## 具体技术实现

### 3.1 核心数据结构

#### 3.1.1 错误类型

```rust
#[derive(Debug, Error)]
pub enum SystemSkillsError {
    #[error("io error while {action}: {source}")]
    Io {
        action: &'static str,
        source: std::io::Error,
    },
}
```

**设计特点**：
- 使用 `thiserror` 派生错误类型
- 包含上下文 `action` 字段，便于调试定位

#### 3.1.2 嵌入式目录常量

```rust
const SYSTEM_SKILLS_DIR: Dir = include_dir::include_dir!("$CARGO_MANIFEST_DIR/src/assets/samples");
const SYSTEM_SKILLS_DIR_NAME: &str = ".system";
const SKILLS_DIR_NAME: &str = "skills";
const SYSTEM_SKILLS_MARKER_FILENAME: &str = ".codex-system-skills.marker";
const SYSTEM_SKILLS_MARKER_SALT: &str = "v1";
```

### 3.2 关键流程

#### 3.2.1 安装流程 (`install_system_skills`)

```
1. 解析 codex_home 为 AbsolutePathBuf
2. 创建 skills 根目录（如果不存在）
3. 计算目标系统技能目录路径
4. 计算嵌入式内容的指纹
5. 检查 marker 文件：
   - 如果存在且指纹匹配 → 跳过安装（快速返回）
   - 否则 → 继续安装
6. 如果目标目录存在 → 删除整个目录
7. 递归写入嵌入式目录内容
8. 写入新的 marker 文件（包含指纹）
```

**代码路径**：`src/lib.rs:47-78`

#### 3.2.2 指纹计算流程 (`embedded_system_skills_fingerprint`)

```rust
fn embedded_system_skills_fingerprint() -> String {
    let mut items = Vec::new();
    collect_fingerprint_items(&SYSTEM_SKILLS_DIR, &mut items);
    items.sort_unstable_by(|(a, _), (b, _)| a.cmp(b));  // 确保确定性

    let mut hasher = DefaultHasher::new();
    SYSTEM_SKILLS_MARKER_SALT.hash(&mut hasher);  // 盐值
    for (path, contents_hash) in items {
        path.hash(&mut hasher);
        contents_hash.hash(&mut hasher);
    }
    format!("{:x}", hasher.finish())
}
```

**关键特性**：
- 对文件路径和内容哈希进行排序，确保哈希结果稳定
- 使用盐值 `"v1"` 支持未来版本迁移

#### 3.2.3 目录写入流程 (`write_embedded_dir`)

```rust
fn write_embedded_dir(dir: &Dir<'_>, dest: &AbsolutePathBuf) -> Result<(), SystemSkillsError>
```

**实现细节**：
- 递归处理 `include_dir::DirEntry::Dir` 和 `DirEntry::File`
- 使用 `AbsolutePathBuf` 确保路径安全
- 自动创建父目录

### 3.3 构建脚本 (`build.rs`)

**目的**：确保嵌入式资源变更时触发重新编译。

**实现**：
```rust
fn main() {
    let samples_dir = Path::new("src/assets/samples");
    if !samples_dir.exists() { return; }
    
    println!("cargo:rerun-if-changed={}", samples_dir.display());
    // 递归遍历所有子目录和文件，输出 rerun-if-changed
}
```

---

## 关键代码路径与文件引用

### 4.1 本 crate 文件结构

```
codex-rs/skills/
├── Cargo.toml              # crate 配置
├── build.rs                # 构建脚本（资源变更检测）
├── BUILD.bazel             # Bazel 构建配置
└── src/
    └── lib.rs              # 主库代码（195 行）
    └── assets/
        └── samples/        # 嵌入式技能资源
            ├── skill-creator/
            │   ├── SKILL.md
            │   ├── agents/openai.yaml
            │   ├── assets/
            │   ├── references/openai_yaml.md
            │   └── scripts/
            │       ├── init_skill.py
            │       ├── quick_validate.py
            │       └── generate_openai_yaml.py
            ├── skill-installer/
            │   ├── SKILL.md
            │   ├── agents/openai.yaml
            │   ├── assets/
            │   └── scripts/
            │       ├── install-skill-from-github.py
            │       ├── list-skills.py
            │       └── github_utils.py
            └── openai-docs/
                ├── SKILL.md
                ├── agents/openai.yaml
                ├── assets/
                └── references/
                    ├── latest-model.md
                    ├── upgrading-to-gpt-5p4.md
                    └── gpt-5p4-prompting-guide.md
```

### 4.2 关键代码位置

| 功能 | 文件 | 行号 |
|------|------|------|
| `install_system_skills` | `src/lib.rs` | 47-78 |
| `system_cache_root_dir` | `src/lib.rs` | 22-31 |
| `embedded_system_skills_fingerprint` | `src/lib.rs` | 87-99 |
| `write_embedded_dir` | `src/lib.rs` | 123-154 |
| `collect_fingerprint_items` | `src/lib.rs` | 101-118 |
| `uninstall_system_skills` | `core/src/skills/system.rs` | 6-9 |

### 4.3 调用方代码路径

#### 4.3.1 核心调用者：`codex-core`

**文件**：`codex-rs/core/src/skills/manager.rs`

```rust
impl SkillsManager {
    pub fn new(
        codex_home: PathBuf,
        plugins_manager: Arc<PluginsManager>,
        bundled_skills_enabled: bool,
    ) -> Self {
        let manager = Self { ... };
        if !bundled_skills_enabled {
            uninstall_system_skills(&manager.codex_home);
        } else if let Err(err) = install_system_skills(&manager.codex_home) {
            tracing::error!("failed to install system skills: {err}");
        }
        manager
    }
}
```

**文件**：`codex-rs/core/src/skills/system.rs`

```rust
pub(crate) use codex_skills::install_system_skills;
pub(crate) use codex_skills::system_cache_root_dir;

pub(crate) fn uninstall_system_skills(codex_home: &Path) {
    let system_skills_dir = system_cache_root_dir(codex_home);
    let _ = std::fs::remove_dir_all(&system_skills_dir);
}
```

#### 4.3.2 技能加载调用者：`loader.rs`

**文件**：`codex-rs/core/src/skills/loader.rs:287`

```rust
roots.push(SkillRoot {
    path: system_cache_root_dir(config_folder.as_path()),
    scope: SkillScope::System,
});
```

### 4.4 测试覆盖

**单元测试**：`src/lib.rs:172-195`

```rust
#[cfg(test)]
mod tests {
    #[test]
    fn fingerprint_traverses_nested_entries() {
        // 验证指纹计算能正确遍历嵌套目录
    }
}
```

---

## 依赖与外部交互

### 5.1 外部依赖

| 依赖 | 用途 | 版本 |
|------|------|------|
| `include_dir` | 编译时嵌入目录 | workspace |
| `codex-utils-absolute-path` | 绝对路径类型安全 | workspace |
| `thiserror` | 错误类型派生 | workspace |

### 5.2 反向依赖

**唯一消费者**：`codex-core`

```toml
# codex-rs/core/Cargo.toml
codex-skills = { workspace = true }
```

### 5.3 与技能系统的交互

```
┌─────────────────┐
│   codex-core    │
│  SkillsManager  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌──────────────────┐
│  codex-skills   │────▶│  $CODEX_HOME/    │
│ install_system_ │     │  skills/.system/ │
│    skills()     │     │  (运行时文件)     │
└─────────────────┘     └──────────────────┘
         │
         │ include_dir!
         ▼
┌──────────────────┐
│ src/assets/      │
│ samples/         │  (编译时嵌入)
└──────────────────┘
```

### 5.4 环境变量交互

| 变量 | 用途 | 默认值 |
|------|------|--------|
| `CODEX_HOME` | 技能安装根目录 | `~/.codex` |

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 并发安装风险

**问题**：`install_system_skills` 非原子操作，多进程同时启动可能导致竞争条件。

**当前缓解**：
- 指纹检查快速返回（但检查和写入之间仍有窗口）
- 先删除再写入，可能导致短暂无系统技能可用

**建议改进**：
```rust
// 使用临时目录 + 原子重命名
let temp_dir = dest_system.with_extension(".tmp");
write_embedded_dir(&SYSTEM_SKILLS_DIR, &temp_dir)?;
fs::rename(temp_dir, dest_system)?;
```

#### 6.1.2 指纹碰撞风险

**问题**：使用 `DefaultHasher`，Rust 版本升级可能导致哈希算法变化。

**当前缓解**：使用盐值 `"v1"`，可在算法变更时升级盐值。

#### 6.1.3 权限问题

**问题**：`CODEX_HOME` 目录可能无写入权限。

**当前处理**：返回 `SystemSkillsError::Io`，由调用者记录错误但不中断启动。

### 6.2 边界条件

| 边界 | 行为 |
|------|------|
| `samples_dir` 不存在 | 构建脚本静默返回，不输出 rerun-if-changed |
| marker 文件读取失败 | 视为不匹配，重新安装 |
| 目录写入失败 | 返回 `SystemSkillsError::Io` |
| 路径包含非 UTF-8 字符 | 使用 `to_string_lossy()` 处理 |

### 6.3 改进建议

#### 6.3.1 高优先级

1. **原子安装**
   - 使用临时目录 + 原子重命名避免竞争条件
   - 添加文件锁机制（如 `fs2` crate）

2. **稳定哈希**
   - 考虑使用稳定哈希算法（如 `sha2`）替代 `DefaultHasher`
   - 或明确记录使用的哈希算法版本

3. **增量更新**
   - 当前是全量删除+重写，可考虑文件级增量更新
   - 对大技能包可显著减少 I/O

#### 6.3.2 中优先级

4. **监控与可观测性**
   - 添加 metrics 记录安装耗时、缓存命中率
   - 添加详细日志记录每个技能的安装状态

5. **配置化技能列表**
   - 当前技能列表硬编码在 `src/assets/samples`
   - 可考虑通过构建脚本动态收集，支持 feature flag 控制

#### 6.3.3 低优先级

6. **压缩存储**
   - 嵌入式资源可使用压缩减少二进制体积
   - 安装时解压，权衡编译时 vs 运行时开销

7. **权限管理**
   - 安装时保留原始文件权限（特别是脚本的可执行位）
   - 当前 `write_embedded_dir` 未处理权限位

### 6.4 测试建议

当前测试覆盖较薄，建议添加：

```rust
// 1. 并发安装测试
#[test]
fn concurrent_install_is_safe() { }

// 2. 指纹变更检测测试
#[test]
fn fingerprint_changes_when_content_changes() { }

// 3. 权限保留测试
#[test]
fn executable_permissions_preserved() { }

// 4. 错误恢复测试
#[test]
fn partial_install_recovery() { }
```

---

## 附录：技能内容详解

### A.1 skill-creator 技能

**脚本功能**：

| 脚本 | 功能 |
|------|------|
| `init_skill.py` | 创建新技能目录结构，生成 SKILL.md 模板和 agents/openai.yaml |
| `quick_validate.py` | 验证技能目录结构、YAML frontmatter 格式 |
| `generate_openai_yaml.py` | 根据 skill 名称生成 UI 元数据文件 |

**关键约束**：
- 技能名：小写字母、数字、连字符，最大 64 字符
- short_description：25-64 字符

### A.2 skill-installer 技能

**脚本功能**：

| 脚本 | 功能 |
|------|------|
| `list-skills.py` | 从 GitHub API 获取 curated/experimental 技能列表 |
| `install-skill-from-github.py` | 支持 zip 下载或 git sparse checkout 安装 |
| `github_utils.py` | GitHub API 请求封装，支持 GITHUB_TOKEN 认证 |

**安装方式优先级**：
1. `auto`：先尝试 zip 下载，失败回退到 git
2. `download`：仅 zip 下载
3. `git`：仅 git sparse checkout

### A.3 openai-docs 技能

**参考文档用途**：

| 文档 | 用途 |
|------|------|
| `latest-model.md` | 模型选择建议 |
| `upgrading-to-gpt-5p4.md` | GPT-5.4 升级指南 |
| `gpt-5p4-prompting-guide.md` | 提示词优化模板 |

**MCP 工具依赖**：
- `openaiDeveloperDocs` MCP server
- 工具：`search_openai_docs`, `fetch_openai_doc`, `list_openai_docs`

---

*文档生成时间：2026-03-22*
*基于代码版本：codex-rs/skills @ HEAD*
