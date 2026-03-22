# codex-rs/utils/string 深度研究文档

## 1. 场景与职责

### 1.1 模块定位

`codex-rs/utils/string` 是 Codex 项目中的一个基础工具 crate，提供字符串处理的通用功能。该 crate 被设计为**无状态、纯函数式**的工具库，专注于解决以下核心场景：

1. **UTF-8 安全截断**：处理多字节字符边界处的字符串截断，避免截断在字符中间导致无效 UTF-8
2. **指标标签清理**：为 OpenTelemetry 指标系统清理和规范化标签值，确保符合后端存储的约束
3. **UUID 提取**：从文本中提取标准 UUID 格式
4. **Markdown 位置后缀规范化**：将 Markdown 风格的 `#L..` 位置标记转换为终端友好的 `:line[:col]` 格式

### 1.2 使用场景分布

| 使用方 | 使用功能 | 场景描述 |
|--------|----------|----------|
| `codex-rs/core` | `take_bytes_at_char_boundary` | 文件读取工具中截断超长行（MAX_LINE_LENGTH=500） |
| `codex-rs/otel` | `sanitize_metric_tag_value` | OpenTelemetry 指标标签值清理 |
| `codex-rs/tui` | `normalize_markdown_hash_location_suffix` | Markdown 渲染中处理文件链接位置后缀 |
| `codex-rs/tui_app_server` | `normalize_markdown_hash_location_suffix` | 同上，TUI 应用服务器端渲染 |
| `codex-rs/windows-sandbox-rs` | `take_bytes_at_char_boundary`, `sanitize_metric_tag_value` | 日志命令预览截断、指标标签清理 |

### 1.3 架构设计原则

- **零依赖（除 regex-lite）**：保持轻量，仅依赖 `regex-lite` 用于 UUID 正则匹配
- **无分配优先**：`take_bytes_at_char_boundary` 返回 `&str` 切片而非新分配字符串
- **线程安全**：`find_uuids` 使用 `std::sync::OnceLock` 实现正则表达式懒加载
- **防御性编程**：所有公共函数都处理边界情况（空字符串、超长输入等）

---

## 2. 功能点目的

### 2.1 `take_bytes_at_char_boundary` - 前缀安全截断

**目的**：在指定字节预算内截取字符串前缀，确保截断位置位于有效的 UTF-8 字符边界。

**解决的问题**：
- 直接字节截断可能切在多字节 UTF-8 字符中间，导致无效字符串
- 需要精确控制输出长度的场景（如终端显示、日志截断）

**关键约束**：
- 输入：`&str`（已保证有效 UTF-8）
- 输出：`&str`（原字符串的切片，零拷贝）
- 时间复杂度：O(n)，n 为字符数（使用 `char_indices()` 迭代）

### 2.2 `take_last_bytes_at_char_boundary` - 后缀安全截断

**目的**：从字符串末尾截取指定字节预算内的后缀，同样保证字符边界安全。

**使用场景**：
- 显示文件路径时保留末尾文件名部分
- 日志中显示命令行的尾部

**实现特点**：
- 使用 `char_indices().rev()` 反向迭代
- 记录起始位置和已用字节数

### 2.3 `sanitize_metric_tag_value` - 指标标签值清理

**目的**：将任意字符串转换为符合指标系统（如 Statsig、Datadog）标签约束的格式。

**清理规则**：
1. 字符白名单：ASCII 字母数字、`.`、`_`、`-`、`/`
2. 非法字符替换为 `_`
3. 首尾 `_` 去除
4. 空结果或纯符号结果替换为 `"unspecified"`
5. 最大长度限制：256 字符

**业务价值**：
- 防止特殊字符导致指标后端拒绝或注入攻击
- 统一标签格式，便于查询和聚合

### 2.4 `find_uuids` - UUID 提取

**目的**：从任意文本中提取所有标准 UUID（GUID）。

**匹配模式**：
```regex
[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}
```

**性能优化**：
- 使用 `OnceLock` 实现正则表达式单例懒加载
- 避免每次调用重新编译正则

### 2.5 `normalize_markdown_hash_location_suffix` - 位置后缀规范化

**目的**：将 Markdown/GitHub 风格的行号标记（如 `#L74C3`）转换为终端友好的格式（`:74:3`）。

