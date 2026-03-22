# codex-rs/skills/src/assets 深度研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 目录定位

`codex-rs/skills/src/assets` 是 **codex-skills** crate 的嵌入式资源目录，负责存储**预置的系统级技能（System Skills）**样本。这些技能在编译时被嵌入到二进制中，在运行时解压到用户的 `CODEX_HOME/skills/.system` 目录。

### 1.2 核心职责

| 职责 | 说明 |
|------|------|
| **技能模板存储** | 存放可复用的技能模板，供用户创建新技能时参考 |
| **系统技能分发** | 将 OpenAI 官方维护的技能随 Codex CLI 一起分发 |
| **自举能力** | 提供 `skill-creator` 和 `skill-installer` 技能，实现技能的自我扩展 |

### 1.3 使用场景

1. **首次启动**: Codex CLI 首次启动时，自动将嵌入的技能解压到用户目录
2. **技能更新**: 当 Codex 版本升级时，通过指纹比对检测技能变化并重新安装
3. **离线使用**: 用户无需网络即可使用系统预置技能
4. **技能创建**: 用户使用 `skill-creator` 技能创建新技能
5. **技能安装**: 用户使用 `skill-installer` 从 GitHub 安装社区技能

---

## 功能点目的

### 2.1 当前包含的系统技能

目录 `src/assets/samples/` 下包含三个系统技能：

#### 2.1.1 openai-docs

**用途**: 提供 OpenAI 官方文档查询和 GPT-5.4 升级指导

**文件结构**:
```
openai-docs/
├── SKILL.md                          # 技能主文档
├── LICENSE.txt                       # 许可证
├── agents/openai.yaml               # UI 元数据
├── assets/                          # 图标资源
│   ├── openai-small.svg
│   └── openai.png
└── references/                      # 参考文档
    ├── gpt-5p4-prompting-guide.md   # GPT-5.4 提示词升级指南
    ├── latest-model.md              # 最新模型推荐
    └── upgrading-to-gpt-5p4.md      # GPT-5.4 升级指南
```

**触发条件**: 用户询问 OpenAI 产品/API、模型选择建议或 GPT-5.4 升级相关问题时触发

#### 2.1.2 skill-creator

**用途**: 指导用户创建新的 Codex 技能

**文件结构**:
```
skill-creator/
├── SKILL.md                          # 技能创建指南
├── license.txt                       # 许可证
├── agents/openai.yaml               # UI 元数据
├── assets/                          # 图标资源
├── references/
│   └── openai_yaml.md               # openai.yaml 字段说明
└── scripts/                         # 辅助脚本
    ├── generate_openai_yaml.py      # 生成 UI 元数据
    ├── init_skill.py                # 初始化新技能
    └── quick_validate.py            # 快速验证技能
```

**触发条件**: 用户要求创建新技能或更新现有技能时触发

**核心功能脚本**:
- `init_skill.py`: 创建技能目录结构、SKILL.md 模板、agents/openai.yaml
- `generate_openai_yaml.py`: 根据技能信息生成 UI 元数据
- `quick_validate.py`: 验证 SKILL.md 格式、YAML frontmatter 等

#### 2.1.3 skill-installer

**用途**: 从 GitHub 安装社区技能

**文件结构**:
```
skill-installer/
├── SKILL.md                          # 安装指南
├── LICENSE.txt                       # 许可证
├── agents/openai.yaml               # UI 元数据
├── assets/                          # 图标资源
└── scripts/                         # 安装脚本
    ├── github_utils.py              # GitHub API 工具
    ├── install-skill-from-github.py # 主安装脚本
    └── list-skills.py               # 列出可安装技能
```

**触发条件**: 用户要求列出或安装技能时触发

**核心功能脚本**:
- `list-skills.py`: 从 openai/skills 仓库获取技能列表
- `install-skill-from-github.py`: 支持多种方式安装（zip 下载、git sparse-checkout）
- `github_utils.py`: 封装 GitHub API 请求，支持 GITHUB_TOKEN 认证

### 2.2 技能加载层级

Codex 技能系统采用四层架构，系统技能位于第三层：

