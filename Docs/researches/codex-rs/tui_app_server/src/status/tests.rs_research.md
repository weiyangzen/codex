# tests.rs 研究文档

## 场景与职责

`tests.rs` 是 `tui_app_server/src/status/` 模块的测试文件，包含 18 个异步测试用例，全面覆盖状态卡片的各种渲染场景。使用 `insta` 快照测试验证 UI 输出，确保状态显示的正确性和一致性。

### 核心职责
1. **快照测试**: 验证状态卡片在不同配置下的渲染输出
2. **功能测试**: 验证特定功能（如额度显示、权限摘要）
3. **边界测试**: 测试窄终端、缺失数据等边界情况

## 功能点目的

### 测试分类

| 类别 | 测试函数 | 目的 |
|------|----------|------|
| **推理配置** | `status_snapshot_includes_reasoning_details` | 验证推理 effort 和 summaries 显示 |
| **权限显示** | `status_permissions_non_default_workspace_write_is_custom` | 验证自定义权限摘要 |
| **会话信息** | `status_snapshot_includes_forked_from` | 验证 fork 来源显示 |
| **速率限制** | `status_snapshot_includes_monthly_limit` | 验证月度限制显示 |
| **额度显示** | `status_snapshot_shows_unlimited_credits` | 验证无限额度 |
| | `status_snapshot_shows_positive_credits` | 验证正数额度 |
| | `status_snapshot_hides_zero_credits` | 验证零额度隐藏 |
| | `status_snapshot_hides_when_has_no_credits_flag` | 验证无额度标志时隐藏 |
| **令牌使用** | `status_card_token_usage_excludes_cached_tokens` | 验证不显示缓存令牌 |
| | `status_context_window_uses_last_usage` | 验证使用 last_usage 而非 total |
| **边界情况** | `status_snapshot_truncates_in_narrow_terminal` | 验证窄终端截断 |
| | `status_snapshot_shows_missing_limits_message` | 验证缺失限制提示 |
| | `status_snapshot_shows_empty_limits_message` | 验证空限制提示 |
| | `status_snapshot_shows_stale_limits_message` | 验证过期数据提示 |
| **综合场景** | `status_snapshot_includes_credits_and_limits` | 验证额度和限制同时显示 |
| | `status_snapshot_cached_limits_hide_credits_without_flag` | 验证无额度标志时隐藏 |

## 具体技术实现

### 测试基础设施

#### 测试配置创建

```rust
async fn test_config(temp_home: &TempDir) -> Config {
    ConfigBuilder::default()
        .codex_home(temp_home.path().to_path_buf())
        .build()
        .await
        .expect("load config")
}
```

使用 `tempfile::TempDir` 创建隔离的测试环境。

