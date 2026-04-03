# helpers.rs 研究文档

## 场景与职责

`helpers.rs` 是状态显示模块的工具函数集合，提供模型信息格式化、项目文档摘要、账户显示、令牌格式化和目录格式化等辅助功能。这些函数将原始数据转换为人类可读的字符串表示。

### 核心职责
1. **模型显示**: 组合模型名称与推理配置详情
2. **项目文档发现**: 扫描并格式化 AGENTS.md 文件路径
3. **账户显示**: 包装账户显示枚举
4. **令牌格式化**: 将大数字转换为紧凑表示（K/M/B/T）
5. **目录格式化**: 将绝对路径转换为相对 home 的简洁形式

## 功能点目的

### 1. compose_model_display - 模型信息组合

将模型名称与配置条目结合，生成主名称和详情列表：

```rust
pub(crate) fn compose_model_display(
    model_name: &str,
    entries: &[(&str, String)],
) -> (String, Vec<String>)
```

提取以下配置项：
- `reasoning effort` → "reasoning {effort}"
- `reasoning summaries` → "summaries {summary}" 或 "summaries off"

### 2. compose_agents_summary - 项目文档摘要

扫描项目中的 AGENTS.md 文件并生成相对路径摘要：

```rust
pub(crate) fn compose_agents_summary(config: &Config) -> String
```

### 3. compose_account_display - 账户显示包装

```rust
pub(crate) fn compose_account_display(
    account_display: Option<&StatusAccountDisplay>,
) -> Option<StatusAccountDisplay>
```

简单的 `Option::cloned` 包装。

### 4. format_tokens_compact - 紧凑令牌数

```rust
pub(crate) fn format_tokens_compact(value: i64) -> String
```

转换规则：
- `< 1,000`: 原样显示（如 "999"）
- `< 1,000,000`: K 格式，保留 0-2 位小数（如 "1.23K"）
- `< 1,000,000,000`: M 格式
- `< 1,000,000,000,000`: B 格式
- `>= 1,000,000,000,000`: T 格式

### 5. format_directory_display - 目录显示

```rust
pub(crate) fn format_directory_display(directory: &Path, max_width: Option<usize>) -> String
```

- 优先转换为 `~/path` 形式
- 超长路径使用中心截断

### 6. format_reset_timestamp - 重置时间格式化

```rust
pub(crate) fn format_reset_timestamp(dt: DateTime<Local>, captured_at: DateTime<Local>) -> String
```

- 同一天：仅显示时间（如 "14:30"）
- 不同天：显示时间和日期（如 "14:30 on 5 Jul"）

## 具体技术实现

### compose_model_display 实现

```rust
pub(crate) fn compose_model_display(
    model_name: &str,
    entries: &[(&str, String)],
) -> (String, Vec<String>) {
    let mut details: Vec<String> = Vec::new();
    
    // 提取 reasoning effort
    if let Some((_, effort)) = entries.iter().find(|(k, _)| *k == "reasoning effort") {
        details.push(format!("reasoning {}", effort.to_ascii_lowercase()));
    }
    
    // 提取 reasoning summaries
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

### compose_agents_summary 实现

**路径发现** (行 35-81):
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
                        file_name.clone()  // 当前目录直接显示文件名
                    } else {
                        // 向上遍历计算相对路径
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
            if rels.is_empty() {
                "<none>".to_string()
            } else {
                rels.join(", ")
            }
        }
        Err(_) => "<none>".to_string(),
    }
}
```

**路径规范化**:
```rust
fn normalize_agents_display_path(path: &Path) -> String {
    dunce::simplified(path).display().to_string()
}
```

### format_tokens_compact 实现

```rust
pub(crate) fn format_tokens_compact(value: i64) -> String {
    let value = value.max(0);
    if value == 0 {
        return "0".to_string();
    }
    if value < 1_000 {
        return value.to_string();
    }

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

    // 根据数值大小决定小数位数
    let decimals = if scaled < 10.0 {
        2
    } else if scaled < 100.0 {
        1
    } else {
        0
    };

    // 格式化并去除末尾零
    let mut formatted = format!("{scaled:.decimals$}");
    if formatted.contains('.') {
        while formatted.ends_with('0') {
            formatted.pop();
        }
        if formatted.ends_with('.') {
            formatted.pop();
        }
    }

    format!("{formatted}{suffix}")
}
```

