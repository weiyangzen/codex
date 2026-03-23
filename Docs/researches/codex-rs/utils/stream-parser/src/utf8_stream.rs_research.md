# utf8_stream.rs 研究文档

## 场景与职责

`utf8_stream.rs` 实现了 `Utf8StreamParser<P>`，这是一个适配器/包装器，用于将任何 `StreamTextParser` 实现从 `&str` 输入扩展到 `&[u8]` 输入。

**核心问题**: 当从网络或文件读取原始字节流时，UTF-8 编码的多字节字符可能被分割在多个数据块边界上。例如字符 `é` (U+00E9) 编码为 `[0xC3, 0xA9]`，可能被分割为 `[0xC3]` 和 `[0xA9]` 两个块。

**解决方案**: `Utf8StreamParser` 缓冲不完整的 UTF-8 序列，直到收集完整字符后再传递给内部解析器。

## 功能点目的

### Utf8StreamParserError
- 错误类型枚举
- 变体:
  - `InvalidUtf8 { valid_up_to, error_len }`: 无效的 UTF-8 序列
  - `IncompleteUtf8AtEof`: EOF 时有不完整的 UTF-8 码点

### Utf8StreamParser<P>
- 适配器结构
- 类型参数 `P: StreamTextParser`: 内部解析器
- 字段:
  - `inner: P`: 被包装的内部解析器
  - `pending_utf8: Vec<u8>`: 待处理的 UTF-8 字节缓冲区

### 方法
- `push_bytes(&mut self, chunk: &[u8]) -> Result<...>`: 处理字节块
- `finish(&mut self) -> Result<...>`: 完成解析
- `into_inner(self) -> Result<P, ...>`: 提取内部解析器（验证缓冲区为空）
- `into_inner_lossy(self) -> P`: 提取内部解析器（丢弃缓冲区）

## 具体技术实现

### Utf8StreamParserError 定义

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Utf8StreamParserError {
    InvalidUtf8 {
        valid_up_to: usize,  // 有效字节偏移
        error_len: usize,    // 错误序列长度
    },
    IncompleteUtf8AtEof,
}

impl fmt::Display for Utf8StreamParserError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidUtf8 { valid_up_to, error_len } => {
                write!(f, "invalid UTF-8 in streamed bytes at offset {valid_up_to} (error length {error_len})")
            }
            Self::IncompleteUtf8AtEof => {
                write!(f, "incomplete UTF-8 code point at end of stream")
            }
        }
    }
}

