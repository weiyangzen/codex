# realtime_context_tests.rs 研究文档

## 场景与职责

`realtime_context_tests.rs` 是 `realtime_context.rs` 模块的单元测试文件，负责验证实时启动上下文构建的核心功能。由于实时上下文构建涉及文件系统操作、Git 仓库解析和复杂的数据格式化，这些测试使用临时目录和模拟数据来隔离外部依赖。

该测试文件覆盖以下关键场景：
- 工作区段落构建（目录树渲染）
- 最近工作段落构建（线程分组和格式化）
- 边界条件处理（空目录、缺失 Git 仓库等）

## 功能点目的

### 1. 工作区段落测试
验证 `build_workspace_section_with_user_root()` 函数：
- **空目录处理**：当目录没有有意义的结构时返回 `None`
- **目录树渲染**：正确列出目录条目（文件和子目录）
- **多根目录处理**：同时处理 CWD、Git 根目录和用户主目录

### 2. 最近工作段落测试
验证 `build_recent_work_section()` 函数：
- **Git 仓库分组**：正确将线程按 Git 仓库根目录分组
- **混合分组**：处理 Git 仓库内目录和非 Git 目录的混合场景
- **信息展示**：正确显示会话数量、最新活动、分支信息和用户查询

## 具体技术实现

### 测试辅助函数

```rust
/// 创建测试用的 ThreadMetadata
fn thread_metadata(cwd: &str, title: &str, first_user_message: &str) -> ThreadMetadata {
    ThreadMetadata {
        id: ThreadId::new(),
        rollout_path: PathBuf::from("/tmp/rollout.jsonl"),
        created_at: Utc.timestamp_opt(1_709_251_100, 0).single().expect("valid timestamp"),
        updated_at: Utc.timestamp_opt(1_709_251_200, 0).single().expect("valid timestamp"),
        source: "cli".to_string(),
        agent_nickname: None,
        agent_role: None,
        model_provider: "test-provider".to_string(),
        model: Some("gpt-5".to_string()),
        reasoning_effort: None,
        cwd: PathBuf::from(cwd),
        cli_version: "test".to_string(),
        title: title.to_string(),
        sandbox_policy: "workspace-write".to_string(),
        approval_mode: "never".to_string(),
        tokens_used: 0,
        first_user_message: Some(first_user_message.to_string()),
        archived_at: None,
        git_sha: None,
        git_branch: Some("main".to_string()),
        git_origin_url: None,
    }
}
```

### 核心测试用例

#### 工作区段落 - 空目录
```rust
#[test]
fn workspace_section_requires_meaningful_structure() {
    let cwd = TempDir::new().expect("tempdir");
    assert_eq!(
        build_workspace_section_with_user_root(cwd.path(), None),
        None  // 空目录应返回 None
    );
}
```

#### 工作区段落 - 目录树渲染
```rust
#[test]
fn workspace_section_includes_tree_when_entries_exist() {
    let cwd = TempDir::new().expect("tempdir");
    fs::create_dir(cwd.path().join("docs")).expect("create docs dir");
    fs::write(cwd.path().join("README.md"), "hello").expect("write readme");
    
    let section = build_workspace_section_with_user_root(cwd.path(), None)
        .expect("workspace section");
    
    assert!(section.contains("Working directory tree:"));
    assert!(section.contains("- docs/"));
    assert!(section.contains("- README.md"));
}
```

#### 工作区段落 - 多根目录
```rust
#[test]
fn workspace_section_includes_user_root_tree_when_distinct() {
    let root = TempDir::new().expect("tempdir");
    let cwd = root.path().join("cwd");
    let git_root = root.path().join("git");
    let user_root = root.path().join("home");
    
    // 设置 CWD
    fs::create_dir_all(cwd.join("docs")).expect("create cwd docs dir");
    fs::write(cwd.join("README.md"), "hello").expect("write cwd readme");
    
    // 设置 Git 根目录
    fs::create_dir_all(git_root.join(".git")).expect("create git dir");
    fs::write(git_root.join("Cargo.toml"), "[workspace]").expect("write git root marker");
    
    // 设置用户主目录
    fs::create_dir_all(user_root.join("code")).expect("create user root child");
    fs::write(user_root.join(".zshrc"), "export TEST=1").expect("write home file");
    
    let section = build_workspace_section_with_user_root(cwd.as_path(), Some(user_root))
        .expect("workspace section");
    
    assert!(section.contains("User root tree:"));
    assert!(section.contains("- code/"));
    assert!(!section.contains("- .zshrc"));  // 隐藏文件被过滤
}
```

#### 最近工作段落 - Git 分组
```rust
#[test]
fn recent_work_section_groups_threads_by_cwd() {
    let root = TempDir::new().expect("tempdir");
    let repo = root.path().join("repo");
    let workspace_a = repo.join("workspace-a");
    let workspace_b = repo.join("workspace-b");
    let outside = root.path().join("outside");
    
    // 初始化 Git 仓库
    fs::create_dir(&repo).expect("create repo dir");
    Command::new("git")
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .args(["init"])
        .current_dir(&repo)
        .output()
        .expect("git init");
    
    fs::create_dir_all(&workspace_a).expect("create workspace a");
    fs::create_dir_all(&workspace_b).expect("create workspace b");
    fs::create_dir_all(&outside).expect("create outside dir");
    
    let recent_threads = vec![
        thread_metadata(workspace_a.to_string_lossy().as_ref(), "...", "Log the startup context"),
        thread_metadata(workspace_b.to_string_lossy().as_ref(), "...", "Remove memories"),
        thread_metadata(outside.to_string_lossy().as_ref(), "", "Inspect flaky test"),
    ];
    let current_cwd = workspace_a;
    let repo = fs::canonicalize(repo).expect("canonicalize repo");
    
    let section = build_recent_work_section(current_cwd.as_path(), &recent_threads)
        .expect("recent work section");
    
    // 验证 Git 仓库分组
    assert!(section.contains(&format!("### Git repo: {}", repo.display())));
    assert!(section.contains("Recent sessions: 2"));  // workspace-a 和 workspace-b 在同一组
    assert!(section.contains("User asks:"));
    
    // 验证非 Git 目录单独分组
    assert!(section.contains(&format!("### Directory: {}", outside.display())));
}
```