```
SkillScope::Repo    (项目级)    # ./.agents/skills/ 或项目根目录 skills/
SkillScope::User    (用户级)    # ~/.agents/skills/ 或 ~/.codex/skills/
SkillScope::System  (系统级)    # ~/.codex/skills/.system/ ← 本目录内容
SkillScope::Admin   (系统级)    # /etc/codex/skills/
```

---

## 具体技术实现

### 3.1 嵌入与解压机制

#### 3.1.1 编译时嵌入

使用 `include_dir` crate 在编译时将整个 `samples` 目录嵌入二进制：

```rust
// codex-rs/skills/src/lib.rs
const SYSTEM_SKILLS_DIR: Dir = include_dir::include_dir!("$CARGO_MANIFEST_DIR/src/assets/samples");
```

**BUILD.bazel 配置**:
```starlark
codex_rust_crate(
    name = "skills",
    crate_name = "codex_skills",
    compile_data = glob(
        include = ["**"],
        exclude = [
            "**/* *",
            "BUILD.bazel",
            "Cargo.toml",
        ],
        allow_empty = True,
    ),
)
```

#### 3.1.2 增量安装与指纹检测

为避免每次启动都重复写入，使用指纹机制检测变化：

```rust
// 核心指纹计算逻辑
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

**安装流程**:
1. 检查目标目录是否存在指纹文件 `.codex-system-skills.marker`
2. 比对指纹，若匹配则跳过安装
3. 若不匹配，删除旧目录，写入新内容
4. 写入新指纹文件

### 3.2 关键数据结构

#### 3.2.1 技能元数据 (SkillMetadata)

```rust
// codex-rs/core/src/skills/model.rs
pub struct SkillMetadata {
    pub name: String,                           // 技能名称
    pub description: String,                    // 描述（触发依据）
    pub short_description: Option<String>,      // 短描述（UI 展示）
    pub interface: Option<SkillInterface>,      // UI 界面配置
    pub dependencies: Option<SkillDependencies>, // 工具依赖（MCP 等）
    pub policy: Option<SkillPolicy>,            // 调用策略
    pub permission_profile: Option<PermissionProfile>, // 权限配置
    pub managed_network_override: Option<SkillManagedNetworkOverride>,
    pub path_to_skills_md: PathBuf,             // SKILL.md 路径
    pub scope: SkillScope,                      // 作用域
}
```

#### 3.2.2 技能界面配置 (SkillInterface)

```rust
pub struct SkillInterface {
    pub display_name: Option<String>,           // 显示名称
    pub short_description: Option<String>,      // 短描述（25-64 字符）
    pub icon_small: Option<PathBuf>,            // 小图标路径
    pub icon_large: Option<PathBuf>,            // 大图标路径
    pub brand_color: Option<String>,            // 品牌色（#RRGGBB）
    pub default_prompt: Option<String>,         // 默认提示词
}
```

### 3.3 技能解析流程

SKILL.md 采用 YAML Frontmatter + Markdown 正文格式：

```markdown
---
name: skill-name
description: When to use this skill...
metadata:
  short-description: Short UI label
---

# Skill Title

Content...
```

**解析步骤** (`loader.rs`):
1. 读取文件内容
2. 提取 `---` 包围的 YAML frontmatter
3. 解析 YAML 获取 `name`, `description`, `metadata`
4. 读取 `agents/openai.yaml` 获取界面配置和依赖
5. 验证字段长度限制（name ≤ 64, description ≤ 1024 等）
6. 规范化路径和命名空间

### 3.4 隐式调用检测

系统通过分析用户命令检测隐式技能调用：

```rust
// invocation_utils.rs
pub(crate) async fn maybe_emit_implicit_skill_invocation(
    sess: &Session,
    turn_context: &TurnContext,
    command: &str,
    workdir: Option<&str>,
)
```

**检测模式**:
1. **脚本执行检测**: 检测 `python script.py`, `bash script.sh` 等命令
2. **文档读取检测**: 检测 `cat SKILL.md`, `head doc.md` 等命令
3. **路径匹配**: 将命令中的路径与技能目录匹配

---

## 关键代码路径与文件引用

### 4.1 核心文件映射

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/skills/src/lib.rs` | 系统技能安装、指纹计算、目录写入 |
| `codex-rs/skills/build.rs` | Cargo 构建脚本，监听资源变化 |
| `codex-rs/skills/Cargo.toml` | crate 配置，依赖声明 |
| `codex-rs/skills/BUILD.bazel` | Bazel 构建配置 |
| `codex-rs/core/src/skills/system.rs` | 系统技能管理封装 |
| `codex-rs/core/src/skills/manager.rs` | SkillsManager，技能加载缓存 |
| `codex-rs/core/src/skills/loader.rs` | 技能扫描、解析、验证 |
| `codex-rs/core/src/skills/model.rs` | 技能数据结构定义 |
| `codex-rs/core/src/skills/invocation_utils.rs` | 隐式调用检测 |

