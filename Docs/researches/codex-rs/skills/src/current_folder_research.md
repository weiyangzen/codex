# codex-rs/skills/src 深度研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 定位与核心职责

`codex-rs/skills/src` 是 Codex 项目中负责**系统技能（System Skills）嵌入式分发**的核心模块。其主要职责包括：

1. **嵌入式系统技能管理**：将预设的技能模板（skill-creator、skill-installer、openai-docs）打包嵌入到编译后的二进制文件中
2. **系统技能安装与缓存**：在 Codex 启动时将嵌入的技能解压到用户本地文件系统（`$CODEX_HOME/skills/.system`）
3. **指纹验证与增量更新**：通过哈希指纹机制避免不必要的重复安装，只在技能内容变化时重新解压

### 1.2 业务场景

| 场景 | 说明 |
|------|------|
| **首次启动** | Codex 启动时检测到 `$CODEX_HOME/skills/.system` 不存在，解压所有嵌入的系统技能 |
| **技能更新** | 新版本 Codex 包含更新的技能内容，指纹不匹配时自动清理旧版本并重新安装 |
| **禁用系统技能** | 用户配置 `bundled.enabled = false` 时，清理已安装的系统技能 |
| **离线使用** | 嵌入的技能无需网络即可使用，确保核心功能可用 |

### 1.3 与 core/skills 的关系

```
codex-rs/skills/src/lib.rs          # 底层系统技能安装/管理
        ↓
codex-rs/core/src/skills/system.rs  # 再导出，供 core 使用
        ↓
codex-rs/core/src/skills/manager.rs # SkillsManager 调用安装逻辑
        ↓
SkillsManager::new()                # 初始化时执行系统技能安装
```

---

## 功能点目的

### 2.1 功能总览

| 功能模块 | 目的 | 关键函数/结构 |
|----------|------|---------------|
| **系统技能缓存定位** | 确定系统技能的本地存储路径 | `system_cache_root_dir()` |
| **系统技能安装** | 将嵌入的技能解压到本地文件系统 | `install_system_skills()` |
| **指纹计算** | 计算嵌入技能内容的哈希指纹用于变更检测 | `embedded_system_skills_fingerprint()` |
| **目录写入** | 递归写入嵌入目录到磁盘 | `write_embedded_dir()` |
| **系统技能卸载** | 清理本地系统技能目录 | `uninstall_system_skills()` (core 层封装) |

### 2.2 嵌入的技能内容

位于 `src/assets/samples/` 的三个系统技能：

1. **skill-creator**：指导用户创建有效技能的完整指南
   - 包含 `init_skill.py`：初始化新技能目录结构
   - 包含 `quick_validate.py`：验证技能格式正确性
   - 包含 `generate_openai_yaml.py`：生成 UI 元数据

2. **skill-installer**：从 GitHub 安装技能的工具
   - 包含 `install-skill-from-github.py`：支持 zip 下载或 git sparse checkout
   - 包含 `list-skills.py`：列出可安装的技能
   - 包含 `github_utils.py`：GitHub API 请求工具

3. **openai-docs**：OpenAI 产品文档查询技能
   - 提供官方文档 MCP 工具使用指南
   - 包含 GPT-5.4 升级和提示词优化参考

### 2.3 渐进式披露设计

系统技能遵循 Codex 的渐进式披露原则：

```
Level 1: Metadata (name + description)     → 始终加载 (~100 words)
Level 2: SKILL.md body                     → 触发后加载 (<5k words)
Level 3: Bundled resources                 → 按需加载 (scripts/references/assets)
```

---

## 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 错误类型

```rust
// lib.rs:156-170
#[derive(Debug, Error)]
pub enum SystemSkillsError {
    #[error("io error while {action}: {source}")]
    Io {
        action: &'static str,
        #[source]
        source: std::io::Error,
    },
}
```

#### 3.1.2 常量定义

