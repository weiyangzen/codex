# Codex Feedback Module Research Document

## 1. 场景与职责

### 1.1 模块定位
`codex-rs/feedback` 是 Codex CLI 项目的用户反馈收集与上传模块，负责：
- **运行时日志捕获**：通过环形缓冲区(ring buffer)持续收集应用日志
- **用户反馈收集**：为 TUI/Exec 等前端提供反馈上传功能
- **诊断信息收集**：自动收集网络连接相关的环境变量诊断信息
- **Sentry 集成**：将反馈数据（含日志、元数据、诊断信息）上传至 Sentry 服务

### 1.2 使用场景
| 场景 | 描述 |
|------|------|
| Bug 报告 | 用户遇到崩溃、错误消息、UI/行为异常时提交反馈 |
| 结果评价 | 用户对 AI 输出质量进行评价（好/坏结果） |
| 安全检查反馈 | 用户认为某些内容被错误地阻止时提交反馈 |
| 其他反馈 | 性能问题、功能建议、UX 反馈等 |

### 1.3 架构位置
```
┌─────────────────────────────────────────────────────────────┐
│                    TUI / Exec / App-Server                  │
│                         (调用方)                             │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐  │
│  │ CodexFeedback│───▶│FeedbackSnapshot│───▶│ upload_feedback │  │
│  │ (日志收集)   │    │ (快照生成)   │    │ (Sentry上传)   │  │
│  └─────────────┘    └─────────────┘    └─────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  FeedbackDiagnostics (网络诊断收集)                          │
│  - 代理环境变量检测 (HTTP_PROXY, HTTPS_PROXY, etc.)          │
│  - OPENAI_BASE_URL 检测                                      │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 核心功能

#### 2.1.1 日志收集 (`CodexFeedback`)
- **目的**：在运行时持续收集日志，为问题排查提供上下文
- **实现**：使用固定大小（默认 4MiB）的环形缓冲区，避免内存无限增长
- **特点**：
  - 线程安全（基于 `Mutex<VecDeque<u8>>`）
  - 自动淘汰旧数据（FIFO）
  - 支持通过 `tracing` 集成

#### 2.1.2 元数据收集 (`feedback_tags`)
- **目的**：收集结构化元数据（如模型版本、认证模式等）用于问题分析
- **实现**：通过 `tracing` 的 `feedback_tags` target 收集，支持以下类型：
  - `i64`, `u64`, `bool`, `f64`, `str`, `debug`
- **限制**：最多 64 个标签（`MAX_FEEDBACK_TAGS`）

#### 2.1.3 网络诊断 (`FeedbackDiagnostics`)
- **目的**：自动检测可能影响连接的环境变量配置
- **检测项**：
  - 代理变量：`HTTP_PROXY`, `http_proxy`, `HTTPS_PROXY`, `https_proxy`, `ALL_PROXY`, `all_proxy`
  - API 端点：`OPENAI_BASE_URL`
- **输出格式**：Markdown 格式的诊断报告附件

#### 2.1.4 反馈上传 (`upload_feedback`)
- **目的**：将收集的数据发送到 Sentry 进行分析
- **上传内容**：
  - 分类标签（bug/bad_result/good_result/safety_check/other）
  - 用户备注（可选）
  - 日志文件（可选）
  - 诊断信息（自动）
  - 额外附件（如 rollout 文件）

### 2.2 反馈分类
| 分类 | 用途 | Sentry Level |
|------|------|--------------|
| `bug` | 崩溃、错误、挂起、UI/行为异常 | Error |
| `bad_result` | 输出偏离目标、不正确、不完整 | Error |
| `good_result` | 有帮助、正确、高质量的输出 | Info |
| `safety_check` | 安全检查误报 | Error |
| `other` | 其他问题 | Info |

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 `CodexFeedback` - 主入口结构
```rust
#[derive(Clone)]
pub struct CodexFeedback {
    inner: Arc<FeedbackInner>,
}

struct FeedbackInner {
    ring: Mutex<RingBuffer>,      // 日志环形缓冲区
    tags: Mutex<BTreeMap<String, String>>,  // 元数据标签
}
```

#### 3.1.2 `RingBuffer` - 环形缓冲区
```rust
struct RingBuffer {
    max: usize,                   // 最大容量（默认 4MiB）
    buf: VecDeque<u8>,           // 底层存储
}
```
**关键算法**：
- 写入时若超过容量，从头部淘汰旧数据
- 若单次写入数据超过容量，仅保留尾部数据

#### 3.1.3 `FeedbackSnapshot` - 快照结构
```rust
pub struct FeedbackSnapshot {
    bytes: Vec<u8>,                              // 日志字节
    tags: BTreeMap<String, String>,             // 元数据标签
    feedback_diagnostics: FeedbackDiagnostics,  // 网络诊断
    pub thread_id: String,                      // 会话 ID
}
```

#### 3.1.4 `FeedbackDiagnostics` - 诊断信息
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

### 3.2 关键流程

#### 3.2.1 日志收集流程
```
1. 应用代码调用 tracing::info!(...)
   ↓