## 关键代码路径与文件引用

### 被测代码
| 被测函数 | 实现文件 | 行号 |
|---------|---------|------|
| `build_workspace_section_with_user_root()` | `realtime_context.rs` | 273 |
| `build_recent_work_section()` | `realtime_context.rs` | 144 |
| `render_tree()` | `realtime_context.rs` | 331 |
| `collect_tree_lines()` | `realtime_context.rs` | 341 |
| `format_thread_group()` | `realtime_context.rs` | 412 |

### 测试模块结构
```rust
#[cfg(test)]
#[path = "realtime_context_tests.rs"]
mod tests;
```

## 依赖与外部交互

### 内部依赖
```rust
use super::build_recent_work_section;
use super::build_workspace_section_with_user_root;
use chrono::{TimeZone, Utc};
use codex_protocol::ThreadId;
use codex_state::ThreadMetadata;
use pretty_assertions::assert_eq;
```

### 外部依赖
- `tempfile::TempDir` - 临时目录创建
- `std::fs` - 文件系统操作
- `std::process::Command` - 执行 Git 命令

### Git 命令依赖
测试使用系统 Git 命令初始化仓库：
```rust
Command::new("git")
    .env("GIT_CONFIG_GLOBAL", "/dev/null")      // 忽略全局配置
    .env("GIT_CONFIG_NOSYSTEM", "1")            // 忽略系统配置
    .args(["init"])
    .current_dir(&repo)
    .output()
```

## 风险、边界与改进建议

### 已知边界条件
1. **Git 依赖**：测试依赖系统安装的 Git，若未安装或版本不兼容会失败
2. **时间戳硬编码**：使用固定时间戳 `1_709_251_100`（2024-03-06），不影响功能但不够灵活
3. **平台差异**：`fs::canonicalize` 在 Windows 和 Unix 上行为略有不同

### 测试覆盖缺口
1. **当前线程段落**：未测试 `build_current_thread_section()`
2. **完整上下文构建**：未测试 `build_realtime_startup_context()` 的端到端流程
3. **令牌截断**：未测试预算限制下的截断行为
4. **错误处理**：未测试文件系统权限错误、损坏的 Git 仓库等异常场景
5. **边界值**：未测试 `MAX_CURRENT_THREAD_TURNS`、`MAX_RECENT_WORK_GROUPS` 等边界

### 潜在风险
1. **Git 命令失败**：若 Git 命令失败，测试会 panic 而非优雅降级
2. **并发执行**：多个测试同时运行时使用不同的 `TempDir`，无冲突风险
3. **环境依赖**：`GIT_CONFIG_GLOBAL=/dev/null` 在 Windows 上可能无效

### 改进建议

#### 1. 增加缺失的测试覆盖
```rust
// 测试当前线程段落
#[test]
fn current_thread_section_extracts_recent_turns() {
    let items = vec![
        create_user_message("Hello"),
        create_assistant_message("Hi there"),
        create_user_message("How are you?"),
        create_assistant_message("I'm doing well!"),
    ];
    let section = build_current_thread_section(&items).expect("section");
    assert!(section.contains("Latest turn"));
    assert!(section.contains("Prior turn 1"));
}

// 测试令牌预算截断
#[test]
fn section_is_truncated_to_token_budget() {
    let huge_cwd = TempDir::new().expect("tempdir");
    // 创建大量文件使树结构超过预算
    for i in 0..100 {
        fs::write(huge_cwd.path().join(format!("file_{}.txt", i)), "content").unwrap();
    }
    let section = build_workspace_section_with_user_root(huge_cwd.path(), None).expect("section");
    // 验证截断发生（通过近似令牌计数）
    assert!(section.len() / 4 <= WORKSPACE_SECTION_TOKEN_BUDGET);
}
```

#### 2. 使用模拟替代真实 Git
```rust
// 当前：使用真实 Git 命令
// 建议：使用 mock 或手动创建 .git 目录结构
fn create_mock_git_repo(path: &Path) {
    fs::create_dir_all(path.join(".git")).unwrap();
    fs::write(path.join(".git/HEAD"), "ref: refs/heads/main\n").unwrap();
}
```

#### 3. 参数化测试
```rust
use test_case::test_case;

#[test_case(0, None; "empty dir returns none")]
#[test_case(1, Some; "single file returns section")]
#[test_case(20, Some; "at limit returns section")]
#[test_case(21, Some; "over limit truncates")]
fn workspace_section_with_various_entry_counts(count: usize, expected: Option<()>) {
    // 测试不同条目数下的行为
}
```

#### 4. 快照测试
对于复杂的格式化输出，使用 `insta` 进行快照测试：
```rust
#[test]
fn recent_work_section_format_snapshot() {
    let threads = vec![/* ... */];
    let section = build_recent_work_section(cwd, &threads).unwrap();
    insta::assert_snapshot!(section);
}
```

#### 5. 异步测试支持
`build_realtime_startup_context` 是异步函数，当前未测试：
```rust
#[tokio::test]
async fn startup_context_builds_successfully() {
    let mock_session = create_mock_session().await;
    let context = build_realtime_startup_context(&mock_session, 5000).await;
    assert!(context.is_some());
}
```