```rust
// lib.rs:12-17
const SYSTEM_SKILLS_DIR: Dir = include_dir::include_dir!("$CARGO_MANIFEST_DIR/src/assets/samples");
const SYSTEM_SKILLS_DIR_NAME: &str = ".system";
const SKILLS_DIR_NAME: &str = "skills";
const SYSTEM_SKILLS_MARKER_FILENAME: &str = ".codex-system-skills.marker";
const SYSTEM_SKILLS_MARKER_SALT: &str = "v1";
```

### 3.2 核心流程

#### 3.2.1 系统技能安装流程

```rust
// lib.rs:47-78
pub fn install_system_skills(codex_home: &Path) -> Result<(), SystemSkillsError> {
    // 1. 解析并规范化 CODEX_HOME 路径
    let codex_home = AbsolutePathBuf::try_from(codex_home)
        .map_err(|source| SystemSkillsError::io("normalize codex home dir", source))?;
    
    // 2. 确保 skills 根目录存在
    fs::create_dir_all(skills_root_dir.as_path())?;
    
    // 3. 计算目标系统技能目录路径
    let dest_system = system_cache_root_dir_abs(&codex_home)?;
    let marker_path = dest_system.join(SYSTEM_SKILLS_MARKER_FILENAME)?;
    
    // 4. 计算期望的指纹
    let expected_fingerprint = embedded_system_skills_fingerprint();
    
    // 5. 检查是否已安装且指纹匹配（短路返回）
    if dest_system.as_path().is_dir()
        && read_marker(&marker_path).is_ok_and(|marker| marker == expected_fingerprint)
    {
        return Ok(());  // 已是最新版本，无需操作
    }
    
    // 6. 清理旧版本（如果存在）
    if dest_system.as_path().exists() {
        fs::remove_dir_all(dest_system.as_path())?;
    }
    
    // 7. 写入新的嵌入目录内容
    write_embedded_dir(&SYSTEM_SKILLS_DIR, &dest_system)?;
    
    // 8. 写入新的指纹标记文件
    fs::write(marker_path.as_path(), format!("{expected_fingerprint}\n"))?;
    Ok(())
}
```

#### 3.2.2 指纹计算流程

```rust
// lib.rs:87-99
fn embedded_system_skills_fingerprint() -> String {
    let mut items = Vec::new();
    collect_fingerprint_items(&SYSTEM_SKILLS_DIR, &mut items);
    items.sort_unstable_by(|(a, _), (b, _)| a.cmp(b));

    let mut hasher = DefaultHasher::new();
    SYSTEM_SKILLS_MARKER_SALT.hash(&mut hasher);  // 加盐防止碰撞
    for (path, contents_hash) in items {
        path.hash(&mut hasher);
        contents_hash.hash(&mut hasher);
    }
    format!("{:x}", hasher.finish())
}
```

#### 3.2.3 目录递归写入流程

```rust
// lib.rs:123-154
fn write_embedded_dir(dir: &Dir<'_>, dest: &AbsolutePathBuf) -> Result<(), SystemSkillsError> {
    fs::create_dir_all(dest.as_path())?;

    for entry in dir.entries() {
        match entry {
            include_dir::DirEntry::Dir(subdir) => {
                // 递归处理子目录
                let subdir_dest = dest.join(subdir.path())?;
                fs::create_dir_all(subdir_dest.as_path())?;
                write_embedded_dir(subdir, dest)?;  // 递归调用
            }
            include_dir::DirEntry::File(file) => {
                // 写入文件内容
                let path = dest.join(file.path())?;
                if let Some(parent) = path.as_path().parent() {
                    fs::create_dir_all(parent)?;
                }
                fs::write(path.as_path(), file.contents())?;
            }
        }
    }
    Ok(())
}
```

### 3.3 编译时文件包含机制

使用 `include_dir` crate 在编译时将整个目录嵌入二进制：