2. CodexFeedback::logger_layer() 捕获日志
   ↓
3. FeedbackWriter::write() 写入 RingBuffer
   ↓
4. RingBuffer::push_bytes() 处理容量限制
```

#### 3.2.2 元数据收集流程
```
1. 应用代码调用 feedback_tags!(key = value)
   ↓
2. tracing::info!(target: "feedback_tags", ...)
   ↓
3. FeedbackMetadataLayer::on_event() 接收事件
   ↓
4. FeedbackTagsVisitor 提取键值对
   ↓
5. 存储到 FeedbackInner.tags (BTreeMap)
```

#### 3.2.3 反馈上传流程
```
1. 用户触发反馈（TUI 快捷键 / API 调用）
   ↓
2. CodexFeedback::snapshot(thread_id) 生成快照
   - 复制当前 ring buffer 内容
   - 复制 tags 映射
   - 收集 FeedbackDiagnostics
   ↓
3. FeedbackSnapshot::upload_feedback(...)
   - 构建 Sentry Event
   - 设置分类标签和级别
   - 添加附件（日志、诊断、额外文件）
   ↓
4. Sentry Client 发送 Envelope
   - 10 秒超时（UPLOAD_TIMEOUT_SECS）
   - 异步发送，不阻塞 UI
```

### 3.3 Tracing 集成

#### 3.3.1 Logger Layer 配置
```rust
pub fn logger_layer<S>(&self) -> impl Layer<S> + Send + Sync + 'static
where
    S: tracing::Subscriber + for<'a> LookupSpan<'a>,
{
    tracing_subscriber::fmt::layer()
        .with_writer(self.make_writer())
        .with_timer(tracing_subscriber::fmt::time::SystemTime)
        .with_ansi(false)
        .with_target(false)
        .with_filter(Targets::new().with_default(Level::TRACE))  // 捕获所有级别
}
```

#### 3.3.2 Metadata Layer 配置
```rust
pub fn metadata_layer<S>(&self) -> impl Layer<S> + Send + Sync + 'static
where
    S: tracing::Subscriber + for<'a> LookupSpan<'a>,
{
    FeedbackMetadataLayer { inner: self.inner.clone() }
        .with_filter(Targets::new().with_target(FEEDBACK_TAGS_TARGET, Level::TRACE))
}
```

### 3.4 Sentry 集成细节

#### 3.4.1 DSN 配置
```rust
const SENTRY_DSN: &str =
    "https://ae32ed50620d7a7792c1ce5df38b3e3e@o33249.ingest.us.sentry.io/4510195390611458";