**输入格式支持**：
- 单行：`#L74` → `:74`
- 单行带列：`#L74C3` → `:74:3`
- 范围：`#L74-L76` → `:74-76`
- 范围带列：`#L74C3-L76C9` → `:74:3-76:9`

**使用场景**：
- TUI 中渲染文件链接时显示简洁的行号信息
- 将 GitHub 永久链接格式转换为编辑器可识别的格式

---

## 3. 具体技术实现

### 3.1 关键数据结构

本 crate 无复杂数据结构，全部为纯函数。核心算法依赖以下 Rust 标准库类型：

```rust
// 字符迭代器
std::str::CharIndices    // 提供 (byte_index, char) 迭代
std::iter::Rev           // 反向迭代适配器

// 正则表达式（regex-lite crate）
regex_lite::Regex        // 轻量级正则实现
std::sync::OnceLock      // 线程安全懒加载容器
```

### 3.2 关键流程详解

#### 3.2.1 UTF-8 安全截断算法

```rust
pub fn take_bytes_at_char_boundary(s: &str, maxb: usize) -> &str {
    if s.len() <= maxb {
        return s;  // 快速路径：无需截断
    }
    let mut last_ok = 0;
    for (i, ch) in s.char_indices() {
        let nb = i + ch.len_utf8();  // 当前字符结束位置
        if nb > maxb {
            break;  // 超出预算，停止
        }
        last_ok = nb;  // 记录最后一个合法位置
    }
    &s[..last_ok]  // 返回切片
}
```

**算法复杂度**：
- 时间：O(k)，k 为截断前需要遍历的字符数
- 空间：O(1)，仅使用栈变量

**边界处理**：
- `maxb = 0`：返回空字符串（首个字符即超出预算）
- 多字节字符（如 emoji，4 字节）：确保完整包含或不包含

#### 3.2.2 指标标签清理流程

```rust
pub fn sanitize_metric_tag_value(value: &str) -> String {
    const MAX_LEN: usize = 256;
    
    // 1. 字符级转换
    let sanitized: String = value
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || matches!(ch, '.' | '_' | '-' | '/') {
                ch
            } else {
                '_'
            }
        })
        .collect();
    
    // 2. 去除首尾下划线
    let trimmed = sanitized.trim_matches('_');
    
    // 3. 空值或纯符号处理
    if trimmed.is_empty() || trimmed.chars().all(|ch| !ch.is_ascii_alphanumeric()) {
        return "unspecified".to_string();
    }
    
    // 4. 长度截断
    if trimmed.len() <= MAX_LEN {
        trimmed.to_string()
    } else {
        trimmed[..MAX_LEN].to_string()
    }
}
```

#### 3.2.3 Markdown 位置后缀解析

```rust
pub fn normalize_markdown_hash_location_suffix(suffix: &str) -> Option<String> {
    let fragment = suffix.strip_prefix('#')?;  // 去除 # 前缀
    
    // 解析范围（支持 L74-L76 格式）
    let (start, end) = match fragment.split_once('-') {
        Some((start, end)) => (start, Some(end)),
        None => (fragment, None),
    };
    
    // 解析起点（L74 或 L74C3）
    let (start_line, start_column) = parse_markdown_hash_location_point(start)?;
    
    // 构建输出
    let mut normalized = String::from(":");
    normalized.push_str(start_line);
    if let Some(column) = start_column {
        normalized.push(':');
        normalized.push_str(column);
    }
    
    // 处理范围终点
    if let Some(end) = end {
        let (end_line, end_column) = parse_markdown_hash_location_point(end)?;
        normalized.push('-');
        normalized.push_str(end_line);
        if let Some(column) = end_column {
            normalized.push(':');
            normalized.push_str(column);
        }
    }
    
    Some(normalized)
}
```

### 3.3 测试覆盖

测试文件位于 `src/lib.rs` 的 `#[cfg(test)]` 模块中，包含以下测试用例：

