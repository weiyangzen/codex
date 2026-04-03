# helpers.rs 研究文档

## 场景与职责

`helpers.rs` 是 Codex TUI 状态显示模块的辅助函数集合，提供模型显示、AGENTS.md 摘要、账户显示、Token 格式化、目录显示、时间戳格式化等通用功能。这些辅助函数被 `card.rs` 和 `rate_limits.rs` 调用，将原始数据转换为人类可读的显示字符串。

## 功能点目的

### 核心功能

1. **模型显示组合** (`compose_model_display`): 将模型名称与推理配置组合为显示字符串
2. **AGENTS.md 摘要** (`compose_agents_summary`): 发现并格式化项目文档路径
3. **账户显示组合** (`compose_account_display`): 将认证信息转换为显示格式
4. **Token 紧凑格式化** (`format_tokens_compact`): 将大数字格式化为 K/M/B/T 后缀形式
5. **目录显示格式化** (`format_directory_display`): 将路径格式化为 ~ 开头的家目录相对路径
6. **重置时间戳格式化** (`format_reset_timestamp`): 格式化速率限制重置时间
7. **首字母大写** (`title_case`): 简单的标题大小写转换

## 具体技术实现

### 1. 模型显示组合

```rust
pub(crate) fn compose_model_display(
    model_name: &str,
    entries: &[(&str, String)],
) -> (String, Vec<String>) {
    let mut details: Vec<String> = Vec::new();
    
    // 提取推理努力度
    if let Some((_, effort)) = entries.iter().find(|(k, _)| *k == "reasoning effort") {
        details.push(format!("reasoning {}", effort.to_ascii_lowercase()));
    }
    
    // 提取推理摘要配置
    if let Some((_, summary)) = entries.iter().find(|(k, _)| *k == "reasoning summaries") {
        let summary = summary.trim();
        if summary.eq_ignore_ascii_case("none") || summary.eq_ignore_ascii_case("off") {
            details.push("summaries off".to_string());
        } else if !summary.is_empty() {
            details.push(format!("summaries {}", summary.to_ascii_lowercase()));
        }
    }

    (model_name.to_string(), details)
}
```

**使用示例**: `gpt-5.1-codex-max` + `reasoning high` → `gpt-5.1-codex-max (reasoning high, summaries detailed)`

### 2. AGENTS.md 摘要

```rust
pub(crate) fn compose_agents_summary(config: &Config) -> String {
    match discover_project_doc_paths(config) {
        Ok(paths) => {
            let mut rels: Vec<String> = Vec::new();
            for p in paths {
                let file_name = p.file_name()
                    .map(|name| name.to_string_lossy().to_string())
                    .unwrap_or_else(|| "<unknown>".to_string());
                
                let display = if let Some(parent) = p.parent() {
                    if parent == config.cwd {
                        // 文件在当前目录
                        file_name.clone()
                    } else {
                        // 计算相对路径（向上遍历）
                        let mut cur = config.cwd.as_path();
                        let mut ups = 0usize;
                        let mut reached = false;
                        while let Some(c) = cur.parent() {
                            if cur == parent {
                                reached = true;
                                break;
                            }
                            cur = c;
                            ups += 1;
                        }
                        if reached {
                            let up = format!("..{}", std::path::MAIN_SEPARATOR);
                            format!("{}{}", up.repeat(ups), file_name)
                        } else if let Ok(stripped) = p.strip_prefix(&config.cwd) {
                            normalize_agents_display_path(stripped)
                        } else {
                            normalize_agents_display_path(&p)
                        }
                    }
                } else {
                    normalize_agents_display_path(&p)
                };
                rels.push(display);
            }
            if rels.is_empty() { "<none>".to_string() } else { rels.join(", ") }
        }
        Err(_) => "<none>".to_string(),
    }
}
```

**路径简化逻辑**:
1. 当前目录下的文件: 只显示文件名
2. 父目录中的文件: 使用 `..` 向上导航（如 `../AGENTS.md`）
3. 其他情况: 使用 `strip_prefix` 或完整路径

**依赖函数**:
```rust
fn normalize_agents_display_path(path: &Path) -> String {
    dunce::simplified(path).display().to_string()
}
```

