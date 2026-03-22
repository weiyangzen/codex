# rollout.rs 研究文档

## 场景与职责

该文件提供了用于测试的 Rollout 文件（会话历史记录）生成功能。在 Codex 中，rollout 文件是 JSON Lines 格式的会话记录，存储在 `CODEX_HOME/sessions/YYYY/MM/DD/rollout-{timestamp}-{thread_id}.jsonl` 路径下。该模块允许测试：
1. 创建模拟的历史会话记录
2. 测试会话列表、读取、恢复等功能
3. 模拟不同来源（CLI、VS Code 等）的会话
4. 模拟包含 Git 信息的会话

## 功能点目的

1. **模拟历史会话**：创建符合格式的 rollout 文件，用于测试会话管理功能
2. **支持多种会话来源**：支持 CLI、VS Code Extension 等不同来源标记
3. **Git 信息集成**：支持在会话元数据中包含 Git 仓库信息
4. **文件时间戳控制**：允许设置文件的修改时间，用于测试按时间排序

## 具体技术实现

### 路径生成

```rust
pub fn rollout_path(codex_home: &Path, filename_ts: &str, thread_id: &str) -> PathBuf {
    let year = &filename_ts[0..4];
    let month = &filename_ts[5..7];
    let day = &filename_ts[8..10];
    codex_home
        .join("sessions")
        .join(year)
        .join(month)
        .join(day)
        .join(format!("rollout-{filename_ts}-{thread_id}.jsonl"))
}
```

路径格式：`{codex_home}/sessions/{YYYY}/{MM}/{DD}/rollout-{YYYY-MM-DDThh-mm-ss}-{thread_id}.jsonl`

### 基础 Rollout 创建

```rust
pub fn create_fake_rollout(
    codex_home: &Path,
    filename_ts: &str,        // 文件名时间戳，格式：YYYY-MM-DDThh-mm-ss
    meta_rfc3339: &str,       // 元数据时间戳，RFC3339 格式
    preview: &str,            // 用户消息预览文本
    model_provider: Option<&str>,  // 模型提供商（如 "openai"）
    git_info: Option<GitInfo>,     // Git 仓库信息
) -> Result<String>           // 返回生成的会话 UUID
```

### 带来源的 Rollout 创建

```rust
pub fn create_fake_rollout_with_source(
    codex_home: &Path,
    filename_ts: &str,
    meta_rfc3339: &str,
    preview: &str,
    model_provider: Option<&str>,
    git_info: Option<GitInfo>,
    source: SessionSource,    // 会话来源（Cli、VsCode 等）
) -> Result<String>
```

### 带文本元素的 Rollout 创建

```rust
pub fn create_fake_rollout_with_text_elements(
    codex_home: &Path,
    filename_ts: &str,
    meta_rfc3339: &str,
    preview: &str,
    text_elements: Vec<serde_json::Value>,  // 富文本元素
    model_provider: Option<&str>,
    git_info: Option<GitInfo>,
) -> Result<String>
```

### Rollout 文件结构

生成的 JSON Lines 文件包含以下记录：

```json
// 1. 会话元数据（session_meta）
{
  "timestamp": "2024-01-15T10:30:00Z",
  "type": "session_meta",
  "payload": {
    "meta": {
      "id": "...",
      "forked_from_id": null,
      "timestamp": "2024-01-15T10:30:00Z",
      "cwd": "/",
      "originator": "codex",
      "cli_version": "0.0.0",
      "source": "cli",
      "agent_nickname": null,
      "agent_role": null,
      "model_provider": "openai",
      "base_instructions": null,
      "dynamic_tools": null,
      "memory_mode": null
    },
    "git": { ... }  // 可选
  }
}

// 2. 用户消息（response_item）
{
  "timestamp": "2024-01-15T10:30:00Z",
  "type": "response_item",
  "payload": {
    "type": "message",
    "role": "user",
    "content": [{"type": "input_text", "text": "Hello"}]
  }
}

// 3. 事件消息（event_msg）
{
  "timestamp": "2024-01-15T10:30:00Z",
  "type": "event_msg",
  "payload": {
    "type": "user_message",
    "message": "Hello",
    "kind": "plain",
    "text_elements": [...],  // create_fake_rollout_with_text_elements 中
    "local_images": []
  }
}
```

### 文件时间戳设置

```rust
let parsed = chrono::DateTime::parse_from_rfc3339(meta_rfc3339)?.with_timezone(&chrono::Utc);
let times = FileTimes::new().set_modified(parsed.into());
std::fs::OpenOptions::new()
    .append(true)
    .open(&file_path)?
    .set_times(times)?;
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/app-server/tests/common/rollout.rs`

### 导出位置
- `lib.rs`: 
```rust
pub use rollout::create_fake_rollout;
pub use rollout::create_fake_rollout_with_source;
pub use rollout::create_fake_rollout_with_text_elements;
pub use rollout::rollout_path;
```

### 依赖的 Codex 内部类型
- `codex_protocol::ThreadId` - 会话 ID 类型
- `codex_protocol::protocol::{GitInfo, SessionMeta, SessionMetaLine, SessionSource}` - 会话协议类型

### 使用示例

