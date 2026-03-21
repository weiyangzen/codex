# codex-rs/feedback 研究文档

## 概述

`codex-feedback` crate 是 Codex CLI 项目的用户反馈收集与上传模块。它负责捕获应用运行时的日志、诊断信息，并将这些信息上传到 Sentry 进行错误追踪和用户反馈收集。

---

## 场景与职责

### 核心职责

1. **日志捕获与存储**：通过环形缓冲区（Ring Buffer）捕获应用运行时的 tracing 日志，保留最新的 4MB 日志内容
2. **反馈元数据收集**：收集结构化元数据（tags）用于反馈分类和追踪
3. **网络诊断信息收集**：检测并记录可能影响连接的环境变量（代理设置、OPENAI_BASE_URL 等）
4. **反馈上传到 Sentry**：将日志、诊断信息和用户注释打包上传到 Sentry 服务

### 使用场景

- **Bug 报告**：用户遇到崩溃或错误时提交反馈
- **结果评价**：用户对 AI 生成结果进行好评/差评反馈
- **安全检查反馈**：用户认为某些内容被错误地阻止时提交反馈
- **其他反馈**：性能问题、功能建议等

---

## 功能点目的

### 1. 环形日志缓冲区 (`RingBuffer`)

```rust
const DEFAULT_MAX_BYTES: usize = 4 * 1024 * 1024; // 4 MiB
```

- **目的**：在内存中保持固定大小的最近日志，避免无限制增长
- **实现**：使用 `VecDeque<u8>` 实现 FIFO 队列，当容量超过限制时从头部丢弃旧数据
- **特点**：
  - 支持大容量写入（自动截断保留尾部）
  - 线程安全（通过 Mutex 保护）

### 2. 反馈分类系统

支持 5 种反馈类别：

| 分类 | 用途 | Sentry Level |
|------|------|--------------|
| `bug` | 崩溃、错误、UI/行为异常 | Error |
| `bad_result` | 输出不准确、不完整或无帮助 | Error |
| `good_result` | 有帮助、正确、高质量的结果 | Info |
| `safety_check` | 安全检查误报 | Error |
| `other` | 性能问题、功能建议等 | Info |

### 3. 网络诊断收集 (`FeedbackDiagnostics`)

自动检测并记录以下环境变量：

- **代理变量**：`HTTP_PROXY`, `http_proxy`, `HTTPS_PROXY`, `https_proxy`, `ALL_PROXY`, `all_proxy`
- **API 端点**：`OPENAI_BASE_URL`

这些信息帮助诊断连接问题，以明文形式记录（包括敏感信息如密码）。

### 4. Tracing 集成

提供两个 tracing layer：

- **`logger_layer`**：捕获所有 TRACE 级别日志到环形缓冲区
- **`metadata_layer`**：捕获 `target: "feedback_tags"` 的结构化元数据

### 5. Sentry 上传

- **DSN**：硬编码的 Sentry 项目地址
- **超时**：10 秒上传超时
- **附件**：支持多个附件（日志文件、诊断信息、额外文件）

---

## 具体技术实现

### 关键数据结构

#### `CodexFeedback` - 主入口

```rust
#[derive(Clone)]
pub struct CodexFeedback {
    inner: Arc<FeedbackInner>,
}

struct FeedbackInner {
    ring: Mutex<RingBuffer>,    // 日志数据
    tags: Mutex<BTreeMap<String, String>>,  // 元数据标签
}
```

#### `FeedbackSnapshot` - 反馈快照

```rust
pub struct FeedbackSnapshot {
    bytes: Vec<u8>,                           // 日志字节
    tags: BTreeMap<String, String>,          // 元数据标签
    feedback_diagnostics: FeedbackDiagnostics, // 诊断信息
    pub thread_id: String,                    // 会话 ID
}
```

#### `FeedbackDiagnostics` - 诊断信息

```rust
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct FeedbackDiagnostics {
    diagnostics: Vec<FeedbackDiagnostic>,
}

pub struct FeedbackDiagnostic {
    pub headline: String,    // 诊断标题
    pub details: Vec<String>, // 详细信息列表
}
```

### 关键流程

#### 1. 日志捕获流程

```
应用代码 -> tracing::info!/debug!/etc. 
    -> FeedbackMakeWriter::make_writer()
    -> FeedbackWriter::write()
    -> RingBuffer::push_bytes() [线程安全写入]
```

#### 2. 元数据收集流程