```rust
// lib.rs:12
const SYSTEM_SKILLS_DIR: Dir = include_dir::include_dir!("$CARGO_MANIFEST_DIR/src/assets/samples");
```

配合 `build.rs` 实现增量编译支持：

```rust
// build.rs:1-27
fn main() {
    let samples_dir = Path::new("src/assets/samples");
    if !samples_dir.exists() {
        return;
    }
    
    // 为每个文件输出 rerun-if-changed，确保文件修改时重新编译
    println!("cargo:rerun-if-changed={}", samples_dir.display());
    visit_dir(samples_dir);
}

fn visit_dir(dir: &Path) {
    for entry in entries.flatten() {
        let path = entry.path();
        println!("cargo:rerun-if-changed={}", path.display());
        if path.is_dir() {
            visit_dir(&path);  // 递归处理
        }
    }
}
```

### 3.4 Bazel 构建配置

```starlark
# BUILD.bazel
codex_rust_crate(
    name = "skills",
    crate_name = "codex_skills",
    compile_data = glob(
        include = ["**"],
        exclude = [
            "**/* *",        # 排除带空格的文件名
            "BUILD.bazel",
            "Cargo.toml",
        ],
        allow_empty = True,
    ),
)
```

注意：`include_dir` 在 Bazel 下需要显式声明 `compile_data` 依赖，否则编译时无法访问源文件。

---

## 关键代码路径与文件引用

### 4.1 本模块文件结构

```
codex-rs/skills/
├── Cargo.toml              # 包配置，依赖 include_dir、thiserror、codex-utils-absolute-path
├── build.rs                # 编译脚本，输出 rerun-if-changed 指令
├── BUILD.bazel             # Bazel 构建配置
└── src/
    └── lib.rs              # 唯一源文件，包含所有逻辑和测试
    └── assets/
        └── samples/        # 嵌入的系统技能目录
            ├── skill-creator/      # 技能创建指南
            │   ├── SKILL.md
            │   ├── agents/openai.yaml
            │   ├── assets/
            │   ├── references/openai_yaml.md
            │   └── scripts/
            │       ├── init_skill.py
            │       ├── quick_validate.py
            │       └── generate_openai_yaml.py
            ├── skill-installer/    # 技能安装工具
            │   ├── SKILL.md
            │   ├── agents/openai.yaml
            │   ├── assets/
            │   └── scripts/
            │       ├── install-skill-from-github.py
            │       ├── list-skills.py
            │       └── github_utils.py
            └── openai-docs/        # OpenAI 文档查询
                ├── SKILL.md
                ├── agents/openai.yaml
                ├── assets/
                └── references/
                    ├── gpt-5p4-prompting-guide.md
                    ├── latest-model.md
                    └── upgrading-to-gpt-5p4.md
```

### 4.2 调用方（上游依赖）

| 调用方 | 文件路径 | 使用方式 |
|--------|----------|----------|
| **core/skills/system** | `core/src/skills/system.rs` | `pub(crate) use codex_skills::{install_system_skills, system_cache_root_dir};` |
| **core/skills/manager** | `core/src/skills/manager.rs` | `SkillsManager::new()` 中调用 `install_system_skills()` |
| **core/state/service** | `core/src/state/service.rs` | 持有 `Arc<SkillsManager>` |
| **thread_manager** | `core/src/thread_manager.rs` | 创建 `SkillsManager` 实例 |

### 4.3 被调用方（下游依赖）

本模块为底层库，无下游 Rust 代码依赖。嵌入的 Python 脚本可能被用户通过 Codex 调用执行。

### 4.4 关键函数调用链

