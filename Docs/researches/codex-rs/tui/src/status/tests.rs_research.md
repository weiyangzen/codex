# tests.rs 研究文档

## 场景与职责

`tests.rs` 是 Codex TUI 状态显示模块的测试文件，提供单元测试和快照测试，验证状态卡片的渲染输出是否符合预期。测试覆盖多种场景，包括推理详情显示、权限自定义、Fork 信息、速率限制、额度显示、Token 使用量、终端宽度适配等。

## 功能点目的

### 测试覆盖场景

| 测试函数 | 测试场景 |
|----------|----------|
| `status_snapshot_includes_reasoning_details` | 推理配置（reasoning effort, summaries）显示 |
| `status_permissions_non_default_workspace_write_is_custom` | 自定义权限显示 |
| `status_snapshot_includes_forked_from` | Fork 会话信息显示 |
| `status_snapshot_includes_monthly_limit` | 月度限制（30天窗口）显示 |
| `status_snapshot_shows_unlimited_credits` | 无限额度显示 |
| `status_snapshot_shows_positive_credits` | 正额度显示（含四舍五入） |
| `status_snapshot_hides_zero_credits` | 零额度隐藏 |
| `status_snapshot_hides_when_has_no_credits_flag` | 未启用额度跟踪时隐藏 |
| `status_card_token_usage_excludes_cached_tokens` | Token 使用量不包含缓存 Token |
| `status_snapshot_truncates_in_narrow_terminal` | 窄终端截断处理 |
| `status_snapshot_shows_missing_limits_message` | 缺失限制数据提示 |
| `status_snapshot_includes_credits_and_limits` | 额度和限制同时显示 |
| `status_snapshot_shows_empty_limits_message` | 空限制数据提示 |
| `status_snapshot_shows_stale_limits_message` | 过期限制数据警告 |
| `status_snapshot_cached_limits_hide_credits_without_flag` | 无额度标志时隐藏 |
| `status_context_window_uses_last_usage` | 上下文窗口使用最后使用量 |

## 具体技术实现

### 测试基础设施

#### 配置创建
```rust
async fn test_config(temp_home: &TempDir) -> Config {
    ConfigBuilder::default()
        .codex_home(temp_home.path().to_path_buf())
        .build()
        .await
        .expect("load config")
}
```

#### 认证管理器创建
```rust
fn test_auth_manager(config: &Config) -> AuthManager {
    AuthManager::new(
        config.codex_home.clone(),
        false,  // disable_auto_refresh
        config.cli_auth_credentials_store_mode,
    )
}
```

#### Token 使用信息构建
```rust
fn token_info_for(model_slug: &str, config: &Config, usage: &TokenUsage) -> TokenUsageInfo {
    let context_window = codex_core::test_support::construct_model_info_offline(model_slug, config)
        .context_window;
    TokenUsageInfo {
        total_token_usage: usage.clone(),
        last_token_usage: usage.clone(),
        model_context_window: context_window,
    }
}
```

#### 行渲染辅助
```rust
fn render_lines(lines: &[Line<'static>]) -> Vec<String> {
    lines.iter()
        .map(|line| {
            line.spans
                .iter()
                .map(|span| span.content.as_ref())
                .collect::<String>()
        })
        .collect()
}
```

#### 目录路径脱敏
```rust
fn sanitize_directory(lines: Vec<String>) -> Vec<String> {
    lines.into_iter()
        .map(|line| {
            if let (Some(dir_pos), Some(pipe_idx)) = (line.find("Directory: "), line.rfind('│')) {
                let prefix = &line[..dir_pos + "Directory: ".len()];
                let suffix = &line[pipe_idx..];
                let content_width = pipe_idx.saturating_sub(dir_pos + "Directory: ".len());
                let replacement = "[[workspace]]";
                let mut rebuilt = prefix.to_string();
                rebuilt.push_str(replacement);
                if content_width > replacement.len() {
                    rebuilt.push_str(&" ".repeat(content_width - replacement.len()));
                }
                rebuilt.push_str(suffix);
                rebuilt
            } else {
                line
            }
        })
        .collect()
}
```

#### 重置时间计算
```rust
fn reset_at_from(captured_at: &chrono::DateTime<chrono::Local>, seconds: i64) -> i64 {
    (*captured_at + ChronoDuration::seconds(seconds))
        .with_timezone(&Utc)
        .timestamp()
}
```

### 测试用例详解