impl Error for Utf8StreamParserError {}
```

### Utf8StreamParser 结构

```rust
#[derive(Debug)]
pub struct Utf8StreamParser<P> {
    inner: P,
    pending_utf8: Vec<u8>,
}
```

### 构造函数

```rust
impl<P> Utf8StreamParser<P>
where
    P: StreamTextParser,
{
    pub fn new(inner: P) -> Self {
        Self {
            inner,
            pending_utf8: Vec::new(),
        }
    }
}
```

### push_bytes 核心逻辑

```rust
pub fn push_bytes(
    &mut self,
    chunk: &[u8],
) -> Result<StreamTextChunk<P::Extracted>, Utf8StreamParserError> {
    let old_len = self.pending_utf8.len();
    self.pending_utf8.extend_from_slice(chunk);

    match std::str::from_utf8(&self.pending_utf8) {
        Ok(text) => {
            // 全部有效 UTF-8
            let out = self.inner.push_str(text);
            self.pending_utf8.clear();
            Ok(out)
        }
        Err(err) => {
            if let Some(error_len) = err.error_len() {
                // 发现无效序列，回滚整个块
                self.pending_utf8.truncate(old_len);
                return Err(Utf8StreamParserError::InvalidUtf8 {
                    valid_up_to: err.valid_up_to(),
                    error_len,
                });
            }

            let valid_up_to = err.valid_up_to();
            if valid_up_to == 0 {
                // 没有有效字节，全部缓冲
                return Ok(StreamTextChunk::default());
            }

            // 处理有效前缀
            let text = match std::str::from_utf8(&self.pending_utf8[..valid_up_to]) {
                Ok(text) => text,
                Err(prefix_err) => {
                    self.pending_utf8.truncate(old_len);
                    let error_len = prefix_err.error_len().unwrap_or(0);
                    return Err(Utf8StreamParserError::InvalidUtf8 {
                        valid_up_to: prefix_err.valid_up_to(),
                        error_len,
                    });
                }
            };
            let out = self.inner.push_str(text);
            self.pending_utf8.drain(..valid_up_to);
            Ok(out)
        }
    }
}
```

### finish 处理

```rust
pub fn finish(&mut self) -> Result<StreamTextChunk<P::Extracted>, Utf8StreamParserError> {
    // 检查缓冲区状态
    if !self.pending_utf8.is_empty() {
        match std::str::from_utf8(&self.pending_utf8) {
            Ok(_) => {}
            Err(err) => {
                if let Some(error_len) = err.error_len() {
                    return Err(Utf8StreamParserError::InvalidUtf8 {
                        valid_up_to: err.valid_up_to(),
                        error_len,
                    });
                }
                return Err(Utf8StreamParserError::IncompleteUtf8AtEof);
            }
        }
    }

    // 处理剩余字节
    let mut out = if self.pending_utf8.is_empty() {
        StreamTextChunk::default()
    } else {
        let text = match std::str::from_utf8(&self.pending_utf8) {
            Ok(text) => text,
            Err(err) => {
                let error_len = err.error_len().unwrap_or(0);
                return Err(Utf8StreamParserError::InvalidUtf8 {
                    valid_up_to: err.valid_up_to(),
                    error_len,
                });
            }
        };
        let out = self.inner.push_str(text);
        self.pending_utf8.clear();
        out
    };

    // 完成内部解析器
    let mut tail = self.inner.finish();
    out.visible_text.push_str(&tail.visible_text);
    out.extracted.append(&mut tail.extracted);
    Ok(out)
}
```

### into_inner 方法

```rust
/// 安全提取：验证缓冲区为空
pub fn into_inner(self) -> Result<P, Utf8StreamParserError> {
    if self.pending_utf8.is_empty() {
        return Ok(self.inner);
    }
    match std::str::from_utf8(&self.pending_utf8) {
        Ok(_) => Ok(self.inner),
        Err(err) => {
            if let Some(error_len) = err.error_len() {
                return Err(Utf8StreamParserError::InvalidUtf8 {
                    valid_up_to: err.valid_up_to(),
                    error_len,
                });
            }
            Err(Utf8StreamParserError::IncompleteUtf8AtEof)
        }
    }
}

/// 不安全提取：丢弃缓冲区
pub fn into_inner_lossy(self) -> P {
    self.inner
}
```

## 关键代码路径与文件引用

- **文件路径**: `codex-rs/utils/stream-parser/src/utf8_stream.rs`
- **依赖**:
  - `stream_text.rs`: `StreamTextChunk`, `StreamTextParser`
- **被依赖**:
  - `lib.rs`: 导出 `Utf8StreamParser`, `Utf8StreamParserError`

## 依赖与外部交互

### 使用示例

```rust
use codex_utils_stream_parser::{CitationStreamParser, Utf8StreamParser, Utf8StreamParserError};

let mut parser = Utf8StreamParser::new(CitationStreamParser::new());

// "é" split across chunks: 0xC3 + 0xA9
let first = parser.push_bytes(&[b'H', 0xC3])?;
assert_eq!(first.visible_text, "H");

let second = parser.push_bytes(&[0xA9, b'!'])?;
assert_eq!(second.visible_text, "é!");

let tail = parser.finish()?;
assert!(tail.visible_text.is_empty());
```

### 跨块 UTF-8 处理流程

```
块1: [b'A', 0xC3]           // 'A' + 'é' 的第一个字节
    ↓
pending_utf8: [b'A', 0xC3]
    ↓
from_utf8: Err(utf8_error)   // 不完整，valid_up_to = 1
    ↓
处理: "A"                    // 有效部分
pending_utf8: [0xC3]         // 保留不完整部分