```
Codex 启动
    │
    ▼
thread_manager::ThreadManager::new()
    │
    ▼
SkillsManager::new(codex_home, plugins_manager, bundled_skills_enabled)
    │
    ├── bundled_skills_enabled == false
    │       └── uninstall_system_skills(codex_home)  # 清理系统技能
    │
    └── bundled_skills_enabled == true
            └── install_system_skills(codex_home)    # 安装/更新系统技能
                    │
                    ├── system_cache_root_dir()      # 确定目标路径
                    ├── embedded_system_skills_fingerprint()  # 计算指纹
                    ├── read_marker()                # 读取现有指纹
                    ├── write_embedded_dir()         # 写入目录
                    └── fs::write(marker)            # 写入新指纹
```

---

## 依赖与外部交互

### 5.1 Rust 依赖

| Crate | 用途 | 版本来源 |
|-------|------|----------|
| `include_dir` | 编译时嵌入目录到二进制 | workspace |
| `thiserror` | 错误类型派生宏 | workspace |
| `codex-utils-absolute-path` | 安全的绝对路径操作 | workspace |

### 5.2 外部工具/脚本依赖

嵌入的 Python 脚本依赖：

| 脚本 | 外部依赖 | 用途 |
|------|----------|------|
| `init_skill.py` | `generate_openai_yaml.py` | 生成 agents/openai.yaml |
| `quick_validate.py` | `pyyaml` | YAML 解析验证 |
| `generate_openai_yaml.py` | `pyyaml` | YAML 生成 |
| `install-skill-from-github.py` | `github_utils.py`, `git`, `curl` | GitHub 下载/克隆 |
| `list-skills.py` | `github_utils.py` | GitHub API 调用 |
| `github_utils.py` | 标准库 | HTTP 请求、环境变量读取 |

### 5.3 文件系统交互

| 路径 | 类型 | 说明 |
|------|------|------|
| `$CODEX_HOME/skills` | 目录 | 技能根目录 |
| `$CODEX_HOME/skills/.system` | 目录 | 系统技能缓存目录 |
| `$CODEX_HOME/skills/.system/.codex-system-skills.marker` | 文件 | 指纹标记文件 |
| `$HOME/.agents/skills` | 目录 | 用户技能目录（legacy） |

### 5.4 环境变量

| 变量 | 用途 |
|------|------|
| `CODEX_HOME` | 确定 Codex 配置和技能存储的根目录 |
| `GITHUB_TOKEN` / `GH_TOKEN` | skill-installer 脚本用于 GitHub API 认证 |

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 并发安全风险

**问题**：`install_system_skills` 函数无并发控制，多进程同时启动时可能产生竞态条件。

```rust
// 当前实现无文件锁
if dest_system.as_path().exists() {
    fs::remove_dir_all(dest_system.as_path())?;  // 进程A删除
}
write_embedded_dir(&SYSTEM_SKILLS_DIR, &dest_system)?;  // 进程B可能同时写入
```

**影响**：低概率导致系统技能目录损坏或不完整。

**缓解**：Codex 通常为单实例运行，实际风险较低。

#### 6.1.2 磁盘空间风险

**问题**：系统技能目录在更新时先删除后重建，如果磁盘空间不足可能导致技能完全不可用。

**建议**：添加磁盘空间预检查，或采用原子替换策略（写入临时目录后重命名）。

#### 6.1.3 权限问题

**问题**：`$CODEX_HOME` 目录可能位于只读文件系统或用户无写入权限的位置。

**当前处理**：错误通过 `SystemSkillsError::Io` 返回，由调用方处理。

### 6.2 边界条件

| 边界条件 | 行为 |
|----------|------|
| 指纹文件损坏 | 视为不匹配，重新安装 |
| 系统技能目录被手动修改 | 指纹不匹配时会重新安装（覆盖修改） |
| 嵌入目录为空 | 正常处理，创建空目录 |
| 路径包含非 UTF-8 字符 | 使用 `to_string_lossy()` 处理，可能丢失信息 |
| 符号链接 | `include_dir` 会跟随符号链接嵌入目标内容 |

### 6.3 测试覆盖

