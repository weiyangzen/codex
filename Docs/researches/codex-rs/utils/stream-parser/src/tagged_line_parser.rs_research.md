# tagged_line_parser.rs 研究文档

## 场景与职责

`tagged_line_parser.rs` 实现了 `TaggedLineParser<T>`，一个基于行的标签块解析器。与 `InlineHiddenTagParser` 不同，该解析器要求标签必须独占一行（行首到行尾只有标签）。

**典型用途**: 解析 `<proposed_plan>...</proposed_plan>` 这样的块级标签，这些标签通常包含多行内容，且标签本身需要单独成行。

## 功能点目的

### TagSpec<T>
- 标签规范结构
- 字段:
  - `open: &'static str`: 开始标签（如 `<tag>`）
  - `close: &'static str`: 结束标签（如 `</tag>`）
  - `tag: T`: 标签类型标识

### TaggedLineSegment<T>
- 解析结果段枚举
- 变体:
  - `Normal(String)`: 普通文本
  - `TagStart(T)`: 标签开始
  - `TagDelta(T, String)`: 标签内的内容增量
  - `TagEnd(T)`: 标签结束

### TaggedLineParser<T>
- 核心解析器
- 特点:
  - 行级解析，标签必须独占一行
  - 支持多行内容块
  - 缓冲行直到能确定是否为标签行

## 具体技术实现

