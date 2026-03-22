# seek_sequence.rs 深度研究文档

## 场景与职责

`seek_sequence.rs` 是 `codex-apply-patch` crate 的核心算法模块，负责在文件内容中定位 patch chunk 的匹配位置。核心职责包括：

1. **序列匹配**：在文本行数组中查找模式序列的匹配位置
2. **多级容错匹配**：提供从精确匹配到模糊匹配的降级策略
3. **Unicode 规范化**：处理 ASCII 与 Unicode 标点符号的等价匹配
4. **EOF 定位支持**：支持从文件末尾开始反向匹配

该模块是 patch 应用的关键路径，直接影响 patch 应用的成功率和准确性。

## 功能点目的

### 1. 精确匹配
- **目的**：首先尝试字节级精确匹配
- **场景**：patch 内容与文件内容完全一致

### 2. 尾部空白容错
- **目的**：忽略行尾空白字符的差异
- **场景**：编辑器自动去除/添加行尾空格

### 3. 全空白容错
- **目的**：忽略行首和行尾的所有空白字符
- **场景**：缩进风格不一致（空格 vs Tab）

### 4. Unicode 规范化匹配
- **目的**：将 Unicode 标点符号映射为 ASCII 等价物后匹配
- **场景**：AI 模型使用 ASCII 字符，但源代码使用 typographic Unicode 字符

### 5. EOF 定位
- **目的**：优先从文件末尾开始匹配
- **场景**：在文件末尾添加新内容

## 具体技术实现

### 核心函数

```rust
/// 在 lines 中查找 pattern 的匹配位置
/// 
/// # 参数
/// - `lines`: 文件内容行数组
/// - `pattern`: 要查找的模式序列
/// - `start`: 开始搜索的索引
/// - `eof`: 是否优先从文件末尾匹配
///
/// # 返回
/// - `Some(index)`: 匹配的起始索引
/// - `None`: 未找到匹配
pub(crate) fn seek_sequence(
    lines: &[String],
    pattern: &[String],
    start: usize,
    eof: bool,
) -> Option<usize> {
    // 空模式直接返回当前位置
    if pattern.is_empty() {
        return Some(start);
    }

    // 模式比输入长，不可能匹配
    if pattern.len() > lines.len() {
        return None;
    }

    // 计算搜索起始位置
    let search_start = if eof && lines.len() >= pattern.len() {
        lines.len() - pattern.len()  // 从末尾开始
    } else {
        start  // 从指定位置开始
    };

    // 四级匹配策略（按严格程度降序）
    exact_match(lines, pattern, search_start)
        .or_else(|| rstrip_match(lines, pattern, search_start))
        .or_else(|| trim_match(lines, pattern, search_start))
        .or_else(|| normalised_match(lines, pattern, search_start))
}
```

### 四级匹配策略

#### 1. 精确匹配

```rust
// 字节级精确比较
for i in search_start..=lines.len() - pattern.len() {
    if lines[i..i + pattern.len()] == *pattern {
        return Some(i);
    }
}
```

#### 2. 尾部空白容错匹配

```rust
// 仅比较 trim_end() 后的结果
for i in search_start..=lines.len() - pattern.len() {
    let mut ok = true;
    for (p_idx, pat) in pattern.iter().enumerate() {
        if lines[i + p_idx].trim_end() != pat.trim_end() {
            ok = false;
            break;
        }
    }
    if ok {
        return Some(i);
    }
}
```

#### 3. 全空白容错匹配

```rust
// 比较 trim() 后的结果（行首行尾都忽略）
for i in search_start..=lines.len() - pattern.len() {
    let mut ok = true;
    for (p_idx, pat) in pattern.iter().enumerate() {
        if lines[i + p_idx].trim() != pat.trim() {
            ok = false;
            break;
        }
    }
    if ok {
        return Some(i);
    }
}
```

#### 4. Unicode 规范化匹配

```rust
fn normalise(s: &str) -> String {
    s.trim()
        .chars()
        .map(|c| match c {
            // 各类连字符/破折号 → ASCII '-'
            '\u{2010}' |  // HYPHEN
            '\u{2011}' |  // NON-BREAKING HYPHEN
            '\u{2012}' |  // FIGURE DASH
            '\u{2013}' |  // EN DASH
            '\u{2014}' |  // EM DASH
            '\u{2015}' |  // HORIZONTAL BAR
            '\u{2212}'    // MINUS SIGN
                => '-',
            
            // 花式单引号 → ASCII '\''
            '\u{2018}' |  // LEFT SINGLE QUOTATION MARK
            '\u{2019}' |  // RIGHT SINGLE QUOTATION MARK
            '\u{201A}' |  // SINGLE LOW-9 QUOTATION MARK
            '\u{201B}'    // SINGLE HIGH-REVERSED-9 QUOTATION MARK
                => '\'',
            
            // 花式双引号 → ASCII '"'
            '\u{201C}' |  // LEFT DOUBLE QUOTATION MARK
            '\u{201D}' |  // RIGHT DOUBLE QUOTATION MARK
            '\u{201E}' |  // DOUBLE LOW-9 QUOTATION MARK
            '\u{201F}'    // DOUBLE HIGH-REVERSED-9 QUOTATION MARK
                => '"',
            
            // 各种非断空格 → 普通空格
            '\u{00A0}' |  // NO-BREAK SPACE
            '\u{2002}' |  // EN SPACE
            '\u{2003}' |  // EM SPACE
            '\u{2004}' |  // THREE-PER-EM SPACE
            '\u{2005}' |  // FOUR-PER-EM SPACE
            '\u{2006}' |  // SIX-PER-EM SPACE
            '\u{2007}' |  // FIGURE SPACE
            '\u{2008}' |  // PUNCTUATION SPACE
            '\u{2009}' |  // THIN SPACE
            '\u{200A}' |  // HAIR SPACE
            '\u{202F}' |  // NARROW NO-BREAK SPACE
            '\u{205F}' |  // MEDIUM MATHEMATICAL SPACE
            '\u{3000}'    // IDEOGRAPHIC SPACE
                => ' ',
            
            other => other,
        })
        .collect::<String>()
}

// 规范化后比较
for i in search_start..=lines.len() - pattern.len() {
    let mut ok = true;
    for (p_idx, pat) in pattern.iter().enumerate() {
        if normalise(&lines[i + p_idx]) != normalise(pat) {
            ok = false;
            break;
        }
    }
    if ok {
        return Some(i);
    }
}
```