```

#### 3.4.2 事件构建
- **标题格式**：`[分类]: Codex session {thread_id}`
- **级别映射**：
  - `bug` | `bad_result` | `safety_check` → `Level::Error`
  - 其他 → `Level::Info`
- **标签保留**：`thread_id`, `classification`, `cli_version`, `session_source`, `reason` 为保留字段

#### 3.4.3 附件类型
| 文件名 | 内容 | 条件 |
|--------|------|------|
| `codex-logs.log` | 环形缓冲区日志 | `include_logs=true` |
| `codex-connectivity-diagnostics.txt` | 网络诊断报告 | 诊断非空且 `include_logs=true` |
| 用户指定文件名 | 额外文件内容 | 提供 `extra_attachment_paths` |

---

## 4. 关键代码路径与文件引用

### 4.1 本模块文件
| 文件 | 行数 | 职责 |
|------|------|------|
| `codex-rs/feedback/src/lib.rs` | 572 | 主模块：CodexFeedback、RingBuffer、FeedbackSnapshot、Sentry 上传 |
| `codex-rs/feedback/src/feedback_diagnostics.rs` | 229 | 网络诊断收集：FeedbackDiagnostics、FeedbackDiagnostic |
| `codex-rs/feedback/Cargo.toml` | 15 | 依赖：anyhow, codex-protocol, sentry, tracing, tracing-subscriber |
| `codex-rs/feedback/BUILD.bazel` | 6 | Bazel 构建配置 |

### 4.2 调用方文件
| 文件 | 用途 |
|------|------|
| `codex-rs/tui/src/bottom_pane/feedback_view.rs` | TUI 反馈界面：FeedbackNoteView、反馈分类选择、上传确认 |
| `codex-rs/tui/src/chatwidget.rs` | ChatWidget 反馈触发、chatgpt_user_id 标签记录 |
| `codex-rs/tui/src/app.rs` | App 结构体持有 feedback 实例 |
| `codex-rs/tui/src/app_event.rs` | FeedbackCategory 枚举定义 |
| `codex-rs/tui_app_server/src/bottom_pane/feedback_view.rs` | tui_app_server 反馈界面（与 tui 并行实现） |
| `codex-rs/tui_app_server/src/app.rs` | tui_app_server App 结构体 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | tui_app_server ChatWidget |
| `codex-rs/tui_app_server/src/lib.rs` | 初始化 feedback 和 tracing layer |

### 4.3 App-Server 集成
| 文件 | 用途 |
|------|------|
| `codex-rs/app-server/src/codex_message_processor.rs` | 处理 FeedbackUpload 请求（line 6979-7102） |
| `codex-rs/app-server/src/message_processor.rs` | MessageProcessor 结构体持有 feedback |
| `codex-rs/app-server/src/in_process.rs` | InProcessClientStartArgs 包含 feedback |
| `codex-rs/app-server/src/lib.rs` | 初始化 feedback 实例 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | FeedbackUploadParams/FeedbackUploadResponse 定义（line 2100-2116） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ClientRequest::FeedbackUpload 定义（line 451-454） |

### 4.4 其他调用方
| 文件 | 用途 |
|------|------|
| `codex-rs/exec/src/lib.rs` | Exec 模式初始化 feedback（line 438） |
| `codex-rs/app-server-client/src/lib.rs` | AppServerClient 持有 feedback |
| `codex-rs/core/src/util.rs` | feedback_tags! 宏定义（line 31-39） |
| `codex-rs/core/src/codex.rs` | 使用 feedback_tags! 记录模型/策略信息（line 7012） |

### 4.5 关键代码片段

#### 4.5.1 环形缓冲区写入（lib.rs:178-201）
```rust
fn push_bytes(&mut self, data: &[u8]) {
    if data.is_empty() { return; }
    
    // 如果数据超过容量，只保留尾部
    if data.len() >= self.max {
        self.buf.clear();
        let start = data.len() - self.max;
        self.buf.extend(data[start..].iter().copied());
        return;
    }
    
    // 淘汰旧数据以腾出空间
    let needed = self.len() + data.len();
    if needed > self.max {
        let to_drop = needed - self.max;
        for _ in 0..to_drop { let _ = self.buf.pop_front(); }
    }
    
    self.buf.extend(data.iter().copied());
}
```

#### 4.5.2 Sentry 上传（lib.rs:246-343）
```rust
pub fn upload_feedback(
    &self,
    classification: &str,
    reason: Option<&str>,
    include_logs: bool,
    extra_attachment_paths: &[PathBuf],
    session_source: Option<SessionSource>,
    logs_override: Option<Vec<u8>>,
) -> Result<()> {
    // 构建 Sentry Client
    let client = Client::from_config(ClientOptions {
        dsn: Some(Dsn::from_str(SENTRY_DSN)?),
        transport: Some(Arc::new(DefaultTransportFactory {})),
        ..Default::default()
    });
    
    // 构建标签
    let mut tags = BTreeMap::from([
        (String::from("thread_id"), self.thread_id.to_string()),
        (String::from("classification"), classification.to_string()),
        (String::from("cli_version"), cli_version.to_string()),
    ]);
    
    // 构建事件和附件...
    let mut envelope = Envelope::new();
    envelope.add_item(EnvelopeItem::Event(event));
    for attachment in self.feedback_attachments(include_logs, extra_attachment_paths, logs_override) {
        envelope.add_item(EnvelopeItem::Attachment(attachment));
    }
    
    client.send_envelope(envelope);
    client.flush(Some(Duration::from_secs(UPLOAD_TIMEOUT_SECS)));
}
```

#### 4.5.3 诊断收集（feedback_diagnostics.rs:30-69）
```rust
pub fn collect_from_env() -> Self {
    Self::collect_from_pairs(std::env::vars())
}

