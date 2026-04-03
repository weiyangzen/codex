# realtime_context.rs 研究文档

## 场景与职责

`realtime_context.rs` 是 Codex 实时对话（Realtime Conversation）功能的启动上下文构建模块。它负责在实时会话启动时，收集和组装关于当前工作环境的背景信息，为 AI 模型提供有价值的上下文，以改善对话的连贯性和相关性。

该模块的核心职责包括：
- 从当前会话历史中提取最近的对话轮次
- 从状态数据库加载最近的工作线程（threads）元数据
- 扫描本地工作区目录结构
- 将收集的信息格式化为结构化的文本上下文
- 应用令牌预算限制进行智能截断

## 功能点目的

### 1. 启动上下文构建 (`build_realtime_startup_context`)
这是模块的主入口函数，协调各个子模块构建完整的启动上下文：
- 收集当前线程的最近对话轮次
- 加载并分组最近的工作历史
- 构建工作区目录树映射
- 应用令牌预算进行截断和格式化

### 2. 当前线程上下文 (`build_current_thread_section`)
从会话历史中提取最近的 user/assistant 对话轮次：
- 解析 `ResponseItem` 流，识别 user 和 assistant 消息
- 过滤掉上下文性消息（contextual user messages）
- 保留最多 `MAX_CURRENT_THREAD_TURNS = 2` 轮对话
- 格式化输出包含 "Latest turn" 和 "Prior turn" 标记

### 3. 最近工作历史 (`build_recent_work_section`)
从状态数据库加载并呈现最近的工作活动：
- 按 Git 仓库根目录或工作目录对线程进行分组
- 优先显示当前工作目录所在的分组
- 每组显示最多 `MAX_RECENT_WORK_GROUPS = 8` 个
- 每组内显示最近的用户查询（去重后）

### 4. 工作区映射 (`build_workspace_section_with_user_root`)
构建当前工作环境的目录结构视图：
- 当前工作目录（CWD）的树形结构
- Git 根目录的树形结构（如果与 CWD 不同）
- 用户主目录的树形结构（如果与上述都不同）
- 限制树深度为 `TREE_MAX_DEPTH = 2`，每目录最多 `DIR_ENTRY_LIMIT = 20` 项

## 具体技术实现

### 核心数据结构

```rust
// 预算常量（令牌数）
const CURRENT_THREAD_SECTION_TOKEN_BUDGET: usize = 1_200;
const RECENT_WORK_SECTION_TOKEN_BUDGET: usize = 2_200;
const WORKSPACE_SECTION_TOKEN_BUDGET: usize = 1_600;
const NOTES_SECTION_TOKEN_BUDGET: usize = 300;

// 数量限制
const MAX_CURRENT_THREAD_TURNS: usize = 2;      // 当前线程保留轮次
const MAX_RECENT_THREADS: usize = 40;           // 加载的最近线程数
const MAX_RECENT_WORK_GROUPS: usize = 8;        // 显示的工作组数
const MAX_CURRENT_CWD_ASKS: usize = 8;          // 当前目录查询数
const MAX_OTHER_CWD_ASKS: usize = 5;            // 其他目录查询数
const MAX_ASK_CHARS: usize = 240;               // 查询文本最大长度
const TREE_MAX_DEPTH: usize = 2;                // 目录树最大深度
const DIR_ENTRY_LIMIT: usize = 20;              // 每目录最大条目数
const APPROX_BYTES_PER_TOKEN: usize = 4;        // 近似字节/令牌比率
```

### 关键算法

#### 线程分组与排序
```rust
fn build_recent_work_section(cwd: &Path, recent_threads: &[ThreadMetadata]) -> Option<String> {
    let mut groups: HashMap<PathBuf, Vec<&ThreadMetadata>> = HashMap::new();
    
    // 按 Git 根目录或 CWD 分组
    for entry in recent_threads {
        let group = resolve_root_git_project_for_trust(&entry.cwd)
            .unwrap_or_else(|| entry.cwd.clone());
        groups.entry(group).or_default().push(entry);
    }
    
    // 排序：当前组优先，然后按最近更新时间降序
    groups.sort_by(|(left_group, left_entries), (right_group, right_entries)| {
        let left_latest = left_entries.iter().map(|e| e.updated_at).max();
        let right_latest = right_entries.iter().map(|e| e.updated_at).max();
        (
            *left_group != current_group,  // 当前组排前面 (false < true)
            Reverse(left_latest),          // 时间降序
            left_group.as_os_str(),        // 路径字母序
        ).cmp(&...)
    });
}
```