#### 1. 推理详情显示测试
```rust
#[tokio::test]
async fn status_snapshot_includes_reasoning_details() {
    // 配置推理 effort 和 summaries
    config.model = Some("gpt-5.1-codex-max".to_string());
    config.model_reasoning_summary = Some(ReasoningSummary::Detailed);
    
    // 设置 reasoning_effort_override
    let reasoning_effort_override = Some(Some(ReasoningEffort::High));
    
    // 创建状态卡片并验证快照
    let composite = new_status_output(..., reasoning_effort_override);
    assert_snapshot!(sanitized);
}
```

#### 2. 权限自定义测试
```rust
#[tokio::test]
async fn status_permissions_non_default_workspace_write_is_custom() {
    // 设置非默认权限
    config.permissions.approval_policy.set(AskForApproval::OnRequest);
    config.permissions.sandbox_policy.set(SandboxPolicy::WorkspaceWrite {
        network_access: true,  // 非默认配置
        ...
    });
    
    // 验证权限行显示 "Custom (...)"
    assert_eq!(permissions_text, Some("Custom (workspace-write with network access, on-request)"));
}
```

#### 3. Fork 信息显示测试
```rust
#[tokio::test]
async fn status_snapshot_includes_forked_from() {
    let session_id = ThreadId::from_string("0f0f3c13-...").expect("session id");
    let forked_from = ThreadId::from_string("e9f18a88-...").expect("forked id");
    
    let composite = new_status_output(..., &Some(session_id), ..., Some(forked_from), ...);
    // 验证快照包含 Session 和 Forked from 行
}
```

#### 4. 额度显示测试组
```rust
// 无限额度
async fn status_snapshot_shows_unlimited_credits() {
    let snapshot = RateLimitSnapshot {
        credits: Some(CreditsSnapshot { has_credits: true, unlimited: true, balance: None }),
        ...
    };
    // 验证包含 "Credits: Unlimited"
}

// 正额度（四舍五入）
async fn status_snapshot_shows_positive_credits() {
    let snapshot = RateLimitSnapshot {
        credits: Some(CreditsSnapshot { has_credits: true, unlimited: false, balance: Some("12.5") }),
        ...
    };
    // 验证包含 "Credits: 13 credits"（12.5 四舍五入）
}

// 零额度隐藏
async fn status_snapshot_hides_zero_credits() {
    let snapshot = RateLimitSnapshot {
        credits: Some(CreditsSnapshot { has_credits: true, unlimited: false, balance: Some("0") }),
        ...
    };
    // 验证不包含 "Credits:" 行
}
```

#### 5. 窄终端适配测试
```rust
#[tokio::test]
async fn status_snapshot_truncates_in_narrow_terminal() {
    // 使用 70 列宽度（而非标准的 80）
    let mut rendered_lines = render_lines(&composite.display_lines(70));
    // 验证快照显示正确的截断行为
}
```

#### 6. 过期限制数据测试
```rust
#[tokio::test]
async fn status_snapshot_shows_stale_limits_message() {
    let captured_at = ...;  // 捕获时间
    let now = captured_at + ChronoDuration::minutes(20);  // 20 分钟后（超过 15 分钟阈值）
    
    let composite = new_status_output(..., now, ...);
    // 验证包含 "limits may be stale" 警告
}
```

#### 7. 上下文窗口测试
```rust
#[tokio::test]
async fn status_context_window_uses_last_usage() {
    let total_usage = TokenUsage { total_tokens: 102_000, ... };  // 总计 102K
    let last_usage = TokenUsage { total_tokens: 13_679, ... };     // 最后 13.7K
    
    let token_info = TokenUsageInfo {
        total_token_usage: total_usage.clone(),
        last_token_usage: last_usage,  // 应使用此值
        model_context_window: Some(272_000),
    };
    
    // 验证显示 "13.7K used" 而非 "102K"
}
```

## 关键代码路径与文件引用

### 测试依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `new_status_output` | `card.rs` | 创建单限制组状态卡片（测试导出） |
| `rate_limit_snapshot_display` | `rate_limits.rs` | 转换速率限制快照（测试导出） |
| `HistoryCell` | `history_cell.rs` | 渲染接口 |
| `ConfigBuilder` | `codex_core::config` | 测试配置构建 |
| `AuthManager` | `codex_core::AuthManager` | 测试认证管理器 |
| `TokenUsageInfo` | `codex_protocol::protocol` | Token 使用信息 |
| `RateLimitSnapshot` | `codex_protocol::protocol` | 速率限制快照 |