fn collect_from_pairs<I, K, V>(pairs: I) -> Self
where
    I: IntoIterator<Item = (K, V)>,
    K: Into<String>,
    V: Into<String>,
{
    let env = pairs.into_iter()
        .map(|(k, v)| (k.into(), v.into()))
        .collect::<HashMap<_, _>>();
    let mut diagnostics = Vec::new();
    
    // 收集代理变量
    let proxy_details = PROXY_ENV_VARS.iter()
        .filter_map(|key| env.get(*key).map(|v| format!("{key} = {v}")))
        .collect::<Vec<_>>();
    if !proxy_details.is_empty() {
        diagnostics.push(FeedbackDiagnostic {
            headline: "Proxy environment variables are set and may affect connectivity.".to_string(),
            details: proxy_details,
        });
    }
    
    // 收集 OPENAI_BASE_URL
    if let Some(value) = env.get(OPENAI_BASE_URL_ENV_VAR) {
        diagnostics.push(FeedbackDiagnostic {
            headline: "OPENAI_BASE_URL is set and may affect connectivity.".to_string(),
            details: vec![format!("{OPENAI_BASE_URL_ENV_VAR} = {value}")],
        });
    }
    
    Self { diagnostics }
}
```

---

## 5. 依赖与外部交互

### 5.1 依赖 crate
| Crate | 用途 |
|-------|------|
| `anyhow` | 错误处理 |
| `codex-protocol` | ThreadId、SessionSource 类型 |
| `sentry` (0.46) | Sentry 客户端、Event、Envelope、Attachment |
| `tracing` | 日志框架集成 |
| `tracing-subscriber` | Layer、MakeWriter 实现 |

### 5.2 外部服务
| 服务 | 用途 | 配置 |
|------|------|------|
| Sentry | 反馈数据接收 | 硬编码 DSN，10 秒超时 |
| GitHub Issues | 外部用户问题跟踪 | `BASE_CLI_BUG_ISSUE_URL` |
| 内部 Slack (go/codex-feedback-internal) | OpenAI 员工内部反馈 | `CODEX_FEEDBACK_INTERNAL_URL` |

### 5.3 协议集成

#### 5.3.1 App-Server Protocol V2
```rust
// FeedbackUploadParams (v2.rs:2100-2109)
pub struct FeedbackUploadParams {
    pub classification: String,
    #[ts(optional = nullable)]
    pub reason: Option<String>,
    #[ts(optional = nullable)]
    pub thread_id: Option<String>,
    pub include_logs: bool,
    #[ts(optional = nullable)]
    pub extra_log_files: Option<Vec<PathBuf>>,
}

// FeedbackUploadResponse (v2.rs:2114-2116)
pub struct FeedbackUploadResponse {
    pub thread_id: String,
}
```

#### 5.3.2 ClientRequest 枚举
```rust
// common.rs:451-454
FeedbackUpload => "feedback/upload" {
    params: v2::FeedbackUploadParams,
    response: v2::FeedbackUploadResponse,
}
```

### 5.4 配置项
| 配置 | 位置 | 说明 |
|------|------|------|
| `feedback_enabled` | `codex_core::config::Config` | 控制是否允许发送反馈 |
| `SENTRY_DSN` | `lib.rs` (硬编码) | Sentry 项目 DSN |
| `DEFAULT_MAX_BYTES` | `lib.rs` (4MiB) | 环形缓冲区默认大小 |
| `UPLOAD_TIMEOUT_SECS` | `lib.rs` (10秒) | Sentry 上传超时 |
| `MAX_FEEDBACK_TAGS` | `lib.rs` (64) | 最大标签数量 |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 安全风险
| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 敏感信息泄露 | 日志可能包含 API 密钥、文件内容 | 用户可选择不上传日志（`include_logs=false`） |
| 代理凭证泄露 | 代理 URL 可能包含密码（如 `https://user:pass@proxy`） | 诊断信息原样记录，但仅用于调试 |
| Sentry DSN 暴露 | DSN 硬编码在源码中 | DSN 是公开可发布的客户端密钥 |

#### 6.1.2 可靠性风险
| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 上传超时 | 网络问题导致上传阻塞 | 10 秒超时，异步发送 |
| 内存溢出 | 环形缓冲区无限增长 | 固定 4MiB 上限，FIFO 淘汰 |
| Mutex 死锁 | `lock().expect("mutex poisoned")` 可能 panic | 使用标准库 Mutex，中毒后 panic 是可接受的 |

#### 6.1.3 隐私风险
| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| chatgpt_user_id 收集 | 上传时记录用户 ID | 仅用于问题排查，不关联到外部 |
| thread_id 暴露 | 会话 ID 随反馈上传 | 用于关联问题，用户可见 |

### 6.2 边界情况