#### 目录树渲染
```rust
fn collect_tree_lines(dir: &Path, depth: usize, lines: &mut Vec<String>) {
    if depth >= TREE_MAX_DEPTH {
        return;
    }
    
    let entries = read_sorted_entries(dir)?;
    let total_entries = entries.len();
    
    // 排序：目录在前，然后按名称排序
    entries.sort_by(|left, right| {
        let left_is_dir = left.file_type().map(|ft| ft.is_dir()).unwrap_or(false);
        let right_is_dir = right.file_type().map(|ft| ft.is_dir()).unwrap_or(false);
        (!left_is_dir, file_name_string(&left.path()))  // 目录优先
            .cmp(&(!right_is_dir, file_name_string(&right.path())))
    });
    
    // 显示前 DIR_ENTRY_LIMIT 项
    for entry in entries.into_iter().take(DIR_ENTRY_LIMIT) {
        lines.push(format!("{indent}- {name}{suffix}"));
        if file_type.is_dir() {
            collect_tree_lines(&entry.path(), depth + 1, lines);  // 递归
        }
    }
    
    // 显示省略标记
    if total_entries > DIR_ENTRY_LIMIT {
        lines.push(format!("{}- ... {} more entries", indent, total_entries - DIR_ENTRY_LIMIT));
    }
}
```

#### 对话轮次提取
```rust
fn build_current_thread_section(items: &[ResponseItem]) -> Option<String> {
    let mut turns = Vec::new();
    let mut current_user = Vec::new();
    let mut current_assistant = Vec::new();
    
    for item in items {
        match item {
            ResponseItem::Message { role: "user", content, .. } => {
                if is_contextual_user_message_content(content) { continue; }
                // 开始新轮次
                if !current_user.is_empty() || !current_assistant.is_empty() {
                    turns.push((mem::take(&mut current_user), mem::take(&mut current_assistant)));
                }
                current_user.push(text);
            }
            ResponseItem::Message { role: "assistant", content, .. } => {
                current_assistant.push(text);
            }
            _ => {}
        }
    }
    
    // 保留最后 MAX_CURRENT_THREAD_TURNS 轮
    let retained_turns = turns.into_iter().rev().take(MAX_CURRENT_THREAD_TURNS).rev().collect();
}
```

### 噪声目录过滤
```rust
const NOISY_DIR_NAMES: &[&str] = &[
    ".git", ".next", ".pytest_cache", ".ruff_cache",
    "__pycache__", "build", "dist", "node_modules", "out", "target",
];

fn is_noisy_name(name: &OsStr) -> bool {
    let name = name.to_string_lossy();
    name.starts_with('.') || NOISY_DIR_NAMES.iter().any(|noisy| *noisy == name)
}
```

## 关键代码路径与文件引用

### 入口函数
| 函数 | 位置 | 调用方 |
|-----|------|-------|
| `build_realtime_startup_context()` | `realtime_context.rs:51` | `realtime_conversation.rs:469` |

### 内部调用链
```
build_realtime_startup_context
├── load_recent_threads
│   └── Session::services.state_db.list_threads()
├── build_current_thread_section
│   └── event_mapping::is_contextual_user_message_content()
├── build_recent_work_section
│   └── git_info::resolve_root_git_project_for_trust()
└── build_workspace_section_with_user_root
    ├── git_info::resolve_root_git_project_for_trust()
    └── render_tree
        ├── read_sorted_entries
        └── collect_tree_lines (递归)
```