### 测试工具

| 工具 | 用途 |
|------|------|
| `insta::assert_snapshot` | 快照测试 |
| `pretty_assertions::assert_eq` | 清晰的差异比较 |
| `tempfile::TempDir` | 临时目录 |
| `chrono::TimeZone` | 固定时间戳 |

### 快照文件

测试生成以下快照文件（位于 `src/snapshots/`）：
- `codex_tui__status__tests__status_snapshot_includes_reasoning_details.snap`
- `codex_tui__status__tests__status_snapshot_includes_forked_from.snap`
- `codex_tui__status__tests__status_snapshot_includes_monthly_limit.snap`
- `codex_tui__status__tests__status_snapshot_truncates_in_narrow_terminal.snap`
- `codex_tui__status__tests__status_snapshot_shows_missing_limits_message.snap`
- `codex_tui__status__tests__status_snapshot_includes_credits_and_limits.snap`
- `codex_tui__status__tests__status_snapshot_shows_empty_limits_message.snap`
- `codex_tui__status__tests__status_snapshot_shows_stale_limits_message.snap`
- `codex_tui__status__tests__status_snapshot_cached_limits_hide_credits_without_flag.snap`

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `insta` | 快照测试框架 |
| `pretty_assertions` | 测试断言美化 |
| `tempfile` | 临时目录创建 |
| `chrono` | 固定时间戳 |
| `tokio` | 异步测试运行时 |

### 内部模块依赖

```rust
use super::new_status_output;
use super::rate_limit_snapshot_display;
use crate::history_cell::HistoryCell;
use codex_core::AuthManager;
use codex_core::config::Config;
use codex_core::config::ConfigBuilder;
use codex_protocol::ThreadId;
use codex_protocol::protocol::TokenUsage;
use codex_protocol::protocol::TokenUsageInfo;
use codex_protocol::protocol::RateLimitSnapshot;
use codex_protocol::protocol::RateLimitWindow;
use codex_protocol::protocol::CreditsSnapshot;
```

## 风险、边界与改进建议

### 测试设计优点

1. **快照测试**: 捕获完整的渲染输出，易于发现 UI 回归
2. **固定时间戳**: 使用 `with_ymd_and_hms` 确保测试可重复
3. **路径脱敏**: `sanitize_directory` 避免环境相关差异
4. **跨平台处理**: Windows 路径分隔符转换

### 潜在风险

1. **快照维护成本**:
   - 9 个快照文件需要维护
   - UI 微调可能导致大量快照更新

2. **测试数据硬编码**:
   - 模型名称、时间戳、UUID 等硬编码
   - 协议变化可能需要同步更新

3. **异步测试复杂性**:
   - 所有测试都是异步的（`#[tokio::test]`）
   - 虽然当前测试是同步的，但框架支持异步配置加载

4. **覆盖率盲点**:
   - 未测试多限制组场景
   - 未测试 AGENTS.md 发现逻辑
   - 未测试模型提供商显示

### 改进建议

1. **参数化测试**:
   ```rust
   #[rstest]
   #[case("gpt-5.1-codex-max", Some(ReasoningEffort::High))]
   #[case("gpt-5.1-codex", None)]
   async fn status_with_various_models(#[case] model: &str, #[case] effort: Option<ReasoningEffort>) {
       // 减少重复代码
   }
   ```

2. **测试数据工厂**:
   ```rust
   fn create_test_rate_limit_snapshot(used_percent: f64, credits: Option<&str>) -> RateLimitSnapshot {
       // 统一测试数据创建
   }
   ```

3. **更多边界测试**:
   - 极长模型名称
   - 极深目录路径
   - 多限制组（codex + codex_other）
   - 各种 PlanType 组合

4. **性能测试**:
   - 大数据量下的渲染性能
   - 频繁渲染的内存使用

5. **可访问性测试**:
   - 验证颜色对比度
   - 验证屏幕阅读器输出

### 代码度量

- 代码行数: 1030 行
- 测试函数: 16 个
- 辅助函数: 5 个
- 快照文件: 9 个
- 平均测试长度: ~60 行

### 维护建议

1. **更新快照**:
   ```bash
   cargo insta review -p codex-tui
   ```

2. **添加新测试**:
   - 遵循现有模式：配置 → 数据 → 渲染 → 断言
   - 使用固定时间戳
   - 考虑是否需要新快照

3. **调试失败测试**:
   - 检查 `*.snap.new` 文件
   - 使用 `cargo insta show` 预览差异