#### 6.2.1 环形缓冲区边界
- **空缓冲区**：`snapshot_bytes()` 返回空 Vec
- **满缓冲区**：新数据从头部淘汰旧数据
- **超大单次写入**：超过容量的数据仅保留尾部（line 184-189）

#### 6.2.2 标签收集边界
- **标签数量限制**：超过 64 个标签时，新键被忽略（保留已有键）
- **保留字段保护**：`thread_id`, `classification`, `cli_version`, `session_source`, `reason` 不会被用户标签覆盖

#### 6.2.3 附件处理边界
- **文件读取失败**：记录警告日志，跳过该附件（line 374-383）
- **无文件名**：使用默认名 "extra-log.log"
- **诊断为空**：不生成诊断附件

#### 6.2.4 上传边界
- **反馈禁用**：通过配置禁用反馈时，App-Server 返回错误（line 6980-6988）
- **无效 thread_id**：解析失败时返回错误（line 6998-7012）
- **上传失败**：返回内部错误，不阻塞用户操作

### 6.3 改进建议

#### 6.3.1 安全性改进
1. **敏感信息脱敏**
   - 在日志写入环形缓冲区前，使用正则表达式脱敏 API 密钥
   - 对代理 URL 中的密码部分进行掩码处理

2. **用户确认增强**
   - 在上传前显示日志预览，让用户确认是否包含敏感信息
   - 提供 "编辑日志" 功能，允许用户删除敏感行

#### 6.3.2 功能性改进
1. **动态缓冲区大小**
   - 支持通过配置调整环形缓冲区大小
   - 考虑使用分层存储（内存 + 临时文件）支持更大日志

2. **标签命名空间**
   - 引入标签前缀机制，避免不同模块的标签冲突
   - 支持标签分类（如 `model.*`, `auth.*`, `network.*`）

3. **诊断扩展**
   - 收集更多网络诊断信息（如 DNS 配置、TLS 版本）
   - 检测常见代理工具（如 Clash、Shadowsocks）

#### 6.3.3 可观测性改进
1. **上传指标**
   - 添加反馈上传成功率/延迟指标
   - 记录上传失败原因分类

2. **日志质量**
   - 添加日志轮转和压缩
   - 支持结构化日志（JSON）便于分析

#### 6.3.4 代码质量改进
1. **错误处理**
   - 将 `lock().expect()` 改为更优雅的错误处理
   - 添加上传重试机制（指数退避）

2. **测试覆盖**
   - 添加 Sentry 上传的 mock 测试
   - 测试大文件附件处理
   - 测试网络超时场景

3. **文档完善**
   - 添加用户文档说明反馈上传的内容和用途
   - 添加开发者文档说明如何添加新的诊断检查

### 6.4 技术债务

| 项目 | 描述 | 优先级 |
|------|------|--------|
| Sentry DSN 硬编码 | 无法在不重新编译的情况下切换 Sentry 项目 | 低 |
| 诊断信息无国际化 | 诊断信息仅英文 | 低 |
| 反馈分类硬编码 | 分类字符串在多处硬编码 | 中 |
| 缺乏反馈去重 | 相同问题可能多次上传 | 低 |

---

## 7. 附录

### 7.1 常量汇总
| 常量 | 值 | 位置 |
|------|-----|------|
| `DEFAULT_MAX_BYTES` | 4 * 1024 * 1024 (4MiB) | lib.rs:28 |
| `SENTRY_DSN` | "https://ae32ed506..." | lib.rs:29-30 |
| `UPLOAD_TIMEOUT_SECS` | 10 | lib.rs:31 |
| `FEEDBACK_TAGS_TARGET` | "feedback_tags" | lib.rs:32 |
| `MAX_FEEDBACK_TAGS` | 64 | lib.rs:33 |
| `FEEDBACK_DIAGNOSTICS_ATTACHMENT_FILENAME` | "codex-connectivity-diagnostics.txt" | feedback_diagnostics.rs:4 |

### 7.2 环境变量检测列表
```rust
const PROXY_ENV_VARS: &[&str] = &[
    "HTTP_PROXY", "http_proxy",
    "HTTPS_PROXY", "https_proxy",
    "ALL_PROXY", "all_proxy",
];
const OPENAI_BASE_URL_ENV_VAR: &str = "OPENAI_BASE_URL";
```

### 7.3 测试文件
| 文件 | 测试内容 |
|------|----------|
| `lib.rs` (line 480-571) | 环形缓冲区、元数据层、附件生成 |
| `feedback_diagnostics.rs` (line 99-228) | 诊断收集、格式化、边界情况 |

---

*文档生成时间：2026-03-22*
*基于代码版本：codex-rs/feedback/src 当前 HEAD*
