# codex-rs/file-search/src/lib.rs 研究文档

## 场景与职责

`lib.rs` 是 `codex-file-search` crate 的核心库实现，提供高性能的模糊文件搜索能力。该 crate 被设计为可复用的库，同时支持两种使用模式：

1. **独立 CLI 工具**：通过 `main.rs` 提供命令行界面
2. **库集成**：被 `codex-rs/tui`、`codex-rs/tui_app_server`、`codex-rs/app-server` 等 crate 集成，用于实现交互式文件搜索（如 `@` 文件选择功能）

核心职责包括：
- 并行文件系统遍历（使用 `ignore` crate）
- 高性能模糊匹配（使用 `nucleo` crate）
- 支持增量查询更新的会话模式
- 可取消的异步搜索

## 功能点目的

### 1. 核心数据结构

#### `FileMatch`
表示单个匹配结果：
```rust
pub struct FileMatch {
    pub score: u32,                    // nucleo 相关性评分
    pub path: PathBuf,                 // 相对路径
    pub match_type: MatchType,         // 文件或目录
    pub root: PathBuf,                 // 搜索根目录
    pub indices: Option<Vec<u32>>,     // 匹配字符索引（用于高亮）
}
```

#### `FileSearchSnapshot`
会话模式下的搜索状态快照：
```rust
pub struct FileSearchSnapshot {
    pub query: String,
    pub matches: Vec<FileMatch>,
    pub total_match_count: usize,
    pub scanned_file_count: usize,
    pub walk_complete: bool,
}
```

#### `FileSearchOptions`
搜索配置选项：
```rust
pub struct FileSearchOptions {
    pub limit: NonZero<usize>,         // 最大结果数
    pub exclude: Vec<String>,          // 排除模式
    pub threads: NonZero<usize>,       // 工作线程数
    pub compute_indices: bool,         // 是否计算匹配索引
    pub respect_gitignore: bool,       // 是否遵守 .gitignore
}
```

### 2. 两种 API 模式

#### 2.1 单次搜索模式 (`run` 函数)
适用于一次性搜索场景：
```rust
pub fn run(
    pattern_text: &str,
    roots: Vec<PathBuf>,
    options: FileSearchOptions,
    cancel_flag: Option<Arc<AtomicBool>>,
) -> anyhow::Result<FileSearchResults>
```

**工作流程**：
1. 创建 `RunReporter`（同步等待完成的 reporter）
2. 调用 `create_session()` 创建搜索会话
3. 发送初始查询
4. 阻塞等待 `RunReporter::wait_for_complete()` 返回结果

#### 2.2 会话模式 (`create_session` + `FileSearchSession`)
适用于交互式场景（如 TUI 中的实时搜索）：
```rust
pub fn create_session(
    search_directories: Vec<PathBuf>,
    options: FileSearchOptions,
    reporter: Arc<dyn SessionReporter>,
    cancel_flag: Option<Arc<AtomicBool>>,
) -> anyhow::Result<FileSearchSession>
```

**核心特性**：
- **增量更新**：通过 `FileSearchSession::update_query()` 更新查询，复用已遍历的文件列表
- **流式结果**：通过 `SessionReporter` trait 的回调实时接收结果更新
- **资源管理**：`Drop` 实现确保会话清理时发送关闭信号

### 3. 双线程协作架构

会话模式内部使用两个工作线程：

#### Walker 线程 (`walker_worker`)
- **职责**：遍历文件系统，将发现的路径注入 nucleo
- **关键技术**：
  - 使用 `ignore::WalkBuilder` 构建并行遍历器
  - `require_git(true)`：仅在 git 仓库内时遵守 `.gitignore`（避免父目录的 `.gitignore` 误过滤）
  - `follow_links(true)`：跟随符号链接
  - `hidden(false)`：包含隐藏文件
  - 每 1024 个条目检查一次取消标志

#### Matcher 线程 (`matcher_worker`)
- **职责**：运行 nucleo 匹配引擎，处理查询更新和结果通知
- **关键技术**：
  - 使用 `crossbeam_channel::select!` 多路复用信号
  - 支持查询增量更新（`append` 模式优化前缀扩展查询）
  - 10ms 超时轮询机制平衡延迟和 CPU 使用
  - 结果去重排序（按分数降序、路径升序）

### 4. GitIgnore 处理策略

通过 `respect_gitignore` 选项控制：
- **启用**（默认）：`require_git(true)` 确保只在 git 仓库内应用 `.gitignore`
- **禁用**：完全关闭所有 ignore 相关处理（`.gitignore`、`.ignore`、git 全局排除等）

**设计原因**：避免父目录的宽泛 `.gitignore`（如 `*`）意外隐藏子目录中的文件（见测试 `parent_gitignore_outside_repo_does_not_hide_repo_files`）。

## 具体技术实现

### 关键依赖

| Crate | 用途 |
|-------|------|
| `nucleo` | 高性能模糊匹配引擎，支持实时增量更新 |
| `ignore` | 并行文件遍历，支持 `.gitignore` 等过滤规则 |
| `crossbeam-channel` | 无锁 MPSC 通道，用于线程间通信 |
| `serde` | 结果序列化（JSON 输出） |

