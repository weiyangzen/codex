# project_doc_tests.rs 研究文档

## 场景与职责

`project_doc_tests.rs` 是 `codex-core` 库中 `project_doc` 模块的集成测试文件。它负责验证项目级文档（AGENTS.md）的发现、读取、截断、合并以及与功能特性（如 js_repl）的集成逻辑。

该测试文件确保以下核心场景的正确性：
- AGENTS.md 文件的自动发现机制（从当前工作目录向上遍历至项目根目录）
- 文件大小限制与截断行为
- 多层级 AGENTS.md 文件的合并（根目录 + 子目录）
- 功能特性（Feature）对用户指令的附加影响
- 回退文件名（fallback filenames）机制
- 项目根标记（project_root_markers）的自定义配置

## 功能点目的

### 1. 项目文档发现与读取测试
验证 `get_user_instructions()` 和 `discover_project_doc_paths()` 函数的核心行为：
- **文件缺失场景**：当 AGENTS.md 不存在且未配置系统指令时，应返回 `None`
- **小文件读取**：小于 `project_doc_max_bytes` 限制的文件应完整返回
- **大文件截断**：超出限制的文件应被截断至限制大小
- **跨目录发现**：在嵌套工作目录中应能定位到仓库根目录的 AGENTS.md

### 2. 功能特性集成测试
验证 `Feature` 系统对用户指令的影响：
- **JsRepl 特性**：启用时自动附加 JavaScript REPL 使用说明
- **JsReplToolsOnly 特性**：进一步限制工具调用必须通过 js_repl
- **ImageDetailOriginal 特性**：不影响指令内容，仅作为功能开关
- **Apps 特性**：不自动附加用户指令

### 3. 多源合并测试
验证多种指令来源的优先级和合并逻辑：
- 系统指令与项目文档的合并（使用 `PROJECT_DOC_SEPARATOR` 分隔）
- 根目录与子目录 AGENTS.md 的级联合并
- `AGENTS.override.md` 优先于 `AGENTS.md`
- 回退文件名在默认文件名缺失时的使用

### 4. 配置选项测试
验证配置参数对文档发现的影响：
- `project_root_markers`：自定义项目根目录标记（如 `.codex-root`）
- `project_doc_fallback_filenames`：配置备选文件名列表
- `project_doc_max_bytes`：零值禁用文档功能

## 具体技术实现

### 关键测试辅助函数

```rust
// 创建测试配置
async fn make_config(root: &TempDir, limit: usize, instructions: Option<&str>) -> Config

// 创建带回退文件名的配置
async fn make_config_with_fallback(
    root: &TempDir, 
    limit: usize, 
    instructions: Option<&str>, 
    fallbacks: &[&str]
) -> Config

// 创建带自定义根标记的配置
async fn make_config_with_project_root_markers(
    root: &TempDir,
    limit: usize,
    instructions: Option<&str>,
    markers: &[&str],
) -> Config

// 创建测试技能
fn create_skill(codex_home: PathBuf, name: &str, description: &str)
```

### 核心测试用例分析

#### 文件截断测试
```rust
#[tokio::test]
async fn doc_larger_than_limit_is_truncated() {
    const LIMIT: usize = 1024;
    let tmp = tempfile::tempdir().expect("tempdir");
    let huge = "A".repeat(LIMIT * 2); // 2 KiB
    fs::write(tmp.path().join("AGENTS.md"), &huge).unwrap();
    
    let res = get_user_instructions(&make_config(&tmp, LIMIT, None).await)
        .await
        .expect("doc expected");
    
    assert_eq!(res.len(), LIMIT, "doc should be truncated to LIMIT bytes");
    assert_eq!(res, huge[..LIMIT]);
}
```

#### 层级合并测试
```rust
#[tokio::test]
async fn concatenates_root_and_cwd_docs() {
    let repo = tempfile::tempdir().expect("tempdir");
    // 模拟 git 仓库
    std::fs::write(repo.path().join(".git"), "gitdir: /path/to/actual/git/dir\n").unwrap();
    fs::write(repo.path().join("AGENTS.md"), "root doc").unwrap();
    
    let nested = repo.path().join("workspace/crate_a");
    std::fs::create_dir_all(&nested).unwrap();
    fs::write(nested.join("AGENTS.md"), "crate doc").unwrap();
    
    let mut cfg = make_config(&repo, 4096, None).await;
    cfg.cwd = nested;
    
    let res = get_user_instructions(&cfg).await.expect("doc expected");
    assert_eq!(res, "root doc\n\ncrate doc");  // 根目录文档在前
}
```