#### 令牌信息构造

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
    lines
        .iter()
        .map(|line| {
            line.spans
                .iter()
                .map(|span| span.content.as_ref())
                .collect::<String>()
        })
        .collect()
}
```

将 ratatui 的 `Line` 转换为纯文本字符串用于断言。

#### 目录路径脱敏

```rust
fn sanitize_directory(lines: Vec<String>) -> Vec<String> {
    lines
        .into_iter()
        .map(|line| {
            if let (Some(dir_pos), Some(pipe_idx)) = 
                (line.find("Directory: "), line.rfind('│')) {
                // 将实际路径替换为 [[workspace]]
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

将实际目录路径替换为固定占位符，确保快照测试的可移植性。

#### 重置时间计算

```rust
fn reset_at_from(captured_at: &chrono::DateTime<chrono::Local>, seconds: i64) -> i64 {
    (*captured_at + ChronoDuration::seconds(seconds))
        .with_timezone(&Utc)
        .timestamp()
}
```

计算相对于捕获时间的未来 UTC 时间戳。

### 典型测试模式

以 `status_snapshot_includes_reasoning_details` 为例：

```rust
#[tokio::test]
async fn status_snapshot_includes_reasoning_details() {
    // 1. 设置临时配置
    let temp_home = TempDir::new().expect("temp home");
    let mut config = test_config(&temp_home).await;
    
    // 2. 配置测试场景
    config.model = Some("gpt-5.1-codex-max".to_string());
    config.model_provider_id = "openai".to_string();
    config.model_reasoning_summary = Some(ReasoningSummary::Detailed);
    config.permissions.sandbox_policy.set(SandboxPolicy::WorkspaceWrite { ... })
        .expect("set sandbox policy");
    config.cwd = PathBuf::from("/workspace/tests");

    // 3. 准备测试数据
    let account_display = test_status_account_display();
    let usage = TokenUsage { ... };
    let captured_at = chrono::Local
        .with_ymd_and_hms(2024, 1, 2, 3, 4, 5)
        .single()
        .expect("timestamp");
    let snapshot = RateLimitSnapshot { ... };
    let rate_display = rate_limit_snapshot_display(&snapshot, captured_at);

    // 4. 创建状态输出
    let model_slug = codex_core::test_support::get_model_offline(config.model.as_deref());
    let token_info = token_info_for(&model_slug, &config, &usage);
    let reasoning_effort_override = Some(Some(ReasoningEffort::High));
    let composite = new_status_output(
        &config, account_display.as_ref(), Some(&token_info), &usage,
        &None, None, None, Some(&rate_display), None, captured_at,
        &model_slug, None, reasoning_effort_override,
    );

    // 5. 渲染并处理
    let mut rendered_lines = render_lines(&composite.display_lines(80));
    if cfg!(windows) {
        for line in &mut rendered_lines {
            *line = line.replace('\\', "/");
        }
    }
    let sanitized = sanitize_directory(rendered_lines).join("\n");
    
    // 6. 断言快照
    assert_snapshot!(sanitized);
}
```

### 测试数据模式

#### 标准 TokenUsage

```rust
TokenUsage {
    input_tokens: 1_200,
    cached_input_tokens: 200,      // 不应显示
    output_tokens: 900,
    reasoning_output_tokens: 150,  // 模型相关
    total_tokens: 2_250,
}
```

#### 标准 RateLimitSnapshot

```rust
RateLimitSnapshot {
    limit_id: None,
    limit_name: None,
    primary: Some(RateLimitWindow {
        used_percent: 72.5,
        window_minutes: Some(300),    // 5小时
        resets_at: Some(reset_at_from(&captured_at, 600)),
    }),
    secondary: Some(RateLimitWindow {
        used_percent: 45.0,
        window_minutes: Some(10080),  // 每周
        resets_at: Some(reset_at_from(&captured_at, 1_200)),
    }),
    credits: None,
    plan_type: None,
}
```

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/status/tests.rs` - 1026 行

### 测试依赖
| 文件 | 用途 |
|------|------|
| `card.rs` | `new_status_output` - 创建状态输出 |
| `rate_limits.rs` | `rate_limit_snapshot_display` - 快照转换 |
| `account.rs` | `StatusAccountDisplay` - 账户显示类型 |
| `../history_cell.rs` | `HistoryCell` - 渲染 trait |

### 外部 crate 依赖
| Crate | 用途 |
|-------|------|
| `chrono` | 时间构造和时区处理 |
| `codex_core` | `Config`, `ConfigBuilder`, 测试支持函数 |
| `codex_protocol` | `ThreadId`, `TokenUsage`, `RateLimitSnapshot` 等 |
| `insta` | 快照测试框架 |
| `pretty_assertions` | 清晰的断言输出 |
| `ratatui` | `Line` 类型处理 |
| `tempfile` | 临时目录创建 |

### 快照文件

测试生成的快照存储在：
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/snapshots/`

命名模式：`codex_tui_app_server__status__tests__{test_name}.snap`

## 依赖与外部交互

### 与 codex_core 测试支持的交互

```rust
use codex_core::test_support::construct_model_info_offline;
use codex_core::test_support::get_model_offline;
```

这些函数提供离线环境下的模型信息查询，无需实际 API 调用。

### 与快照测试的交互

使用 `insta` crate 进行快照测试：
```rust
assert_snapshot!(sanitized);
```

首次运行生成 `.snap.new` 文件，审核后通过 `cargo insta accept` 接受。

### 平台处理

```rust
if cfg!(windows) {
    for line in &mut rendered_lines {
        *line = line.replace('\\', "/");
    }
}
```

统一 Windows 和 Unix 的路径分隔符，确保快照一致性。

## 风险、边界与改进建议

### 当前限制

1. **硬编码时间**: 所有测试使用固定的 2024 年时间戳
2. **硬编码路径**: 使用 `/workspace/tests` 作为测试目录
3. **平台特殊处理**: Windows 路径替换可能掩盖实际平台差异

### 测试覆盖分析

| 场景 | 覆盖 | 说明 |
|------|------|------|
| 推理配置 | ✅ | effort 和 summaries |
| 权限摘要 | ✅ | Default/Full Access/Custom |
| Fork 信息 | ✅ | forked_from 显示 |
| 速率限制 | ✅ | 5h/weekly/monthly |
| 额度显示 | ✅ | unlimited/positive/zero/has_credits=false |
| 令牌使用 | ✅ | 排除缓存令牌，使用 last_usage |
| 窄终端 | ✅ | 70 列宽度测试 |
| 数据缺失 | ✅ | missing/empty limits |
| 数据过期 | ✅ | stale 阈值测试 |

### 潜在改进

1. **参数化测试**: 使用 `rstest` 或类似框架减少重复代码
2. **时间模拟**: 使用模拟时间而非固定时间戳
3. **更多边界**: 添加极长模型名称、极多 agents.md 等边界测试
4. **性能测试**: 添加大令牌数的性能基准

### 维护建议

1. **快照审查**: 定期审查快照文件，确保 UI 变更是预期的
2. **测试命名**: 保持测试函数名描述性，便于快速定位问题
3. **文档注释**: 为复杂测试添加注释说明测试目的

### 代码质量

- 使用 `pretty_assertions::assert_eq` 提供清晰的差异输出
- 使用 `#[tokio::test]` 支持异步配置构建
- 建议提取更多通用辅助函数减少重复