### 核心数据结构

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct TagSpec<T> {
    pub(crate) open: &'static str,
    pub(crate) close: &'static str,
    pub(crate) tag: T,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum TaggedLineSegment<T> {
    Normal(String),
    TagStart(T),
    TagDelta(T, String),
    TagEnd(T),
}

#[derive(Debug, Default)]
pub(crate) struct TaggedLineParser<T>
where
    T: Copy + Eq,
{
    specs: Vec<TagSpec<T>>,      // 标签规范列表
    active_tag: Option<T>,       // 当前激活的标签
    detect_tag: bool,            // 是否正在检测标签
    line_buffer: String,         // 行缓冲区
}
```

### 关键算法

#### parse 方法主循环

```rust
pub(crate) fn parse(&mut self, delta: &str) -> Vec<TaggedLineSegment<T>> {
    let mut segments = Vec::new();
    let mut run = String::new();

    for ch in delta.chars() {
        if self.detect_tag {
            // 标签检测模式
            if !run.is_empty() {
                self.push_text(std::mem::take(&mut run), &mut segments);
            }
            self.line_buffer.push(ch);
            
            if ch == '\n' {
                // 行结束，处理整行
                self.finish_line(&mut segments);
                continue;
            }
            
            let slug = self.line_buffer.trim_start();
            if slug.is_empty() || self.is_tag_prefix(slug) {
                // 空行或可能是标签前缀，继续缓冲
                continue;
            }
            
            // 确定不是标签行，转为普通文本模式
            let buffered = std::mem::take(&mut self.line_buffer);
            self.detect_tag = false;
            self.push_text(buffered, &mut segments);
            continue;
        }

        // 普通文本模式
        run.push(ch);
        if ch == '\n' {
            self.push_text(std::mem::take(&mut run), &mut segments);
            self.detect_tag = true;  // 新行开始，重新检测标签
        }
    }

    if !run.is_empty() {
        self.push_text(run, &mut segments);
    }

    segments
}
```

#### finish_line 处理

```rust
fn finish_line(&mut self, segments: &mut Vec<TaggedLineSegment<T>>) {
    let line = std::mem::take(&mut self.line_buffer);
    let without_newline = line.strip_suffix('\n').unwrap_or(&line);
    let slug = without_newline.trim_start().trim_end();

    // 尝试匹配开始标签
    if let Some(tag) = self.match_open(slug)
        && self.active_tag.is_none()
    {
        push_segment(segments, TaggedLineSegment::TagStart(tag));
        self.active_tag = Some(tag);
        self.detect_tag = true;
        return;
    }

    // 尝试匹配结束标签
    if let Some(tag) = self.match_close(slug)
        && self.active_tag == Some(tag)
    {
        push_segment(segments, TaggedLineSegment::TagEnd(tag));
        self.active_tag = None;
        self.detect_tag = true;
        return;
    }

    // 不是标签行，作为普通文本
    self.detect_tag = true;
    self.push_text(line, segments);
}
```

#### finish 处理（EOF）

```rust
pub(crate) fn finish(&mut self) -> Vec<TaggedLineSegment<T>> {
    let mut segments = Vec::new();
    
    if !self.line_buffer.is_empty() {
        let buffered = std::mem::take(&mut self.line_buffer);
        let without_newline = buffered.strip_suffix('\n').unwrap_or(&buffered);
        let slug = without_newline.trim_start().trim_end();

        // 尝试匹配开始或结束标签
        if let Some(tag) = self.match_open(slug)
            && self.active_tag.is_none()
        {
            push_segment(&mut segments, TaggedLineSegment::TagStart(tag));
            self.active_tag = Some(tag);
        } else if let Some(tag) = self.match_close(slug)
            && self.active_tag == Some(tag)
        {
            push_segment(&mut segments, TaggedLineSegment::TagEnd(tag));
            self.active_tag = None;
        } else {
            self.push_text(buffered, &mut segments);
        }
    }
    
    // 自动关闭未关闭的标签
    if let Some(tag) = self.active_tag.take() {
        push_segment(&mut segments, TaggedLineSegment::TagEnd(tag));
    }
    
    self.detect_tag = true;
    segments
}
```

#### 段合并优化

```rust
fn push_segment<T>(segments: &mut Vec<TaggedLineSegment<T>>, segment: TaggedLineSegment<T>)
where
    T: Copy + Eq,
{
    match segment {
        TaggedLineSegment::Normal(delta) => {
            if delta.is_empty() {
                return;
            }
            // 合并连续的 Normal 段
            if let Some(TaggedLineSegment::Normal(existing)) = segments.last_mut() {
                existing.push_str(&delta);
                return;
            }
            segments.push(TaggedLineSegment::Normal(delta));
        }
        TaggedLineSegment::TagDelta(tag, delta) => {
            if delta.is_empty() {
                return;
            }
            // 合并同标签连续的 TagDelta 段
            if let Some(TaggedLineSegment::TagDelta(existing_tag, existing)) = segments.last_mut()
                && *existing_tag == tag
            {
                existing.push_str(&delta);
                return;
            }
            segments.push(TaggedLineSegment::TagDelta(tag, delta));
        }
        TaggedLineSegment::TagStart(tag) => segments.push(TaggedLineSegment::TagStart(tag)),
        TaggedLineSegment::TagEnd(tag) => segments.push(TaggedLineSegment::TagEnd(tag)),
    }
}
```

## 关键代码路径与文件引用

- **文件路径**: `codex-rs/utils/stream-parser/src/tagged_line_parser.rs`
- **依赖**: 无（独立模块）
- **被依赖**:
  - `proposed_plan.rs`: `ProposedPlanParser` 基于此实现
  - `lib.rs`: 模块声明

## 依赖与外部交互

### 在 ProposedPlanParser 中的使用

```rust
// proposed_plan.rs
pub struct ProposedPlanParser {
    parser: TaggedLineParser<PlanTag>,
}

impl ProposedPlanParser {
    pub fn new() -> Self {
        Self {
            parser: TaggedLineParser::new(vec![TagSpec {
                open: OPEN_TAG,      // "<proposed_plan>"
                close: CLOSE_TAG,    // "</proposed_plan>"
                tag: PlanTag::ProposedPlan,
            }]),
        }
    }
}
```

### 使用示例

```rust
let mut parser = TaggedLineParser::new(vec![TagSpec {
    open: "<tag>",
    close: "</tag>",
    tag: Tag::Block,
}]);

// 缓冲直到确定是标签
let mut segments = parser.parse("<t");
segments.extend(parser.parse("ag>\nline\n</tag>\n"));
segments.extend(parser.finish());

// 结果:
// TagStart(Tag::Block)
// TagDelta(Tag::Block, "line\n")
// TagEnd(Tag::Block)
```

## 风险、边界与改进建议

### 边界情况处理

| 场景 | 行为 |
|------|------|
| 标签行有额外文本 | `<tag> extra\n` 被视为普通文本 |
| 跨块边界 | `<ta` + `g>\n` 正确处理 |
| 未关闭标签 | EOF 时自动关闭 |
| 空行 | 保留在普通文本中 |
| 缩进标签 | `  <tag>\n` 被视为普通文本（非独占行）|

### 测试覆盖

| 测试 | 描述 |
|------|------|
| `buffers_prefix_until_tag_is_decided` | 缓冲前缀直到确定标签 |
| `rejects_tag_lines_with_extra_text` | 拒绝带额外文本的标签行 |

### 风险点

1. **缩进敏感**: 标签必须行首开始（`trim_start()` 后匹配），缩进标签不被识别
2. **行尾空格**: `trim_end()` 处理，行尾空格不影响匹配
3. **内存使用**: `line_buffer` 可能累积大量数据（如果无换行符）

### 改进建议

1. **配置化缩进处理**: 允许配置是否接受缩进标签
   ```rust
   pub(crate) struct TagSpec<T> {
       // ...
       pub allow_indentation: bool,
   }
   ```

2. **行长度限制**: 添加 `line_buffer` 大小限制，防止内存溢出

3. **多标签支持**: 当前设计支持多标签，但测试覆盖不足

4. **错误报告**: 当前静默处理无效标签，可考虑添加警告机制

5. **性能优化**: 对于大文件，考虑使用 `memchr` 等快速字符串搜索