### format_directory_display 实现

```rust
pub(crate) fn format_directory_display(directory: &Path, max_width: Option<usize>) -> String {
    // 尝试转换为 ~/path 形式
    let formatted = if let Some(rel) = relativize_to_home(directory) {
        if rel.as_os_str().is_empty() {
            "~".to_string()
        } else {
            format!("~{}{}", std::path::MAIN_SEPARATOR, rel.display())
        }
    } else {
        directory.display().to_string()
    };

    // 超长路径截断
    if let Some(max_width) = max_width {
        if max_width == 0 {
            return String::new();
        }
        if UnicodeWidthStr::width(formatted.as_str()) > max_width {
            return text_formatting::center_truncate_path(&formatted, max_width);
        }
    }

    formatted
}
```

### format_reset_timestamp 实现

```rust
pub(crate) fn format_reset_timestamp(dt: DateTime<Local>, captured_at: DateTime<Local>) -> String {
    let time = dt.format("%H:%M").to_string();
    if dt.date_naive() == captured_at.date_naive() {
        time  // 同一天只显示时间
    } else {
        format!("{time} on {}", dt.format("%-d %b"))  // 显示时间和日期
    }
}
```

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/status/helpers.rs` - 160 行

### 调用方
| 文件 | 使用函数 |
|------|----------|
| `card.rs` | `compose_model_display`, `compose_agents_summary`, `compose_account_display`, `format_tokens_compact`, `format_directory_display` |
| `rate_limits.rs` | `format_reset_timestamp` |

### 依赖项
| 文件/Crate | 用途 |
|------------|------|
| `../exec_command.rs` | `relativize_to_home` - 路径相对化 |
| `account.rs` | `StatusAccountDisplay` - 账户显示类型 |
| `../text_formatting.rs` | `center_truncate_path` - 路径中心截断 |
| `codex_core::config::Config` | 配置访问 |
| `codex_core::project_doc::discover_project_doc_paths` | AGENTS.md 发现 |
| `dunce` | 路径规范化 |
| `unicode_width` | Unicode 宽度计算 |

## 依赖与外部交互

### 与 codex_core 的交互

**项目文档发现**:
```rust
use codex_core::project_doc::discover_project_doc_paths;
```

该函数在 `codex-rs/core/src/project_doc.rs` 中定义，负责：
1. 从当前目录向上查找项目根（通过 `.git` 等标记）
2. 从项目根到当前目录收集所有 `AGENTS.md` 文件
3. 返回按层次排序的路径列表

**配置访问**:
```rust
use codex_core::config::Config;
```

使用 `config.cwd` 作为路径计算的基准。

### 与 exec_command 的交互

```rust
use crate::exec_command::relativize_to_home;
```

将绝对路径转换为 `~/path` 形式，提升可读性。

## 风险、边界与改进建议

### 当前限制

1. **compose_agents_summary 复杂度**: 路径计算逻辑复杂，涉及多层条件判断
2. **硬编码单位**: `format_tokens_compact` 使用 K/M/B/T 单位，不符合部分地区的数字习惯
3. **日期格式**: `format_reset_timestamp` 使用英文格式（"5 Jul"），未本地化

### 边界情况

1. **空路径**: `compose_agents_summary` 返回 `"<none>"`
2. **负数令牌**: `format_tokens_compact` 强制 `max(0)`，负数显示为 "0"
3. **零宽度**: `format_directory_display` 在 `max_width = 0` 时返回空字符串

### 潜在改进

1. **简化路径计算**: `compose_agents_summary` 可使用 `pathdiff` crate 简化相对路径计算
2. **国际化**: 添加日期和数字格式的本地化支持
3. **配置单位**: 允许用户配置令牌数的显示单位偏好
4. **缓存**: `discover_project_doc_paths` 可能在短时间内被多次调用，可考虑缓存

### 测试建议

当前模块无独立测试，建议添加：
- `format_tokens_compact` 的边界测试（0, 999, 1000, 999999, 1000000 等）
- `format_directory_display` 的路径格式测试
- `format_reset_timestamp` 的跨天/同一天测试

### 代码质量

- 函数职责单一，符合单一职责原则
- 使用 `pub(crate)` 限制可见性，避免外部依赖
- 建议为 `compose_agents_summary` 添加文档注释说明路径计算逻辑
