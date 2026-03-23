# num_format.rs 研究文档

## 场景与职责

`num_format.rs` 是 Codex 协议库中的数字格式化工具模块，专门负责将数字（特别是 token 计数）格式化为人类可读的字符串形式。该模块在 TUI 和 CLI 输出中广泛使用，用于显示 token 使用量、上下文窗口统计等信息。

**核心职责：**
- 提供本地化感知的数字格式化（千位分隔符）
- 实现 SI 后缀格式化（K/M/G）用于大数字的简洁展示
- 支持 3 位有效数字的精度控制

## 功能点目的

### 1. 本地化数字格式化 (`format_with_separators`)

**目的：** 将整数格式化为带千位分隔符的字符串，根据用户系统 locale 自动选择合适的分隔符样式。

**示例：**
- `12345` → `"12,345"` (en-US)
- `12345` → `"12.345"` (de-DE)

**实现机制：**
- 使用 `icu_decimal` crate 进行国际化数字格式化
- 使用 `sys_locale` 检测系统 locale
- 回退到 `en-US` 如果 locale 检测失败

### 2. SI 后缀格式化 (`format_si_suffix`)

**目的：** 将大数字（特别是 token 计数）格式化为带 SI 后缀（K/M/G）的简洁形式，保留 3 位有效数字。

**示例：**
- `999` → `"999"`
- `1200` → `"1.20K"`
- `123456789` → `"123M"`
- `1234000000000` → `"1,234G"`

**精度规则：**
- 1000-9999: 保留 2 位小数 (如 `1.20K`)
- 10000-99999: 保留 1 位小数 (如 `10.0K`)
- 100000-999999: 保留 0 位小数 (如 `100K`)
- 超过 1000G: 保留整数 G (如 `1,234G`)

## 具体技术实现

### 关键数据结构

```rust
// 静态格式化器缓存
static FORMATTER: OnceLock<DecimalFormatter> = OnceLock::new();
```

使用 `OnceLock` 实现懒加载和线程安全的单例模式，避免重复创建格式化器。

### 核心函数流程

#### `formatter()` - 获取全局格式化器

```rust
fn formatter() -> &'static DecimalFormatter {
    static FORMATTER: OnceLock<DecimalFormatter> = OnceLock::new();
    FORMATTER.get_or_init(|| {
        make_local_formatter().unwrap_or_else(make_en_us_formatter)
    })
}
```

流程：
1. 尝试创建本地化格式化器
2. 如果失败（locale 解析失败或 ICU 数据问题），回退到 en-US

#### `format_si_suffix_with_formatter` - SI 后缀格式化核心

```rust
fn format_si_suffix_with_formatter(n: i64, formatter: &DecimalFormatter) -> String {
    let n = n.max(0);  // 确保非负
    
    if n < 1000 {
        return formatter.format(&Decimal::from(n)).to_string();
    }
    
    // 使用闭包格式化缩放后的值
    let format_scaled = |n: i64, scale: i64, frac_digits: u32| -> String {
        let value = n as f64 / scale as f64;
        let scaled: i64 = (value * 10f64.powi(frac_digits as i32)).round() as i64;
        let mut dec = Decimal::from(scaled);
        dec.multiply_pow10(-(frac_digits as i16));
        formatter.format(&dec).to_string()
    };
    
    // 逐级检查单位阈值
    const UNITS: [(i64, &str); 3] = [(1_000, "K"), (1_000_000, "M"), (1_000_000_000, "G")];
    // ... 精度选择逻辑
}
```

**精度选择算法：**
- 计算 `(100.0 * value / scale).round()`，如果结果 < 1000，使用 2 位小数
- 计算 `(10.0 * value / scale).round()`，如果结果 < 1000，使用 1 位小数
- 否则使用 0 位小数

### 依赖与外部交互

**外部依赖：**
- `icu_decimal`: ICU 数字格式化库
- `icu_locale_core`: ICU locale 处理
- `sys_locale`: 系统 locale 检测

**调用方：**
- `protocol.rs` 中的 `FinalOutput::fmt` - 用于显示 token 使用量统计
- `exec/src/event_processor_with_human_output.rs` - 事件处理器输出

## 关键代码路径与文件引用

### 本文件关键代码

| 行号 | 内容 | 说明 |
|------|------|------|
| 8-11 | `make_local_formatter` | 创建本地化格式化器 |
| 13-18 | `make_en_us_formatter` | 创建 en-US 回退格式化器 |
| 20-23 | `formatter` | 全局格式化器获取 |
| 27-29 | `format_with_separators` | 公共 API：千位分隔符格式化 |
| 35-67 | `format_si_suffix_with_formatter` | SI 后缀格式化核心实现 |
| 75-77 | `format_si_suffix` | 公共 API：SI 后缀格式化 |

### 调用路径

```
protocol.rs:1969-1992 (FinalOutput::fmt)
    └── format_with_separators(token_usage.blended_total())
    └── format_with_separators(token_usage.non_cached_input())
    └── format_with_separators(token_usage.cached_input())
    └── format_with_separators(token_usage.output_tokens)
    └── format_with_separators(token_usage.reasoning_output_tokens)
```

## 风险、边界与改进建议

### 已知风险

1. **Locale 检测失败**
   - 风险：`sys_locale::get_locale()` 可能返回 None 或无效 locale
   - 缓解：已实现 en-US 回退机制

2. **负数输入**
   - 风险：`format_si_suffix` 使用 `n.max(0)` 静默处理负数
   - 影响：token 计数不应该为负，但如果传入负数会被强制转为 0

3. **大数溢出**
   - 风险：`n as f64` 转换在极大值时可能丢失精度
   - 边界：超过 2^53 的整数可能无法精确表示

### 边界条件

| 输入 | 输出 | 说明 |
|------|------|------|
| 0 | "0" | 最小值 |
| 999 | "999" | 不使用后缀的边界 |
| 1000 | "1.00K" | 第一个后缀阈值 |
| 999_500 | "1.00M" | 进位边界 |
| 1_000_000_000_000 | "1,234G" | 超过 1000G 的特殊处理 |

### 改进建议

1. **添加更多测试用例**
   - 边界值测试（999, 1000, 999_500, 1_000_000 等）
   - 负数处理测试（当前被静默转为 0）
   - 极大值测试（超过 2^53）

2. **考虑添加更多格式化选项**
   - 二进制后缀（KiB/MiB/GiB）支持
   - 自定义精度控制参数

3. **性能优化**
   - 当前每次调用都创建新的 `Decimal` 对象
   - 考虑预计算常用值的格式化结果

4. **错误处理**
   - 考虑对负数输入返回 `Result` 而不是静默处理
   - 添加对溢出情况的明确处理

### 测试覆盖

当前测试（`kmg` 测试函数）覆盖了：
- 0 值
- 各单位的边界值
- 进位情况
- 超过 1000G 的特殊情况

建议补充：
- 负数输入行为验证
- 极大值精度测试
- 多 locale 格式化一致性测试
