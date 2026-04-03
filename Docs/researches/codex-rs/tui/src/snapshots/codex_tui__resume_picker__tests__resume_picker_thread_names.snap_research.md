# Resume Picker 线程名称快照研究文档

## 场景与职责

该快照测试验证 **Resume Picker** 的线程名称（Thread Name）显示功能。当会话被用户命名后，Resume Picker 应该优先显示线程名称而非第一条消息预览，帮助用户更快速地识别会话。

### 核心职责
- 异步加载线程名称
- 优先显示线程名称（如果存在）
- 回退到第一条消息预览（如果无名称）
- 缓存线程名称避免重复查询

## 功能点目的

### 1. 线程名称显示
- 用户可以为会话设置自定义名称（如 "Keep this for now"）
- 线程名称比自动生成的预览更具描述性
- 在 Conversation 列显示线程名称

### 2. 异步加载
- 线程名称存储在独立的索引文件（`session_index.jsonl`）
- 使用 `find_thread_names_by_ids` 异步查询
- 加载完成后更新界面

### 3. 缓存机制
- 使用 `thread_name_cache: HashMap<ThreadId, Option<String>>` 缓存结果
- 避免重复查询相同线程
- 提高界面响应性

### 4. 优先级策略
```
显示优先级：thread_name > preview > "(no message yet)"
```

## 具体技术实现

### 数据结构

```rust
struct PickerState {
    // ... 其他字段
    thread_name_cache: HashMap<ThreadId, Option<String>>,  // 线程名称缓存
}

struct Row {
    path: PathBuf,
    preview: String,                    // 第一条消息预览（后备）
    thread_id: Option<ThreadId>,
    thread_name: Option<String>,        // 线程名称（优先显示）
    // ... 其他字段
}

impl Row {
    fn display_preview(&self) -> &str {
        // 优先返回 thread_name，其次 preview
        self.thread_name.as_deref().unwrap_or(&self.preview)
    }
}
```

### 异步加载流程

```rust
async fn update_thread_names(&mut self) {
    // 1. 收集缺失的线程 ID
    let mut missing_ids = HashSet::new();
    for row in &self.all_rows {
        if let Some(thread_id) = row.thread_id {
            if !self.thread_name_cache.contains_key(&thread_id) {
                missing_ids.insert(thread_id);
            }
        }
    }
    
    if missing_ids.is_empty() {
        return;
    }
    
    // 2. 批量查询线程名称
    let names = find_thread_names_by_ids(&self.codex_home, &missing_ids)
        .await
        .unwrap_or_default();
    
    // 3. 更新缓存
    for thread_id in missing_ids {
        let thread_name = names.get(&thread_id).cloned();
        self.thread_name_cache.insert(thread_id, thread_name);
    }
    
    // 4. 更新行数据
    let mut updated = false;
    for row in self.all_rows.iter_mut() {
        if let Some(thread_id) = row.thread_id {
            let thread_name = self.thread_name_cache.get(&thread_id).cloned().flatten();
            if row.thread_name != thread_name {
                row.thread_name = thread_name;
                updated = true;
            }
        }
    }
    
    // 5. 如果有更新，重新应用过滤
    if updated {
        self.apply_filter();
    }
}
```

### 会话索引格式

```json
// session_index.jsonl
{"id": "11111111-1111-1111-1111-111111111111", "thread_name": "Keep this for now", "updated_at": "2025-01-01T00:00:00Z"}
{"id": "22222222-2222-2222-2222-222222222222", "thread_name": "Named thread", "updated_at": "2025-01-01T00:00:00Z"}
```

### 测试用例分析