### 3. 账户显示组合

```rust
pub(crate) fn compose_account_display(
    auth_manager: &AuthManager,
    plan: Option<PlanType>,
) -> Option<StatusAccountDisplay> {
    let auth = auth_manager.auth_cached()?;

    match auth.auth_mode() {
        CoreAuthMode::ApiKey => Some(StatusAccountDisplay::ApiKey),
        CoreAuthMode::Chatgpt => {
            let email = auth.get_account_email();
            let plan = plan
                .map(|plan_type| title_case(format!("{plan_type:?}").as_str()))
                .or_else(|| Some("Unknown".to_string()));
            Some(StatusAccountDisplay::ChatGpt { email, plan })
        }
    }
}
```

**计划类型转换**: `PlanType::Plus` → `"Plus"`（通过 Debug 格式化 + title_case）

### 4. Token 紧凑格式化

```rust
pub(crate) fn format_tokens_compact(value: i64) -> String {
    let value = value.max(0);
    if value == 0 { return "0".to_string(); }
    if value < 1_000 { return value.to_string(); }

    let value_f64 = value as f64;
    let (scaled, suffix) = if value >= 1_000_000_000_000 {
        (value_f64 / 1_000_000_000_000.0, "T")
    } else if value >= 1_000_000_000 {
        (value_f64 / 1_000_000_000.0, "B")
    } else if value >= 1_000_000 {
        (value_f64 / 1_000_000.0, "M")
    } else {
        (value_f64 / 1_000.0, "K")
    };

    // 动态小数位: <10 保留 2 位, <100 保留 1 位, 否则 0 位
    let decimals = if scaled < 10.0 { 2 } else if scaled < 100.0 { 1 } else { 0 };

    let mut formatted = format!("{scaled:.decimals$}");
    
    // 去除末尾的零和小数点
    if formatted.contains('.') {
        while formatted.ends_with('0') { formatted.pop(); }
        if formatted.ends_with('.') { formatted.pop(); }
    }

    format!("{formatted}{suffix}")
}
```

**格式化规则**:
| 范围 | 示例输出 |
|------|----------|
| 0 | `0` |
| 1-999 | `999` |
| 1,000-999,999 | `1K`, `12.5K`, `999K` |
| 1M-999M | `1M`, `12.5M`, `999M` |
| 1B-999B | `1B`, `12.5B` |
| 1T+ | `1T`, `1.23T` |

### 5. 目录显示格式化

```rust
pub(crate) fn format_directory_display(directory: &Path, max_width: Option<usize>) -> String {
    // 转换为家目录相对路径
    let formatted = if let Some(rel) = relativize_to_home(directory) {
        if rel.as_os_str().is_empty() {
            "~".to_string()
        } else {
            format!("~{}{}", std::path::MAIN_SEPARATOR, rel.display())
        }
    } else {
        directory.display().to_string()
    };

    // 可选截断
    if let Some(max_width) = max_width {
        if max_width == 0 { return String::new(); }
        if UnicodeWidthStr::width(formatted.as_str()) > max_width {
            return text_formatting::center_truncate_path(&formatted, max_width);
        }
    }

    formatted
}
```

**依赖函数**:
```rust
// exec_command::relativize_to_home
pub fn relativize_to_home(path: &Path) -> Option<PathBuf> {
    let home = dirs::home_dir()?;
    path.strip_prefix(home).ok().map(PathBuf::from)
}
```

### 6. 重置时间戳格式化

```rust
pub(crate) fn format_reset_timestamp(dt: DateTime<Local>, captured_at: DateTime<Local>) -> String {
    let time = dt.format("%H:%M").to_string();
    if dt.date_naive() == captured_at.date_naive() {
        time  // 同一天只显示时间
    } else {
        format!("{time} on {}", dt.format("%-d %b"))  // 不同天显示日期
    }
}
```

**输出示例**:
- 同一天: `14:30`
- 不同天: `14:30 on 15 Jan`

### 7. 首字母大写

```rust
pub(crate) fn title_case(s: &str) -> String {
    if s.is_empty() { return String::new(); }
    let mut chars = s.chars();
    let first = match chars.next() {
        Some(c) => c,
        None => return String::new(),
    };
    let rest: String = chars.as_str().to_ascii_lowercase();
    first.to_uppercase().collect::<String>() + &rest
}
```