### 4.2 调用链

```
ThreadManager::new()
  └── SkillsManager::new(codex_home, plugins_manager, bundled_skills_enabled)
        └── install_system_skills(&codex_home)  [若启用系统技能]
              └── codex_skills::install_system_skills()
                    ├── system_cache_root_dir()  →  ~/.codex/skills/.system
                    ├── embedded_system_skills_fingerprint()
                    ├── write_embedded_dir()     →  解压嵌入目录
                    └── 写入 .codex-system-skills.marker

Session::spawn()
  └── skills_manager.skills_for_config(&config)
        └── load_skills_from_roots(roots)
              └── discover_skills_under_root()  [包含系统技能根目录]
```

### 4.3 资源文件引用

```rust
// 嵌入目录常量
const SYSTEM_SKILLS_DIR: Dir = include_dir!("$CARGO_MANIFEST_DIR/src/assets/samples");

// 目标目录常量
const SYSTEM_SKILLS_DIR_NAME: &str = ".system";
const SKILLS_DIR_NAME: &str = "skills";
const SYSTEM_SKILLS_MARKER_FILENAME: &str = ".codex-system-skills.marker";
const SYSTEM_SKILLS_MARKER_SALT: &str = "v1";
```

---

## 依赖与外部交互

### 5.1 内部依赖

| 依赖 crate | 用途 |
|-----------|------|
| `codex-utils-absolute-path` | 绝对路径处理，防止目录遍历攻击 |
| `include_dir` | 编译时嵌入目录到二进制 |
| `thiserror` | 错误类型定义 |

### 5.2 外部依赖（通过脚本）

| 脚本 | 外部依赖 |
|------|---------|
| `init_skill.py` | Python 3, PyYAML |
| `quick_validate.py` | Python 3, PyYAML |
| `generate_openai_yaml.py` | Python 3, PyYAML |
| `install-skill-from-github.py` | Python 3, urllib, zipfile, git（可选） |
| `list-skills.py` | Python 3, urllib, GitHub API |

### 5.3 运行时交互

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Codex CLI     │────▶│  codex-skills    │────▶│  ~/.codex/      │
│   (Rust)        │     │  (embedded)      │     │  skills/.system/│
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │
         ▼