当前测试仅覆盖指纹遍历逻辑：

```rust
// lib.rs:172-195
#[cfg(test)]
mod tests {
    #[test]
    fn fingerprint_traverses_nested_entries() {
        // 验证指纹计算正确遍历嵌套条目
    }
}
```

**测试缺口**：
- 无文件系统 I/O 测试（需要临时目录）
- 无并发测试
- 无错误路径测试（权限不足、磁盘满等）

### 6.4 改进建议

#### 6.4.1 原子性改进

```rust
// 建议：使用临时目录 + 原子重命名
fn install_system_skills_atomic(codex_home: &Path) -> Result<(), SystemSkillsError> {
    let temp_dir = dest_system.with_extension(".tmp");
    write_embedded_dir(&SYSTEM_SKILLS_DIR, &temp_dir)?;
    fs::write(temp_dir.join(SYSTEM_SKILLS_MARKER_FILENAME), ...)?;
    
    // 原子替换
    fs::rename(&temp_dir, &dest_system)?;
    Ok(())
}
```

#### 6.4.2 并发控制

```rust
// 建议：使用文件锁
use fs2::FileExt;

let lock_file = fs::OpenOptions::new()
    .write(true)
    .create(true)
    .open(codex_home.join(".system-skills.lock"))?;
lock_file.try_lock_exclusive()?;  // 或 lock_exclusive() 阻塞等待
```

#### 6.4.3 增强测试

- 添加 `tempfile` 依赖进行 I/O 测试
- 使用 `std::os::unix::fs::PermissionsExt` 测试权限错误处理
- 添加并发测试验证竞态条件处理

#### 6.4.4 可观测性增强

```rust
// 建议：添加结构化日志
tracing::info!(
    target: "codex::skills::system",
    fingerprint = %expected_fingerprint,
    path = %dest_system.display(),
    "installing system skills"
);
```

### 6.5 架构演进建议

当前系统技能为静态嵌入，未来可考虑：

1. **远程更新**：允许从远程源获取最新技能，而非仅依赖二进制更新
2. **按需加载**：延迟解压特定技能，减少启动时间和磁盘占用
3. **版本管理**：支持多版本技能并存，便于回滚
4. **用户自定义系统技能**：允许高级用户覆盖或扩展系统技能

---

## 附录：关键代码引用

### A.1 完整 lib.rs 结构

```rust
// 公开 API
pub fn system_cache_root_dir(codex_home: &Path) -> PathBuf
pub fn install_system_skills(codex_home: &Path) -> Result<(), SystemSkillsError>

// 内部实现
fn system_cache_root_dir_abs(codex_home: &AbsolutePathBuf) -> std::io::Result<AbsolutePathBuf>
fn read_marker(path: &AbsolutePathBuf) -> Result<String, SystemSkillsError>
fn embedded_system_skills_fingerprint() -> String
fn collect_fingerprint_items(dir: &Dir<'_>, items: &mut Vec<(String, Option<u64>)>)
fn write_embedded_dir(dir: &Dir<'_>, dest: &AbsolutePathBuf) -> Result<(), SystemSkillsError>

// 错误类型
#[derive(Debug, Error)]
pub enum SystemSkillsError { ... }
```

### A.2 核心常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `SYSTEM_SKILLS_DIR` | `include_dir!(...)` | 编译时嵌入的目录 |
| `SYSTEM_SKILLS_DIR_NAME` | `".system"` | 系统技能子目录名 |
| `SKILLS_DIR_NAME` | `"skills"` | 技能根目录名 |
| `SYSTEM_SKILLS_MARKER_FILENAME` | `".codex-system-skills.marker"` | 指纹文件名 |
| `SYSTEM_SKILLS_MARKER_SALT` | `"v1"` | 指纹盐值 |

---

*文档生成时间：2026-03-22*
*基于代码版本：codex-rs/skills/src/lib.rs (195 lines)*