**使用场景**: 将 `PlanType` 的 Debug 输出（如 `PLUS`）转换为 `"Plus"`

## 关键代码路径与文件引用

### 上游依赖（输入）

| 模块/类型 | 来源 | 用途 |
|-----------|------|------|
| `Config` | `codex_core::config::Config` | AGENTS.md 搜索配置 |
| `AuthManager` | `codex_core::AuthManager` | 账户信息 |
| `PlanType` | `codex_protocol::account::PlanType` | 订阅计划 |
| `discover_project_doc_paths` | `codex_core::project_doc` | 发现 AGENTS.md |
| `relativize_to_home` | `crate::exec_command` | 家目录相对化 |
| `center_truncate_path` | `crate::text_formatting` | 路径截断 |

### 下游调用方

| 模块 | 路径 | 用途 |
|------|------|------|
| `card.rs` | `./card.rs` | 调用所有辅助函数 |
| `rate_limits.rs` | `./rate_limits.rs` | 调用 `format_reset_timestamp` |

### 调用关系图

```
card.rs
├── compose_model_display
├── compose_agents_summary
│   └── discover_project_doc_paths (core)
├── compose_account_display
├── format_tokens_compact
└── format_directory_display
    └── relativize_to_home
        └── dirs::home_dir

rate_limits.rs
└── format_reset_timestamp
```

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `chrono` | `DateTime`, `Local` 时间处理 |
| `dunce` | `simplified` 路径简化（Windows 兼容） |
| `unicode_width` | `UnicodeWidthStr` 宽度计算 |
| `codex_core` | `AuthManager`, `Config`, `project_doc` |
| `codex_protocol` | `PlanType` |

### 内部模块依赖

```rust
use crate::exec_command::relativize_to_home;
use crate::text_formatting;
use super::account::StatusAccountDisplay;
```

## 风险、边界与改进建议

### 边界情况

1. **Token 格式化**:
   - 负数输入被钳位到 0
   - 极大值（> 1T）正确处理

2. **AGENTS.md 路径**:
   - 当文件在项目根目录外时，显示完整路径
   - 符号链接被 `dunce::simplified` 处理

3. **目录格式化**:
   - `max_width = 0` 返回空字符串
   - 家目录检测失败时回退到完整路径

4. **时间戳格式化**:
   - 依赖系统时区设置
   - 跨年时日期显示正确

### 潜在风险

1. **性能问题**:
   - `compose_agents_summary` 遍历文件系统，可能在大型项目中较慢
   - `format_tokens_compact` 使用浮点运算，精度可能有微小误差

2. **国际化**:
   - `title_case` 仅处理 ASCII
   - 日期格式硬编码为英文（`"on"`, 月份缩写）

3. **路径安全**:
   - `relativize_to_home` 依赖 `dirs::home_dir()`，在某些环境可能返回 None

4. **错误处理**:
   - `compose_agents_summary` 在出错时返回 `"<none>"`，可能掩盖实际问题

### 改进建议

1. **性能优化**:
   - 缓存 `discover_project_doc_paths` 结果
   - 使用整数运算替代浮点运算格式化 Token

2. **功能增强**:
   - 支持国际化日期格式
   - 添加配置控制 AGENTS.md 显示格式

3. **错误处理**:
   - 区分 "无 AGENTS.md" 和 "读取错误"
   - 添加日志记录文件系统错误

4. **代码简化**:
   - `compose_agents_summary` 的路径计算逻辑较复杂，可提取为独立函数
   - `format_tokens_compact` 的阈值判断可使用 match 表达式

### 代码度量

- 代码行数: 189 行
- 公共函数: 7 个
- 私有辅助函数: 1 个 (`normalize_agents_display_path`)
- 复杂度: 中等（主要是路径计算逻辑）

### 测试覆盖

当前无直接单元测试，依赖 `tests.rs` 的集成测试。建议添加：

1. `format_tokens_compact` 的边界值测试
2. `title_case` 的各种输入测试
3. `format_reset_timestamp` 的跨天/跨年测试