```rust
// 1. 创建基础 rollout
let thread_id = create_fake_rollout(
    codex_home.path(),
    "2024-01-15T10-30-00",           // 文件名时间戳
    "2024-01-15T10:30:00Z",          // 元数据时间戳
    "Hello, world!",                 // 用户消息预览
    Some("openai"),                  // 模型提供商
    None,                            // Git 信息
)?;

// 2. 创建带 Git 信息的 rollout
let git_info = GitInfo {
    repo_root: Some("/path/to/repo".into()),
    branch: Some("main".to_string()),
    commit: Some("abc123".to_string()),
};
let thread_id = create_fake_rollout(
    codex_home.path(),
    "2024-01-15T10-30-00",
    "2024-01-15T10:30:00Z",
    "Implement feature",
    Some("openai"),
    Some(git_info),
)?;

// 3. 创建带富文本元素的 rollout
let text_elements = vec![
    json!({"type": "text", "text": "Check this file: "}),
    json!({"type": "file_path", "path": "/path/to/file.rs"}),
];
let thread_id = create_fake_rollout_with_text_elements(
    codex_home.path(),
    "2024-01-15T10-30-00",
    "2024-01-15T10:30:00Z",
    "Check this file: /path/to/file.rs",
    text_elements,
    Some("openai"),
    None,
)?;
```

## 依赖与外部交互

### 外部 crate 依赖
- `anyhow::Result` - 错误处理
- `chrono` - 时间解析和转换
- `serde_json::json` - JSON 构造
- `std::fs` - 文件操作
- `uuid::Uuid` - UUID 生成

### Codex 内部依赖
```
rollout.rs
└── codex_protocol::protocol
    ├── ThreadId           会话 ID
    ├── GitInfo            Git 仓库信息
    ├── SessionMeta        会话元数据
    ├── SessionMetaLine    会话元数据行（包含 meta 和 git）
    └── SessionSource      会话来源枚举
        ├── Cli
        ├── VsCode
        └── ...
```

### 与会话存储的交互

```
测试代码
    │
    ├──► create_fake_rollout(...)
    │       │
    │       ├──► 生成 UUID
    │       ├──► 创建目录结构：sessions/YYYY/MM/DD/
    │       ├──► 构建 SessionMeta
    │       ├──► 序列化 JSON Lines
    │       ├──► 写入文件
    │       └──► 设置文件修改时间
    │
    └──► 启动 codex-app-server
            │
            └──► 会话管理器读取 rollout 文件
                    │
                    ├──► 解析 JSON Lines
                    ├──► 构建会话历史
                    └──► 提供会话列表/读取 API
```

## 风险、边界与改进建议

### 风险
1. **时间戳格式敏感**：`filename_ts` 和 `meta_rfc3339` 使用不同格式，容易混淆
2. **硬编码值**：`originator: "codex"`、`cli_version: "0.0.0"` 等是硬编码的
3. **UUID 生成**：使用 `Uuid::new_v4()` 生成随机 UUID，如果需要确定性测试可能需要控制
4. **目录创建**：使用 `fs::create_dir_all`，如果权限不足会失败
5. **时间戳解析**：`parse_from_rfc3339` 可能失败，但错误处理仅使用 `?`

### 边界
- 仅创建最小化的 rollout 文件（3 行 JSON），不包含完整的对话历史
- 不支持创建分叉会话（`forked_from_id` 始终为 `null`）
- 不支持设置所有 SessionMeta 字段（如 `agent_nickname`、`dynamic_tools` 等）
- 仅支持单条用户消息，不支持助手回复或多轮对话
- 不支持附件或图片（`local_images` 始终为空数组）

### 改进建议

1. **统一时间戳处理**：
```rust
pub struct RolloutTimestamp {
    pub filename_ts: String,  // YYYY-MM-DDThh-mm-ss
    pub rfc3339: String,      // YYYY-MM-DDThh:mm:ssZ
}

impl RolloutTimestamp {
    pub fn from_datetime(dt: DateTime<Utc>) -> Self { ... }
    pub fn now() -> Self { ... }
}
```

2. **完整对话历史支持**：
```rust
pub struct FakeConversation {
    pub user_messages: Vec<String>,
    pub assistant_responses: Vec<String>,
}

pub fn create_fake_rollout_with_conversation(
    codex_home: &Path,
    timestamp: &RolloutTimestamp,
    conversation: &FakeConversation,
    ...
) -> Result<String> { ... }
```

3. **分叉会话支持**：
```rust
pub fn create_fake_forked_rollout(
    codex_home: &Path,
    parent_thread_id: &str,
    ...
) -> Result<String> { ... }
```

4. **Builder 模式**：
```rust
let thread_id = RolloutBuilder::new()
    .codex_home(codex_home.path())
    .timestamp(RolloutTimestamp::now())
    .preview("Hello")
    .model_provider("openai")
    .git_info(git_info)
    .agent_nickname("My Agent")
    .build()?;
```

5. **验证函数**：
```rust
pub fn verify_rollout(codex_home: &Path, thread_id: &str) -> Result<SessionMeta> {
    let path = rollout_path(codex_home, "...", thread_id);
    // 验证文件存在、格式正确、内容完整
}
```

6. **批量创建**：
```rust
pub fn create_fake_rollouts(
    codex_home: &Path,
    configs: Vec<RolloutConfig>,
) -> Result<Vec<String>> { ... }
```

7. **文档增强**：
```rust
/// 创建模拟的 rollout 文件。
/// 
/// # 参数
/// - `filename_ts`: 文件名时间戳，格式为 `YYYY-MM-DDThh-mm-ss`
/// - `meta_rfc3339`: 元数据时间戳，RFC3339 格式（如 `2024-01-15T10:30:00Z`）
/// 
/// # 注意
/// 两个时间戳使用不同格式！filename_ts 用于文件路径，meta_rfc3339 用于文件内容。
pub fn create_fake_rollout(...) -> Result<String> { ... }
```
