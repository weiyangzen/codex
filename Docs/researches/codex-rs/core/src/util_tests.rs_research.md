# util_tests.rs 研究文档

## 场景与职责

`util_tests.rs` 是 `util.rs` 的配套测试模块，负责验证通用工具功能的正确性。测试覆盖：

1. **错误消息解析**：验证服务器错误 JSON 的解析
2. **反馈标签宏**：验证 `feedback_tags!` 宏的行为
3. **认证遥测**：验证认证相关遥测的发射和格式
4. **实用函数**：验证线程名称规范化、恢复命令生成等

## 功能点目的

### 测试用例设计意图

| 测试函数 | 目的 |
|----------|------|
| `test_try_parse_error_message` | 验证标准 OpenAI 错误格式解析 |
| `test_try_parse_error_message_no_error` | 验证非错误 JSON 的处理 |
| `feedback_tags_macro_compiles` | 验证宏的基本编译 |
| `emit_feedback_request_tags_records_sentry_feedback_fields` | 验证完整请求遥测发射 |
| `emit_feedback_auth_recovery_tags_preserves_401_specific_fields` | 验证 401 恢复标签 |
| `emit_feedback_auth_recovery_tags_clears_stale_401_fields` | 验证标签更新逻辑 |
| `emit_feedback_request_tags_preserves_latest_auth_fields_after_unauthorized` | 验证未授权后的字段保留 |
| `emit_feedback_request_tags_preserves_auth_env_fields_for_legacy_emitters` | 验证环境字段保留 |
| `normalize_thread_name_trims_and_rejects_empty` | 验证名称规范化 |
| `resume_command_*` | 验证恢复命令生成逻辑 |

## 具体技术实现

### 测试基础设施

#### TagCollectorLayer

自定义 `tracing` 层用于捕获遥测事件：

```rust
#[derive(Clone)]
struct TagCollectorLayer {
    tags: Arc<Mutex<BTreeMap<String, String>>>,
    event_count: Arc<Mutex<usize>>,
}
```

- 只捕获 `target: "feedback_tags"` 的事件
- 将字段存入 `BTreeMap`
- 统计事件数量

#### TagCollectorVisitor

实现 `tracing::field::Visit`：

```rust
#[derive(Default)]
struct TagCollectorVisitor {
    tags: BTreeMap<String, String>,
}
```

- 记录 `bool` 字段
- 记录 `str` 字段
- 记录 `debug` 格式字段

### 测试 1：错误消息解析

```rust
#[test]
fn test_try_parse_error_message()
```

**输入**：
```json
{
  "error": {
    "message": "Your refresh token has already been used...",
    "type": "invalid_request_error",
    "param": null,
    "code": "refresh_token_reused"
  }
}
```

**验证**：正确提取 `error.message` 字段。

### 测试 2：反馈标签宏

```rust
#[test]
fn feedback_tags_macro_compiles()
```

**内容**：
- 定义仅实现 `Debug` 的结构体
- 使用宏发射标签
- 验证编译通过

### 测试 3：完整遥测发射

```rust
#[test]
fn emit_feedback_request_tags_records_sentry_feedback_fields()
```

**流程**：
1. 设置 `TagCollectorLayer`
2. 构造 `AuthEnvTelemetry` 和 `FeedbackRequestTags`
3. 调用 `emit_feedback_request_tags_with_auth_env`
4. 验证 14+ 个字段的值

**验证字段**：
- `endpoint`
- `auth_header_attached`
- `auth_env_openai_api_key_present`
- `auth_env_codex_api_key_present`
- 等

### 测试 4：401 恢复标签

```rust
#[test]
fn emit_feedback_auth_recovery_tags_preserves_401_specific_fields()
```

**验证**：
- `auth_401_request_id`
- `auth_401_cf_ray`
- `auth_401_error`
- `auth_401_error_code`

### 测试 5：线程名称规范化

```rust
#[test]
fn normalize_thread_name_trims_and_rejects_empty()
```

**验证**：
- `"   "` -> `None`
- `"  my thread  "` -> `Some("my thread")`

### 测试 6：恢复命令生成