### 防御性编程

```rust
// 特殊 case：空模式
if pattern.is_empty() {
    return Some(start);  // 空模式匹配任意位置
}

// 特殊 case：模式比输入长
if pattern.len() > lines.len() {
    return None;  // 避免后续切片操作 panic
}
```

## 关键代码路径与文件引用

### 调用关系

```
lib.rs::compute_replacements()
    ├──► seek_sequence(ctx_line, ...)  // 查找 change_context
    └──► seek_sequence(old_lines, ..., eof)  // 查找 old_lines
```

### 调用参数

| 调用位置 | 用途 | pattern | eof |
|----------|------|---------|-----|
| `compute_replacements()` line 398 | 查找 change_context | `ctx_line` 单元素数组 | `false` |
| `compute_replacements()` line 439 | 查找 old_lines | `chunk.old_lines` | `chunk.is_end_of_file` |

### 模块可见性

```rust
pub(crate) fn seek_sequence(...)
```

- 仅 crate 内部可见
- 不对外暴露 API

## 依赖与外部交互

### 内部依赖

| 模块 | 交互 |
|------|------|
| `lib.rs` | 唯一调用方，用于 chunk 定位 |

### 外部依赖

- **无外部 crate 依赖**
- 仅使用标准库的 `String` 和字符处理

### 与 lib.rs 的协作

```rust
// lib.rs 中的调用示例
if let Some(ctx_line) = &chunk.change_context {
    if let Some(idx) = seek_sequence(
        original_lines,
        std::slice::from_ref(ctx_line),
        line_index,
        /*eof*/ false,
    ) {
        line_index = idx + 1;
    } else {
        return Err(ApplyPatchError::ComputeReplacements(
            format!("Failed to find context '{}' in {}", ctx_line, path.display())
        ));
    }
}

// 查找 old_lines
let found = seek_sequence(
    original_lines,
    pattern,
    line_index,
    chunk.is_end_of_file,
);
```

## 风险、边界与改进建议

### 已知风险

1. **性能问题**
   - 风险：四级匹配每层都是 O(n×m) 复杂度，最坏情况 O(4×n×m)
   - 场景：大文件中查找长模式，且前三级都失败
   - 现状：通常文件和 patch 不会太大，实际影响有限

2. **Unicode 规范化不完整**
   - 风险：未覆盖所有 Unicode 等价字符
   - 现状：仅覆盖常见标点和空格
   - 案例：希腊字母、数学符号等未处理

3. **模糊匹配过度宽松**
   - 风险：可能匹配到错误的位置
   - 场景：文件中存在多个相似段落
   - 缓解：change_context 提供额外定位

### 边界情况处理

| 场景 | 处理 |
|------|------|
| `pattern.is_empty()` | 返回 `Some(start)`，视为无操作匹配 |
| `pattern.len() > lines.len()` | 返回 `None`，避免切片越界 |
| `start > lines.len() - pattern.len()` | 搜索范围为空，返回 `None` |
| 包含 Unicode 组合字符 | 按码点处理，可能不符合用户预期 |
| 多行模式跨文件边界 | 不会越界，`lines.len() - pattern.len()` 限制 |

### 历史修复

```rust
// 2025-04-12 前的问题
// 当 pattern.len() > lines.len() 时，
// lines.len().saturating_sub(pattern.len()) 会产生很大的数，
// 导致切片 panic

// 修复：提前检查
if pattern.len() > lines.len() {
    return None;
}
```

### 改进建议

1. **性能优化**
   - 考虑使用 Boyer-Moore 或 KMP 算法优化单模式匹配
   - 对于多模式匹配，考虑 Aho-Corasick
   - 添加 early exit：如果某级匹配成功率高，跳过后续级别

2. **Unicode 完善**
   - 考虑使用 `unicode-normalization` crate 进行 NFC/NFKC 规范化
   - 添加更多常见字符映射（如全角/半角）

3. **匹配策略可配置**
   - 允许调用方指定使用哪些匹配级别
   - 例如：某些场景要求严格匹配，禁用模糊匹配

4. **诊断信息增强**
   - 返回匹配失败时的最佳候选位置
   - 提供相似度分数，帮助调试

5. **测试覆盖**
   - 增加大文件性能测试
   - 增加 Unicode 边界测试（组合字符、变体选择器等）
   - 增加并发安全测试（当前实现无状态，理论上线程安全）

### 设计评价

**优点**：
- ✅ 多级降级策略提高 patch 应用成功率
- ✅ Unicode 规范化解决 AI 模型与源代码的字符差异
- ✅ 防御性编程避免 panic
- ✅ 纯函数设计，无副作用，易于测试

**局限性**：
- ⚠️ 算法复杂度较高，大文件场景可能有性能问题
- ⚠️ Unicode 覆盖不完整
- ⚠️ 无法处理行顺序调整（仅支持原地替换）