```
应用代码 -> tracing::info!(target: "feedback_tags", key = value)
    -> FeedbackMetadataLayer::on_event()
    -> FeedbackTagsVisitor::record_*()
    -> tags.insert(key, value) [BTreeMap 存储]
```

#### 3. 反馈上传流程

```
用户触发反馈 -> FeedbackNoteView::submit()
    -> FeedbackSnapshot::upload_feedback()
        -> 构建 Sentry Event
        -> 添加附件（日志、诊断、rollout 文件）
        -> Client::send_envelope()
        -> Client::flush() [等待上传完成]
```

### 核心代码路径

| 功能 | 文件 | 关键函数/结构 |
|------|------|---------------|
| 主入口 | `src/lib.rs` | `CodexFeedback` |
| 环形缓冲区 | `src/lib.rs` | `RingBuffer` |
| 日志写入 | `src/lib.rs` | `FeedbackWriter`, `FeedbackMakeWriter` |
| 元数据层 | `src/lib.rs` | `FeedbackMetadataLayer`, `FeedbackTagsVisitor` |
| 快照上传 | `src/lib.rs` | `FeedbackSnapshot::upload_feedback()` |
| 诊断收集 | `src/feedback_diagnostics.rs` | `FeedbackDiagnostics::collect_from_env()` |

---

## 关键代码路径与文件引用

### 文件结构

```
codex-rs/feedback/
├── Cargo.toml              # 依赖：anyhow, codex-protocol, sentry, tracing
├── BUILD.bazel            # Bazel 构建配置
└── src/
    ├── lib.rs             # 主实现（572 行）
    └── feedback_diagnostics.rs  # 诊断信息收集（229 行）
```

### 关键代码片段

#### 环形缓冲区写入

```rust
// src/lib.rs:178-201
fn push_bytes(&mut self, data: &[u8]) {
    if data.is_empty() { return; }
    
    // 如果数据超过容量，只保留尾部
    if data.len() >= self.max {
        self.buf.clear();
        let start = data.len() - self.max;
        self.buf.extend(data[start..].iter().copied());
        return;
    }
    
    // 从头部淘汰旧数据
    let needed = self.len() + data.len();
    if needed > self.max {
        let to_drop = needed - self.max;
        for _ in 0..to_drop { let _ = self.buf.pop_front(); }
    }
    
    self.buf.extend(data.iter().copied());
}
```

#### Sentry 上传

```rust
// src/lib.rs:246-343
pub fn upload_feedback(
    &self,
    classification: &str,
    reason: Option<&str>,
    include_logs: bool,
    extra_attachment_paths: &[PathBuf],
    session_source: Option<SessionSource>,
    logs_override: Option<Vec<u8>>,
) -> Result<()> {
    // 构建 Sentry 客户端
    let client = Client::from_config(ClientOptions {
        dsn: Some(Dsn::from_str(SENTRY_DSN)?),
        transport: Some(Arc::new(DefaultTransportFactory {})),
        ..Default::default()
    });
    
    // 构建事件和附件
    let mut envelope = Envelope::new();
    envelope.add_item(EnvelopeItem::Event(event));
    for attachment in self.feedback_attachments(...) {
        envelope.add_item(EnvelopeItem::Attachment(attachment));
    }
    
    // 发送并等待完成
    client.send_envelope(envelope);
    client.flush(Some(Duration::from_secs(UPLOAD_TIMEOUT_SECS)));
}
```

#### 诊断信息收集

```rust
// src/feedback_diagnostics.rs:30-69
pub fn collect_from_env() -> Self {
    Self::collect_from_pairs(std::env::vars())
}

fn collect_from_pairs<I, K, V>(pairs: I) -> Self {
    let env = pairs.into_iter()
        .map(|(k, v)| (k.into(), v.into()))
        .collect::<HashMap<_, _>>();
    
    // 检测代理环境变量
    let proxy_details = PROXY_ENV_VARS.iter()
        .filter_map(|key| env.get(*key).map(|v| format!("{key} = {v}")))
        .collect::<Vec<_>>();
    
    // 检测 OPENAI_BASE_URL
    if let Some(value) = env.get(OPENAI_BASE_URL_ENV_VAR) {
        diagnostics.push(FeedbackDiagnostic { ... });
    }
}
```

---

## 依赖与外部交互

### 依赖 crate

| crate | 用途 |
|-------|------|
| `anyhow` | 错误处理 |
| `codex-protocol` | `ThreadId`, `SessionSource` 类型 |
| `sentry` | 错误追踪和反馈上传 |
| `tracing` | 日志框架集成 |
| `tracing-subscriber` | tracing layer 实现 |