```rust
#[test]
fn resume_command_prefers_name_over_id()
#[test]
fn resume_command_with_only_id()
#[test]
fn resume_command_with_no_name_or_id()
#[test]
fn resume_command_quotes_thread_name_when_needed()
```

**验证场景**：
- 名称优先于 ID
- 仅 ID 可用
- 两者都不可用
- 需要引号的名称（以 `-` 开头、包含空格、包含引号）

## 关键代码路径与文件引用

### 被测试代码

| 被测试项 | 定义位置 |
|----------|----------|
| `try_parse_error_message` | `util.rs:220` |
| `feedback_tags!` | `util.rs:31` |
| `emit_feedback_request_tags` | `util.rs:127` |
| `emit_feedback_request_tags_with_auth_env` | `util.rs:148` |
| `emit_feedback_auth_recovery_tags` | `util.rs:179` |
| `normalize_thread_name` | `util.rs:244` |
| `resume_command` | `util.rs:253` |

### 测试依赖

| 依赖 | 用途 |
|------|------|
| `tracing_subscriber` | 设置测试遥测层 |
| `AuthEnvTelemetry` | 构造测试数据 |
| `ThreadId` | 构造恢复命令测试 |
| `pretty_assertions::assert_eq` | 更好的断言输出 |

## 依赖与外部交互

### Tracing 设置

```rust
let _guard = tracing_subscriber::registry()
    .with(TagCollectorLayer { ... })
    .set_default();
```

- 使用 `set_default` 设置线程本地订阅者
- 自动清理（`_guard` Drop）

### 异步测试

大部分测试是同步的（`#[test]`），除了：
- `formats_basic_record`（在 user_shell_command_tests.rs）

## 风险、边界与改进建议

### 当前测试覆盖的不足

1. **缺少退避测试**
   - 未测试 `backoff` 函数
   - 应验证计算正确性和随机性

2. **缺少路径解析测试**
   - 未测试 `resolve_path`
   - 应验证绝对/相对路径处理

3. **缺少 error_or_panic 测试**
   - 难以测试（依赖编译模式）
   - 可考虑条件编译测试

4. **缺少边界值测试**
   - `backoff` 的大 attempt 值
   - 超长线程名称
   - 特殊字符处理

5. **缺少并发测试**
   - 遥测发射的线程安全性
   - 锁的正确性

### 改进建议

1. **添加退避测试**
```rust
#[test]
fn backoff_increases_exponentially() {
    let d1 = backoff(1);
    let d2 = backoff(2);
    let d3 = backoff(3);
    assert!(d2 > d1);
    assert!(d3 > d2);
}

#[test]
fn backoff_includes_jitter() {
    // 多次调用相同 attempt，验证结果不同
}
```

2. **添加路径测试**
```rust
#[test]
fn resolve_path_handles_absolute() {
    let base = Path::new("/home/user");
    let path = PathBuf::from("/absolute/path");
    assert_eq!(resolve_path(base, &path), PathBuf::from("/absolute/path"));
}

#[test]
fn resolve_path_handles_relative() {
    let base = Path::new("/home/user");
    let path = PathBuf::from("relative/path");
    assert_eq!(resolve_path(base, &path), PathBuf::from("/home/user/relative/path"));
}
```

3. **添加边界测试**
```rust
#[test]
fn backoff_handles_large_attempt() {
    let _ = backoff(u64::MAX);
    // 验证不 panic
}
```

4. **改进遥测测试**
   - 验证字段类型（当前都转为字符串）
   - 验证嵌套结构

### 潜在风险

1. **测试与实现耦合**
   - 遥测测试依赖具体字段名称
   - 字段重命名需要更新测试

2. **字符串比较脆弱**
   - 遥测值使用字符串比较
   - 格式变更（如引号）可能导致失败

3. **测试顺序依赖**
   - 虽然测试应该是独立的
   - 但 `tracing` 订阅者是线程本地的

### 测试质量评估

| 维度 | 评分 | 说明 |
|------|------|------|
| 覆盖率 | 高 | 主要功能都有测试 |
| 可读性 | 高 | 测试意图清晰 |
| 维护性 | 中 | 字符串匹配较脆弱 |
| 可靠性 | 高 | 不依赖外部系统 |