┌─────────────────┐
│  User Skills    │
│  ~/.codex/skills│
└─────────────────┘
```

### 5.4 配置交互

系统技能可通过 `config.toml` 禁用：

```toml
[skills.bundled]
enabled = false
```

当 `bundled_skills_enabled = false` 时：
1. `SkillsManager::new()` 调用 `uninstall_system_skills()` 清理系统技能目录
2. 技能加载时排除 `SkillScope::System` 的技能

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 安全风险

| 风险点 | 说明 | 缓解措施 |
|-------|------|---------|
| 目录遍历 | 恶意技能可能尝试访问上级目录 | `resolve_asset_path()` 函数检查 `..` 和绝对路径 |
| 符号链接攻击 | 系统技能目录可能被符号链接劫持 | 系统技能由 Codex 自身写入，不跟随符号链接 |
| 脚本执行 | Python 脚本可能执行恶意代码 | 脚本由用户显式调用，非自动执行 |

#### 6.1.2 兼容性风险

| 风险点 | 说明 |
|-------|------|
| 指纹盐值变更 | `SYSTEM_SKILLS_MARKER_SALT` 变更会导致所有用户重新安装 |
| 路径长度限制 | Windows 长路径可能超出限制 |
| 并发写入 | 多进程同时启动可能导致竞争条件 |

### 6.2 边界条件

1. **空技能目录**: `samples` 目录为空时，`include_dir` 仍有效，但无技能可安装
2. **磁盘空间不足**: 写入过程中可能失败，留下不完整目录
3. **权限问题**: 用户无写入 `CODEX_HOME` 权限时安装失败
4. **字符编码**: 假设所有文本文件为 UTF-8 编码

### 6.3 改进建议

#### 6.3.1 短期改进

1. **原子写入**: 使用临时目录 + 原子重命名避免不完整安装
   ```rust
   // 建议实现
   fn atomic_install(src: &Dir, dest: &Path) -> Result<()> {
       let tmp = dest.with_extension(".tmp");
       write_embedded_dir(src, &tmp)?;
       fs::rename(&tmp, dest)?;
       Ok(())
   }
   ```

2. **并发锁**: 添加文件锁防止多进程竞争
   ```rust
   use fs2::FileExt;
   let lock = fs::File::create(dest.join(".install.lock"))?;
   lock.try_lock_exclusive()?;
   ```

3. **更详细的错误报告**: 当前错误信息较简略，可添加上下文

#### 6.3.2 中期改进

1. **增量更新**: 当前是全量替换，可实现文件级增量更新
2. **压缩优化**: 嵌入目录可考虑压缩减少二进制体积
3. **签名验证**: 添加技能包签名验证，防止篡改

#### 6.3.3 长期改进

1. **技能市场集成**: 与远程技能市场联动，自动更新系统技能
2. **技能依赖解析**: 支持技能间的依赖关系
3. **版本管理**: 支持多版本技能并存和切换

### 6.4 测试覆盖

当前测试覆盖：
- `fingerprint_traverses_nested_entries`: 指纹计算遍历测试
- `manager_tests.rs`: SkillsManager 缓存、配置变更测试

建议补充：
- 并发安装测试
- 磁盘满错误处理测试
- 权限拒绝测试
- 大文件（>100MB）处理测试

---

## 附录：文件清单

### Rust 源码

```
codex-rs/skills/
├── build.rs
├── Cargo.toml
├── BUILD.bazel
└── src/
    └── lib.rs

codex-rs/core/src/skills/
├── mod.rs
├── model.rs
├── manager.rs
├── manager_tests.rs
├── loader.rs
├── loader_tests.rs
├── system.rs
├── invocation_utils.rs
├── invocation_utils_tests.rs
├── injection.rs
├── injection_tests.rs
├── env_var_dependencies.rs
├── remote.rs
└── render.rs
```

### 嵌入资源

```
codex-rs/skills/src/assets/samples/
├── openai-docs/
│   ├── SKILL.md
│   ├── LICENSE.txt
│   ├── agents/openai.yaml
│   ├── assets/openai-small.svg
│   ├── assets/openai.png
│   └── references/
│       ├── gpt-5p4-prompting-guide.md
│       ├── latest-model.md
│       └── upgrading-to-gpt-5p4.md
├── skill-creator/
│   ├── SKILL.md
│   ├── license.txt
│   ├── agents/openai.yaml
│   ├── assets/skill-creator-small.svg
│   ├── assets/skill-creator.png
│   ├── references/openai_yaml.md
│   └── scripts/
│       ├── generate_openai_yaml.py
│       ├── init_skill.py
│       └── quick_validate.py
└── skill-installer/
    ├── SKILL.md
    ├── LICENSE.txt
    ├── agents/openai.yaml
    ├── assets/skill-installer-small.svg
    ├── assets/skill-installer.png
    └── scripts/
        ├── github_utils.py
        ├── install-skill-from-github.py
        └── list-skills.py
```

---

*文档生成时间: 2026-03-22*
*研究范围: codex-rs/skills/src/assets 及其调用链*