块2: [0xA9, b'<', ...]       // 'é' 的第二个字节 + 后续
    ↓
pending_utf8: [0xC3, 0xA9, b'<', ...]
    ↓
from_utf8: Ok("é<...")       // 完整有效
    ↓
处理: "é<..."
pending_utf8: []             // 清空
```

### 错误恢复

```rust
// 遇到无效 UTF-8 时回滚
let err = parser.push_bytes(&[0xFF])?;  // 错误！
// pending_utf8 回滚到之前的状态

// 后续有效数据仍可处理
let next = parser.push_bytes(&[b'!'])?; // 成功
```

## 风险、边界与改进建议

### 边界情况处理

| 场景 | 行为 |
|------|------|
| 跨块分割 | `[0xC3]` + `[0xA9]` 正确合并为 `é` |
| 无效字节 | `[0xFF]` 触发错误，回滚整个块 |
| 混合有效/无效 | `ok[0xFF]` 触发错误，保留 `ok` |
| EOF 不完整 | `[0xC3]` 在 `finish()` 时触发 `IncompleteUtf8AtEof` |
| 空块 | 返回空结果 |

### 测试覆盖

| 测试 | 描述 |
|------|------|
| `utf8_stream_parser_handles_split_code_points_across_chunks` | 跨块码点处理 |
| `utf8_stream_parser_rolls_back_on_invalid_utf8_chunk` | 无效 UTF-8 回滚 |
| `utf8_stream_parser_rolls_back_entire_chunk_when_invalid_byte_follows_valid_prefix` | 混合有效/无效回滚 |
| `utf8_stream_parser_errors_on_incomplete_code_point_at_eof` | EOF 不完整错误 |
| `utf8_stream_parser_into_inner_errors_when_partial_code_point_is_buffered` | into_inner 验证 |
| `utf8_stream_parser_into_inner_lossy_drops_buffered_partial_code_point` | into_inner_lossy 行为 |

### 风险点

1. **错误回滚**: 遇到无效 UTF-8 时回滚整个块，可能丢失块内有效数据
   ```rust
   // 当前行为：整个块回滚
   parser.push_bytes(b"valid\xFFdata")?;  // 错误，全部回滚
   
   // 可能的改进：只回滚无效部分
   // 处理 "valid"，保留/丢弃 "\xFFdata"
   ```

2. **内存使用**: `pending_utf8` 可能累积最多 3 字节（UTF-8 最大序列长度减 1）

3. **重复验证**: `finish()` 和 `into_inner()` 都进行 UTF-8 验证，有重复计算

4. **错误信息**: `valid_up_to` 是相对于 `pending_utf8` 的偏移，可能让用户困惑

### 改进建议

1. **部分处理**: 对于 `b"valid\xFFdata"`，考虑处理 `valid` 部分而不是全部回滚
   ```rust
   // 可能的实现
   let valid_len = find_valid_prefix(chunk);
   if valid_len > 0 {
       process(&chunk[..valid_len]);
   }
   if valid_len < chunk.len() {
       return Err(InvalidUtf8 { ... });
   }
   ```

2. **SIMD 优化**: 对于大字节流，考虑使用 SIMD 加速 UTF-8 验证

3. **零拷贝**: 当前 `push_bytes` 总是复制到 `pending_utf8`，可考虑 `bytes` crate 的 `Bytes` 类型

4. **更精确的错误位置**: 报告错误相对于整个流的位置，而非当前缓冲区
   ```rust
   pub struct Utf8StreamParser<P> {
       // ...
       bytes_processed: usize,  // 跟踪总字节数
   }
   ```

5. **配置选项**: 允许配置错误处理策略（严格 vs 宽松）
   ```rust
   pub enum InvalidUtf8Policy {
       Error,      // 当前行为：返回错误
       Replace,    // 用 U+FFFD 替换无效序列
       Ignore,     // 跳过无效字节
   }
   ```

6. **异步支持**: 为 `async` 字节流提供适配器
   ```rust
   impl<P> Utf8StreamParser<P> {
       pub async fn push_bytes_async<R: AsyncRead>(...)
   }
   ```