### 依赖模块
| 模块 | 用途 |
|-----|------|
| `crate::codex::Session` | 获取配置和历史记录 |
| `crate::compact::content_items_to_text` | 内容项转文本 |
| `crate::event_mapping::is_contextual_user_message_content` | 过滤上下文消息 |
| `crate::git_info::resolve_root_git_project_for_trust` | 解析 Git 根目录 |
| `crate::truncate::{TruncationPolicy, truncate_text}` | 文本截断 |
| `codex_state::{SortKey, ThreadMetadata}` | 状态数据库查询 |
| `codex_protocol::models::ResponseItem` | 响应项模型 |

## 依赖与外部交互

### 状态数据库交互
```rust
async fn load_recent_threads(sess: &Session) -> Vec<ThreadMetadata> {
    let Some(state_db) = sess.services.state_db.as_ref() else {
        return Vec::new();
    };
    
    state_db.list_threads(
        MAX_RECENT_THREADS,
        /*anchor*/ None,
        SortKey::UpdatedAt,
        &[],
        /*model_providers*/ None,
        /*archived_only*/ false,
        /*search_term*/ None,
    ).await
}
```

### 文件系统交互
- `std::fs::read_dir()` - 读取目录内容
- `std::fs::metadata()` - 获取文件元数据
- 符号链接跟随：默认行为

### 异步运行时
- 使用 `tokio` 进行异步文件操作
- 状态数据库查询为异步操作

## 风险、边界与改进建议

### 已知边界条件
1. **空状态处理**：当没有历史记录、没有线程、目录为空时，返回 `None` 跳过上下文注入
2. **令牌预算硬编码**：各段落的预算为编译时常量，无法动态调整
3. **目录遍历深度限制**：`TREE_MAX_DEPTH = 2` 可能不足以展示深层项目结构
4. **时间戳依赖**：线程排序完全依赖 `updated_at` 时间戳

### 潜在性能风险
1. **状态数据库查询**：`list_threads(40)` 可能在数据库较大时产生延迟
2. **目录遍历**：虽然限制了深度和条目数，但在网络文件系统上仍可能缓慢
3. **字符串分配**：大量字符串拼接和格式化操作

### 改进建议

#### 1. 动态预算分配
```rust
// 当前：固定预算
const CURRENT_THREAD_SECTION_TOKEN_BUDGET: usize = 1_200;

// 建议：基于总预算的动态分配
fn allocate_budgets(total_tokens: usize, has_recent_work: bool, has_workspace: bool) 
    -> (usize, usize, usize) 
{
    let base_thread = total_tokens / 4;
    let base_work = if has_recent_work { total_tokens / 3 } else { 0 };
    let base_workspace = if has_workspace { total_tokens / 4 } else { 0 };
    // ... 调整逻辑
}
```

#### 2. 缓存机制
- 缓存工作区目录树结构（文件系统监听变更）
- 缓存最近线程列表（状态数据库变更时刷新）

#### 3. 可配置性
- 允许通过配置禁用特定段落（如用户可能不需要工作区映射）
- 允许自定义 `NOISY_DIR_NAMES`
- 允许调整 `TREE_MAX_DEPTH` 和 `DIR_ENTRY_LIMIT`

#### 4. 错误处理增强
```rust
// 当前：数据库错误仅记录警告
warn!("failed to load realtime startup threads from state db: {err}");

// 建议：区分可恢复和不可恢复错误
match state_db.list_threads(...).await {
    Ok(page) => page.items,
    Err(err) if err.is_temporary() => {
        warn!(...);
        Vec::new()
    }
    Err(err) => {
        error!(...);
        // 考虑向用户报告
        Vec::new()
    }
}
```

#### 5. 隐私考虑
- 工作区映射可能暴露敏感目录结构
- 最近工作历史可能暴露用户在其他项目的活动
- 建议添加隐私模式开关，禁用或匿名化这些信息

### 测试覆盖
- 单元测试位于 `realtime_context_tests.rs`
- 当前覆盖：工作区段落构建、最近工作段落构建
- 缺口：完整上下文构建、令牌预算截断、空状态处理
