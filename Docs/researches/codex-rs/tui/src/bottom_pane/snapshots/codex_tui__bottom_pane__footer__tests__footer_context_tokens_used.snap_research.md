# 快照研究文档: footer_context_tokens_used

## 基本信息
- **快照文件**: `codex_tui__bottom_pane__footer__tests__footer_context_tokens_used.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/footer.rs`
- **测试函数**: `footer_snapshots`
- **表达式**: `terminal.backend()`

---

## 场景与职责

### 功能场景
此快照捕获了**底部栏显示已使用Token数量**的状态。当系统配置为显示已使用的token数而非剩余百分比时，底部栏右侧显示格式化后的token使用量。

### 业务职责
1. **资源使用透明**: 向用户展示当前会话的token消耗
2. **成本控制**: 帮助用户了解API使用量
3. **格式化显示**: 将大数字格式化为易读的形式（如123K）

### 显示优先级
1. 优先显示 `context_window_percent`（百分比）
2. 如果百分比未设置，显示 `context_window_used_tokens`（已使用token）
3. 如果都未设置，默认显示 "100% context left"

---

## 功能点目的

### 核心功能
| 功能点 | 目的 | 实现方式 |
|--------|------|----------|
| Token格式化 | 将大数字转为易读格式 | `format_tokens_compact()` |
| 快捷提示 | 显示快捷键帮助 | "? for shortcuts" |
| 右侧对齐 | 信息右对齐显示 | `render_context_right()` |

### UI内容
```
"  ? for shortcuts                                                    123K used  "
  └─ 2空格缩进  └─ 快捷提示 ─────────────────────────────────────────  └─ Token使用
```

### Token格式化示例
| 原始值 | 格式化后 |
|--------|----------|
| 123,456 | "123K" |
| 1,234,567 | "1.2M" |
| 999 | "999" |

---

## 具体技术实现

### context_window_line函数
```rust
pub(crate) fn context_window_line(percent: Option<i64>, used_tokens: Option<i64>) -> Line<'static> {
    if let Some(percent) = percent {
        let percent = percent.clamp(0, 100);
        return Line::from(vec![Span::from(format!("{percent}% context left")).dim()]);
    }

    if let Some(tokens) = used_tokens {
        let used_fmt = format_tokens_compact(tokens);
        return Line::from(vec![Span::from(format!("{used_fmt} used")).dim()]);
    }

    Line::from(vec![Span::from("100% context left").dim()])
}
```

### Token格式化函数
```rust
// 来自 crate::status
pub fn format_tokens_compact(tokens: i64) -> String {
    const K: i64 = 1_000;
    const M: i64 = 1_000_000;
    
    if tokens >= M {
        format!("{:.1}M", tokens as f64 / M as f64)
    } else if tokens >= K {
        format!("{}K", tokens / K)
    } else {
        tokens.to_string()
    }
}
```

### 测试配置
```rust
snapshot_footer(
    "footer_context_tokens_used",
    FooterProps {
        mode: FooterMode::ComposerEmpty,
        esc_backtrack_hint: false,
        use_shift_enter_hint: false,
        is_task_running: false,
        collaboration_modes_enabled: false,
        is_wsl: false,
        quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
        context_window_percent: None,  // <-- 不设置百分比
        context_window_used_tokens: Some(123_456),  // <-- 设置已使用token
        status_line_value: None,
        status_line_enabled: false,
        active_agent_label: None,
    },
);
```

---

## 关键代码路径与文件引用

### 主要代码位置
| 文件 | 行号范围 | 功能 |
|------|----------|------|
| `footer.rs` | 848-860 | `context_window_line()` 函数 |
| `footer.rs` | 529-554 | `render_context_right()` 右对齐渲染 |
| `status.rs` | （假设） | `format_tokens_compact()` token格式化 |

### 优先级逻辑
```rust
// context_window_line 中的优先级
1. context_window_percent (最高优先级)
2. context_window_used_tokens
3. 默认值 "100% context left" (最低优先级)
```

### 测试代码位置
- **测试代码**: `footer.rs` 第 1405-1421 行

---

## 依赖与外部交互

### 依赖模块
| 模块 | 用途 |
|------|------|
| `crate::status::format_tokens_compact` | Token数量格式化 |
| `ratatui::text::Span` | 文本span创建 |
| `ratatui::style::Stylize` | 样式应用（dim） |

### 数据来源
```
模型API响应
    ↓
提取token使用信息
    ↓
更新 FooterProps.context_window_used_tokens
    ↓
渲染时格式化为 "123K used"
```

---

## 风险边界与改进建议

### 潜在风险

#### 1. 精度丢失
- **问题**: 大数字格式化后精度丢失（如1,234,567显示为"1.2M"）
- **影响**: 用户无法看到精确的使用量
- **建议**: 考虑悬停显示精确值

#### 2. 单位混淆
- **问题**: "K"和"M"可能让部分用户困惑
- **建议**: 添加工具提示或说明

#### 3. 与百分比的切换
- **问题**: 用户可能不清楚为什么有时显示百分比，有时显示token数
- **建议**: 统一显示方式或添加配置选项

### 改进建议

#### 1. 悬停显示精确值
```rust
// 建议: 添加悬停提示
Span::from(format!("{used_fmt} used"))
    .dim()
    .on_hover(format!("Exact: {} tokens", tokens))
```

#### 2. 添加成本估算
```rust
// 建议: 显示估算成本
let cost = tokens as f64 * 0.00001;  // 假设费率
Line::from(vec![
    Span::from(format!("{used_fmt} used")).dim(),
    Span::from(format!(" (~${:.2})", cost)).dim(),
])
```

#### 3. 使用进度条
```rust
// 建议: 添加视觉进度条
let bar = create_progress_bar(tokens, max_tokens);
Line::from(vec![bar, Span::from(format!(" {used_fmt}")).dim()])
```

### 测试覆盖分析
- ✅ Token格式化显示测试
- ✅ 百分比显示测试（`footer_shortcuts_context_running`）
- ⚠️ 建议添加: 边界值测试（0, 999, 1000, 999999, 1000000）
- ⚠️ 建议添加: 大数字格式化精度测试