### 调用方（上游依赖）

| crate | 使用方式 |
|-------|----------|
| `codex-tui` | TUI 界面反馈功能 |
| `codex-exec` | Exec 模式反馈收集 |
| `codex-app-server` | App Server 反馈上传 API |
| `codex-app-server-client` | 传递反馈实例 |
| `codex-core` | `feedback_tags!` 宏发送元数据 |

### 配置集成

通过 `Config.feedback_enabled` 控制反馈功能开关：

```rust
// app-server/src/codex_message_processor.rs:6980-6988
if !self.config.feedback_enabled {
    let error = JSONRPCErrorError {
        code: INVALID_REQUEST_ERROR_CODE,
        message: "sending feedback is disabled by configuration".to_string(),
        data: None,
    };
    self.outgoing.send_error(request_id, error).await;
    return;
}
```

### TUI 集成

在 TUI 中，反馈通过 `/feedback` 命令触发：

```rust
// tui/src/chatwidget.rs:4315-4323
if !self.config.feedback_enabled {
    let params = crate::bottom_pane::feedback_disabled_params();
    self.show_selection_view(params);
} else {
    // 显示分类选择弹窗
    crate::bottom_pane::feedback_selection_params(self.app_event_tx.clone());
}
```

---

## 风险、边界与改进建议

### 已知风险

1. **敏感信息泄露**
   - 日志可能包含用户代码、文件路径等敏感信息
   - 诊断信息以明文记录代理认证信息（包括密码）
   - **缓解**：用户可以选择不包含日志的反馈（`include_logs: false`）

2. **Sentry DSN 硬编码**
   - DSN 直接硬编码在源码中：`SENTRY_DSN` 常量
   - **风险**：如果仓库开源，DSN 可能被滥用
   - **建议**：考虑通过构建时环境变量注入

3. **上传超时固定**
   - 超时时间固定为 10 秒，在网络差的情况下可能失败
   - **建议**：考虑可配置或自适应超时

4. **环形缓冲区大小固定**
   - 默认 4MB 可能不足以捕获完整的长时间会话日志
   - **建议**：考虑根据可用内存动态调整

### 边界情况

1. **大日志写入**
   - 当单次写入超过缓冲区容量时，只保留尾部数据
   - 实现正确处理：`data.len() >= self.max` 分支

2. **并发访问**
   - 使用 `Mutex` 保护环形缓冲区和标签集合
   - 使用 `Arc` 实现多线程共享

3. **标签数量限制**
   - 最多 64 个标签（`MAX_FEEDBACK_TAGS`）
   - 超出时新标签被忽略

4. **保留标签保护**
   - 系统标签（thread_id, classification, cli_version 等）不能被用户标签覆盖

### 改进建议

1. **日志脱敏**
   - 添加敏感信息检测和自动脱敏功能
   - 支持用户预览即将上传的日志内容

2. **增量上传**
   - 支持只上传自上次反馈以来的新日志
   - 减少带宽使用和上传时间

3. **离线反馈队列**
   - 当网络不可用时，本地缓存反馈
   - 网络恢复后自动上传

4. **反馈状态追踪**
   - 添加反馈 ID 和上传状态查询
   - 支持用户查看历史反馈状态

5. **配置热更新**
   - 支持运行时动态调整缓冲区大小
   - 支持动态启用/禁用反馈功能

6. **测试覆盖**
   - 当前测试主要覆盖环形缓冲区和元数据层
   - 建议添加 Sentry 上传的 mock 测试

---

## 测试

### 单元测试

位于 `src/lib.rs` 和 `src/feedback_diagnostics.rs` 的 `#[cfg(test)]` 模块：

1. **`ring_buffer_drops_front_when_full`** - 验证环形缓冲区淘汰逻辑
2. **`metadata_layer_records_tags_from_feedback_target`** - 验证元数据收集
3. **`feedback_attachments_gate_connectivity_diagnostics`** - 验证附件生成
4. **`collect_from_pairs_reports_raw_values_and_attachment`** - 验证诊断收集

### 集成测试

- TUI 中的快照测试（`feedback_view_*.snap`）
- App Server 的反馈上传 API 测试

---

## 总结

`codex-feedback` 是一个设计简洁、职责明确的反馈收集模块。它通过 tracing 集成实现无侵入式的日志捕获，通过 Sentry 实现可靠的上传，并通过诊断信息收集帮助排查连接问题。主要改进方向包括敏感信息保护、离线支持和更灵活的配置。