| 测试函数 | 测试内容 |
|----------|----------|
| `find_uuids_finds_multiple` | 验证多个 UUID 的提取 |
| `find_uuids_ignores_invalid` | 验证无效 UUID 被忽略 |
| `find_uuids_handles_non_ascii_without_overlap` | 验证非 ASCII 字符不干扰 UUID 匹配 |
| `sanitize_metric_tag_value_trims_and_fills_unspecified` | 验证纯符号输入返回 "unspecified" |
| `sanitize_metric_tag_value_replaces_invalid_chars` | 验证非法字符替换为下划线 |
| `normalize_markdown_hash_location_suffix_converts_single_location` | 验证单行位置转换 |
| `normalize_markdown_hash_location_suffix_converts_ranges` | 验证范围位置转换 |

---

## 4. 关键代码路径与文件引用

### 4.1 源文件结构

```
codex-rs/utils/string/
├── Cargo.toml          # 包配置
├── BUILD.bazel         # Bazel 构建配置
└── src/
    └── lib.rs          # 全部实现（176 行）
```

### 4.2 公共 API 列表

| 函数签名 | 行号 | 可见性 |
|----------|------|--------|
| `take_bytes_at_char_boundary(s: &str, maxb: usize) -> &str` | 3-16 | `pub` |
| `take_last_bytes_at_char_boundary(s: &str, maxb: usize) -> &str` | 19-38 | `pub` |
| `sanitize_metric_tag_value(value: &str) -> String` | 42-63 | `pub` |
| `find_uuids(s: &str) -> Vec<String>` | 66-77 | `pub` |
| `normalize_markdown_hash_location_suffix(suffix: &str) -> Option<String>` | 79-104 | `pub` |

### 4.3 调用方代码路径

#### 4.3.1 `codex-rs/core/src/tools/handlers/read_file.rs`
```rust
use codex_utils_string::take_bytes_at_char_boundary;

fn format_line(bytes: &[u8]) -> String {
    let decoded = String::from_utf8_lossy(bytes);
    if decoded.len() > MAX_LINE_LENGTH {  // 500
        take_bytes_at_char_boundary(&decoded, MAX_LINE_LENGTH).to_string()
    } else {
        decoded.into_owned()
    }
}
```

#### 4.3.2 `codex-rs/core/src/tools/handlers/list_dir.rs`
```rust
use codex_utils_string::take_bytes_at_char_boundary;

fn format_entry_name(path: &Path) -> String {
    let normalized = path.to_string_lossy().replace("\\", "/");
    if normalized.len() > MAX_ENTRY_LENGTH {  // 500
        take_bytes_at_char_boundary(&normalized, MAX_ENTRY_LENGTH).to_string()
    } else {
        normalized
    }
}
```

#### 4.3.3 `codex-rs/core/src/tools/context.rs`
```rust
use codex_utils_string::take_bytes_at_char_boundary;

fn telemetry_preview(content: &str) -> String {
    let truncated_slice = take_bytes_at_char_boundary(content, TELEMETRY_PREVIEW_MAX_BYTES);
    // ... 后续处理
}
```

#### 4.3.4 `codex-rs/otel/src/metrics/client.rs`
```rust
use codex_utils_string::sanitize_metric_tag_value;

fn os_resource_attributes() -> Vec<KeyValue> {
    let os_type_raw = os_info::get().os_type().to_string();
    let os_type = sanitize_metric_tag_value(os_type_raw.as_str());
    // ...
}
```

#### 4.3.5 `codex-rs/tui/src/markdown_render.rs`
```rust
use codex_utils_string::normalize_markdown_hash_location_suffix;

fn normalize_hash_location_suffix_fragment(fragment: &str) -> Option<String> {
    HASH_LOCATION_SUFFIX_RE
        .is_match(fragment)
        .then(|| format!("#{fragment}"))
        .and_then(|suffix| normalize_markdown_hash_location_suffix(&suffix))
}
```

---

## 5. 依赖与外部交互

### 5.1 依赖关系

```toml
[dependencies]
regex-lite = { workspace = true }  # 轻量级正则表达式库

[dev-dependencies]
pretty_assertions = { workspace = true }  # 测试断言美化
```

### 5.2 反向依赖

以下 crate 依赖 `codex-utils-string`：