#### JsRepl 特性测试
```rust
#[tokio::test]
async fn js_repl_instructions_are_appended_when_enabled() {
    let tmp = tempfile::tempdir().expect("tempdir");
    let mut cfg = make_config(&tmp, 4096, None).await;
    cfg.features.enable(Feature::JsRepl).expect("test config should allow js_repl");
    
    let res = get_user_instructions(&cfg).await.expect("js_repl instructions expected");
    // 验证包含 JsRepl 使用说明
    assert!(res.contains("## JavaScript REPL (Node)"));
    assert!(res.contains("codex.tool"));
    assert!(res.contains("codex.emitImage"));
}
```

## 关键代码路径与文件引用

### 被测代码位置
| 被测功能 | 实现文件 |
|---------|---------|
| `get_user_instructions()` | `codex-rs/core/src/project_doc.rs:79` |
| `read_project_docs()` | `codex-rs/core/src/project_doc.rs:128` |
| `discover_project_doc_paths()` | `codex-rs/core/src/project_doc.rs:186` |
| `PROJECT_DOC_SEPARATOR` | `codex-rs/core/src/project_doc.rs:41` |

### 常量定义
```rust
pub const DEFAULT_PROJECT_DOC_FILENAME: &str = "AGENTS.md";
pub const LOCAL_PROJECT_DOC_FILENAME: &str = "AGENTS.override.md";
const PROJECT_DOC_SEPARATOR: &str = "\n\n--- project-doc ---\n\n";
```

### 调用方引用
- `codex-rs/core/src/codex.rs:486` - `get_user_instructions(&config).await` 在会话启动时调用

## 依赖与外部交互

### 内部依赖
- `crate::config::ConfigBuilder` - 测试配置构建
- `crate::features::Feature` - 功能特性开关
- `crate::project_doc::*` - 被测模块

### 外部依赖
- `tempfile::TempDir` - 临时目录创建
- `tokio::test` - 异步测试运行时
- `pretty_assertions` - 测试断言增强

### 配置层交互
测试通过 `ConfigBuilder` 和 `ConfigLayerStack` 模拟配置加载：
```rust
let mut config = ConfigBuilder::default()
    .codex_home(codex_home.path().to_path_buf())
    .build()
    .await
    .expect("defaults for test should always succeed");
```

## 风险、边界与改进建议

### 已知边界条件
1. **零字节限制**：`project_doc_max_bytes = 0` 应完全禁用文档功能
2. **空文件处理**：空 AGENTS.md 文件会被跳过（通过 `text.trim().is_empty()` 检查）
3. **符号链接**：`discover_project_doc_paths` 允许符号链接，但 dangling links 在打开时会失败
4. **编码问题**：使用 `String::from_utf8_lossy` 处理非 UTF-8 内容，可能丢失信息

### 潜在风险
1. **测试硬编码**：JsRepl 指令内容在测试中硬编码，若 `render_js_repl_instructions()` 实现变更，测试会失败
2. **并发安全**：测试使用 `tempfile::tempdir()` 创建独立目录，无并发冲突风险
3. **平台差异**：路径处理使用 `dunce::canonicalize`，在 Windows 上行为可能不同

### 改进建议
1. **快照测试**：对长文本（如 JsRepl 指令）使用 `insta` 快照测试，便于维护
2. **边界测试**：增加对非 UTF-8 编码文件、超大文件（>100MB）、深层嵌套目录的测试
3. **错误场景**：增加对权限拒绝（Permission Denied）等 IO 错误的测试覆盖
4. **性能测试**：对大量 AGENTS.md 文件的发现性能进行基准测试

### 测试覆盖缺口
- 未测试 `HIERARCHICAL_AGENTS_MESSAGE`（ChildAgentsMd 特性）的完整内容
- 未测试 `skills` 目录对项目文档的影响（测试显示 skills 不应附加到项目文档）
- 未测试多层级（>2 层）目录结构下的文档合并顺序