```rust
#[tokio::test]
async fn resume_picker_thread_names_snapshot() {
    // 1. 创建临时目录和会话索引
    let tempdir = tempfile::tempdir().expect("tempdir");
    let session_index_path = tempdir.path().join("session_index.jsonl");
    
    let id1 = ThreadId::from_string("11111111-1111-1111-1111-111111111111").expect("thread id 1");
    let id2 = ThreadId::from_string("22222222-2222-2222-2222-222222222222").expect("thread id 2");
    
    // 写入会话索引
    let entries = vec![
        json!({"id": id1, "thread_name": "Keep this for now", "updated_at": "2025-01-01T00:00:00Z"}),
        json!({"id": id2, "thread_name": "Named thread", "updated_at": "2025-01-01T00:00:00Z"}),
    ];
    // ... 写入文件
    
    // 2. 创建状态
    let mut state = PickerState::new(
        tempdir.path().to_path_buf(),  // codex_home
        // ...
    );
    
    // 3. 创建测试行（初始无 thread_name）
    let now = Utc::now();
    let rows = vec![
        Row {
            preview: "First message preview".to_string(),  // 后备预览
            thread_id: Some(id1),
            thread_name: None,  // 待加载
            updated_at: Some(now - Duration::days(2)),
            // ...
        },
        Row {
            preview: "Second message preview".to_string(),
            thread_id: Some(id2),
            thread_name: None,
            updated_at: Some(now - Duration::days(3)),
            // ...
        },
    ];
    state.all_rows = rows.clone();
    state.filtered_rows = rows;
    state.selected = 0;
    
    // 4. 异步加载线程名称
    state.update_thread_names().await;
    
    // 5. 渲染并验证
    let metrics = calculate_column_metrics(&state.filtered_rows, state.show_all);
    render_column_headers(&mut frame, segments[0], &metrics, state.sort_key);
    render_list(&mut frame, segments[1], &state, &metrics);
    
    assert_snapshot!("resume_picker_thread_names", snapshot);
}
```

### 快照输出解析

```
  Created at  Updated at  Branch  CWD  Conversation
// 列标题
> -           2 days ago  -       -    Keep this for now
// 第一行（选中）：无创建时间，显示线程名称
  -           3 days ago  -       -    Named thread
// 第二行：无创建时间，显示线程名称
```

**注意**：
- Created at 列显示 `-` 是因为测试数据中 `created_at` 为 `None`
- Conversation 列显示线程名称（"Keep this for now", "Named thread"）而非预览

## 关键代码路径与文件引用

### 核心文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/resume_picker.rs` | Resume Picker 实现 |

### 关键函数

1. **线程名称加载**
   - `PickerState::update_thread_names()` (line 584-624)
   - `find_thread_names_by_ids()` (来自 codex_core)

2. **显示优先级**
   - `Row::display_preview()` (line 342-344)

3. **搜索匹配**
   - `Row::matches_query()` (line 346-356)
   - 同时匹配 `preview` 和 `thread_name`

4. **测试**
   - `resume_picker_thread_names_snapshot()` (line 1852-1948)

### 加载触发时机

```rust
async fn handle_background_event(&mut self, event: BackgroundEvent) -> Result<()> {
    match event {
        BackgroundEvent::PageLoaded { ... } => {
            // ...
            self.ingest_page(page);
            self.update_thread_names().await;  // 页面加载后更新线程名称
            // ...
        }
    }
}
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `tokio` | 异步运行时 |
| `serde_json` | 会话索引 JSON 解析 |
| `tempfile` | 测试临时目录 |

### 内部模块交互

```
resume_picker.rs
├── codex_core::find_thread_names_by_ids() (查询线程名称)
│   └── 读取 codex_home/session_index.jsonl
└── custom_terminal.rs (VT100Backend 测试后端)
```

### 会话索引查询

```rust
// codex_core 中的实现
pub async fn find_thread_names_by_ids(
    codex_home: &Path,
    thread_ids: &HashSet<ThreadId>,
) -> Result<HashMap<ThreadId, String>> {
    let index_path = codex_home.join("session_index.jsonl");
    // 读取索引文件，返回 thread_id -> thread_name 映射
}
```

## 风险、边界与改进建议

### 潜在风险

1. **索引文件损坏**
   - `session_index.jsonl` 损坏可能导致线程名称加载失败
   - 当前实现会静默忽略错误（`unwrap_or_default()`）

2. **并发更新**
   - 用户在 Resume Picker 打开时重命名会话
   - 索引文件更新可能不及时反映

3. **性能问题**
   - 大量会话时，批量查询可能较慢
   - 当前实现是同步批量查询

### 边界情况

1. **无线程名称**
   - 回退到 `preview` 显示
   - 如果 `preview` 也为空，显示 `"(no message yet)"`

2. **空线程名称**
   - 如果 `thread_name` 是空字符串，应视为无名称
   - 当前实现可能显示空字符串

3. **搜索匹配**
   - 搜索时同时匹配 `thread_name` 和 `preview`
   - 用户可能通过任一名称找到会话

### 改进建议

1. **增量更新**
   - 支持会话索引的增量更新
   - 避免全量重新加载

2. **重命名功能**
   - 在 Resume Picker 中直接支持重命名会话
   - 实时更新显示

3. **名称验证**
   - 过滤空字符串线程名称
   - 限制线程名称长度

4. **错误处理**
   - 索引文件损坏时显示警告
   - 提供重建索引的选项

5. **性能优化**
   - 分页加载线程名称
   - 优先加载可见行的线程名称