| 依赖方 | Cargo.toml 路径 | 使用功能 |
|--------|-----------------|----------|
| `codex-core` | `codex-rs/core/Cargo.toml` | `take_bytes_at_char_boundary` |
| `codex-otel` | `codex-rs/otel/Cargo.toml` | `sanitize_metric_tag_value` |
| `codex-tui` | `codex-rs/tui/Cargo.toml` | `normalize_markdown_hash_location_suffix` |
| `codex-tui-app-server` | `codex-rs/tui_app_server/Cargo.toml` | `normalize_markdown_hash_location_suffix` |
| `codex-windows-sandbox` | `codex-rs/windows-sandbox-rs/Cargo.toml` | `take_bytes_at_char_boundary`, `sanitize_metric_tag_value` |

### 5.3 与 Workspace 的集成

在 workspace `Cargo.toml` 中定义：
```toml
[workspace.dependencies]
codex-utils-string = { path = "utils/string" }
```

### 5.4 Bazel 构建

`BUILD.bazel` 使用宏 `codex_rust_crate` 定义：
```starlark
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "string",
    crate_name = "codex_utils_string",
)
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 正则表达式依赖风险
- **风险**：`find_uuids` 依赖 `regex-lite`，虽然该库轻量，但仍引入外部依赖
- **缓解**：使用 `OnceLock` 确保正则只编译一次，降低运行时开销
- **建议**：考虑在性能敏感场景使用手动解析替代正则

#### 6.1.2 指标标签长度硬编码
- **风险**：`MAX_LEN = 256` 是硬编码常量，不同指标后端可能有不同限制
- **建议**：考虑通过参数暴露该限制，或提供配置接口

#### 6.1.3 `normalize_markdown_hash_location_suffix` 的 `Option` 返回
- **风险**：调用方需处理 `None` 情况，但文档未明确说明何时返回 `None`
- **当前行为**：输入不以 `#` 开头、或解析失败时返回 `None`
- **建议**：完善文档，明确错误条件

### 6.2 边界情况

| 场景 | 当前行为 | 是否预期 |
|------|----------|----------|
| `take_bytes_at_char_boundary("", 0)` | 返回 `""` | 是 |
| `take_bytes_at_char_boundary("hello", 0)` | 返回 `""` | 是 |
| `take_bytes_at_char_boundary("😀", 2)` | 返回 `""`（emoji 4 字节） | 是 |
| `sanitize_metric_tag_value("___")` | 返回 `"unspecified"` | 是 |
| `sanitize_metric_tag_value("a" * 300)` | 截断至 256 字符 | 是 |
| `normalize_markdown_hash_location_suffix("invalid")` | 返回 `None` | 是 |

### 6.3 改进建议

#### 6.3.1 性能优化
```rust
// 当前：每次都遍历所有字符
// 建议：对于 ASCII 字符串使用快速路径
pub fn take_bytes_at_char_boundary(s: &str, maxb: usize) -> &str {
    if s.len() <= maxb {
        return s;
    }
    // 快速路径：如果全是 ASCII，直接截断
    if s.is_ascii() {
        return &s[..maxb];
    }
    // 原有实现...
}
```

#### 6.3.2 API 扩展
- 添加 `take_bytes_at_char_boundary_ellipsis` 版本，在截断时添加 `...` 后缀
- 添加 `sanitize_metric_tag_value_with_custom_replacement` 允许自定义替换字符

#### 6.3.3 文档改进
- 为 `normalize_markdown_hash_location_suffix` 添加更多输入/输出示例
- 添加模块级文档说明各函数的适用场景

#### 6.3.4 测试增强
- 添加模糊测试（fuzzing）验证 UTF-8 边界处理
- 添加性能基准测试（criterion）监控回归

### 6.4 维护建议

1. **版本策略**：该 crate 作为基础工具，应保持稳定的 API，谨慎进行破坏性变更
2. **依赖管理**：`regex-lite` 已足够轻量，但如仅需 UUID 匹配，可考虑手动实现以移除依赖
3. **代码组织**：当前所有代码在单文件 `lib.rs` 中，规模可控（176 行），无需拆分

---

## 附录：代码统计

```
Language: Rust
Files: 1
Lines: 176
Blank: ~20
Comments: ~15
Code: ~141
```

## 附录：变更历史（通过 git log 推断）

该 crate 为稳定的基础工具模块，近期变更主要围绕：
1. 添加 `normalize_markdown_hash_location_suffix` 支持 TUI 的 Markdown 渲染
2. 从 `regex` 切换到 `regex-lite` 减少依赖体积
3. 添加 `sanitize_metric_tag_value` 支持指标系统