### 核心算法

#### 匹配排序
```rust
pub fn cmp_by_score_desc_then_path_asc<T, FScore, FPath>(...)
```
- 主键：分数降序（高分在前）
- 次键：路径升序（字母顺序，确保确定性排序）

#### 匹配索引计算
当 `compute_indices = true` 时：
1. 使用 `nucleo::Matcher` 计算匹配位置
2. 排序并去重索引（`sort_unstable` + `dedup`）
3. 索引对应 UTF-32 字符位置（非字节位置）

### 信号处理机制

使用 `crossbeam_channel` 实现的三路信号：
```rust
enum WorkSignal {
    QueryUpdated(String),    // 用户更新查询
    NucleoNotify,           // nucleo 引擎通知有更新
    WalkComplete,           // 遍历完成
    Shutdown,               // 会话关闭
}
```

## 关键代码路径与文件引用

### 会话创建流程
```
create_session()
  ├── build_override_matcher()  [lib.rs:364-378]
  ├── Nucleo::new()             [lib.rs:182-187]
  ├── thread::spawn(matcher_worker)  [lib.rs:205]
  └── thread::spawn(walker_worker)   [lib.rs:208]
```

### 查询更新流程
```
FileSearchSession::update_query()
  └── work_tx.send(WorkSignal::QueryUpdated)
        └── matcher_worker::select! 处理
              └── nucleo.pattern.reparse()  [lib.rs:508-514]
              └── 触发重新匹配
```

### 结果生成流程
```
matcher_worker::select! recv(next_notify)
  └── nucleo.tick()  [lib.rs:539]
        └── snapshot.matches() 迭代
              └── get_file_path() 计算相对路径  [lib.rs:380-397]
              └── 可选：indices_matcher 计算高亮索引  [lib.rs:552-560]
              └── FileMatch 构造
  └── reporter.on_update() 回调
```

### 调用方引用

| 调用方 | 使用方式 | 文件路径 |
|--------|----------|----------|
| CLI 二进制 | `run_main()` | `main.rs:18` |
| TUI | `FileSearchManager` 封装 | `tui/src/file_search.rs` |
| TUI App Server | `FileSearchManager` 封装 | `tui_app_server/src/file_search.rs` |
| App Server | `run_fuzzy_file_search()`, `start_fuzzy_file_search_session()` | `app-server/src/fuzzy_file_search.rs` |

## 依赖与外部交互

### 被调用方（下游依赖）
- **`codex-rs/tui`**：交互式文件搜索弹窗
- **`codex-rs/tui_app_server`**：TUI 应用服务器的文件搜索
- **`codex-rs/app-server`**：LSP 风格协议服务器的文件搜索 API

### 协议集成
在 `app-server-protocol` 中定义了对应的协议类型：
- `FuzzyFileSearchParams` / `FuzzyFileSearchResponse`
- `FuzzyFileSearchSessionStartParams` 等会话管理类型
- `FuzzyFileSearchSessionUpdatedNotification` / `FuzzyFileSearchSessionCompletedNotification`

## 风险、边界与改进建议

### 风险点

1. **线程安全与死锁**
   - `SessionInner` 包含多个 `Arc` 引用，需确保无循环引用
   - `RunReporter` 使用 `RwLock` + `Condvar` 组合，已实现正确但复杂

2. **取消机制局限性**
   - walker 线程每 1024 个条目检查一次取消标志，最坏情况下延迟较大
   - 无强制中断机制，依赖协作式取消

3. **内存使用**
   - 所有遍历的文件路径都保存在 nucleo 内部，大目录可能占用大量内存
   - 无 LRU 或分页机制

4. **路径处理**
   - `get_file_path()` 使用字符串比较，对非 UTF-8 路径可能有问题
   - 多根目录时的"最佳匹配"逻辑基于组件数，可能不符合直觉

### 边界情况

1. **空查询处理**
   - 会话模式允许空查询（返回所有文件）
   - 但 `run_main()` 在空查询时回退到 `ls` 命令

2. **多根目录**
   - 支持多个搜索根目录（`Vec<PathBuf>`）
   - 结果路径相对于各自根目录

3. **符号链接**
   - `follow_links(true)` 可能导致的循环链接问题由 `ignore` crate 处理

### 改进建议

1. **性能优化**
   - 考虑使用 `jemalloc` 或类似内存分配器优化大量小字符串分配
   - 对超大目录考虑分层加载或虚拟滚动

2. **功能增强**
   - 支持正则表达式模式（当前仅模糊匹配）
   - 支持文件内容预览
   - 支持最近文件优先排序

3. **可观测性**
   - 添加 `tracing` 日志记录遍历和匹配性能指标
   - 暴露内部统计信息（缓存命中率等）

4. **错误处理**
   - 当前遍历错误被静默忽略（`Err(_) => return ignore::WalkState::Continue`）
   - 可考虑收集权限错误并报告给用户

5. **测试覆盖**
   - 已覆盖基本功能、取消、多会话、gitignore 场景
   - 可补充：符号链接循环、非 UTF-8 路径、超大目录性能测试
