# ByteRange 类型研究文档

## 1. 场景与职责

### 使用场景
`ByteRange` 是 Codex App-Server Protocol v2 中用于表示文本缓冲区中字节范围的基础类型。它主要用于用户输入处理，标识文本中特定元素（如文件引用、命令、特殊标记等）的位置信息，支持 UI 渲染和持久化存储。

### 主要职责
- **位置标识**：标识文本缓冲区中一段内容的起始和结束字节位置
- **元素定位**：支持在文本中定位特殊元素（如 `TextElement`）
- **范围计算**：支持范围操作（如包含检查、交集计算等）
- **序列化传输**：在客户端和服务器之间传输文本位置信息

### 使用场景示例
```typescript
// 文本元素定位
const text = "请查看 @file:src/main.rs 中的代码";
const fileReference: TextElement = {
    byteRange: { start: 9, end: 26 },  // "@file:src/main.rs"
    placeholder: "src/main.rs",
};

// 范围操作
const range: ByteRange = { start: 10, end: 20 };
const length = range.end - range.start;  // 10 字节

// 包含检查
function contains(range: ByteRange, offset: number): boolean {
    return offset >= range.start && offset < range.end;
}
```

---

## 2. 功能点目的

### 2.1 字节级精确定位
- **目的**：提供字节级别的文本位置精度
- **优势**：
  - 支持多字节字符（如 UTF-8）
  - 与底层缓冲区表示一致
  - 不受显示宽度影响

### 2.2 范围边界定义
| 字段 | 类型 | 说明 |
|------|------|------|
| `start` | `number` | 范围起始字节偏移（包含） |
| `end` | `number` | 范围结束字节偏移（不包含） |

**范围语义**：`[start, end)` - 左闭右开区间
- `start` 指向范围第一个字节
- `end` 指向范围最后一个字节的下一个位置
- 空范围：`start === end`

### 2.3 与 TextElement 的协同
```
Text
    └── TextElement
            ├── byteRange: ByteRange  // 在父文本中的位置
            └── placeholder: string   // 显示占位符
```

### 2.4 使用场景
| 场景 | 说明 |
|------|------|
| 文件引用 | 标识 `@file:path` 在文本中的位置 |
| 命令标记 | 标识 `/command` 或特殊命令的位置 |
| 高亮显示 | UI 根据范围高亮特定文本段 |
| 文本编辑 | 支持基于范围的编辑操作 |
| 持久化 | 保存和恢复文本元素位置 |

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义
```typescript
export type ByteRange = { 
    start: number, 
    end: number, 
};
```

### 3.2 Rust 源类型定义
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ByteRange {
    pub start: usize,
    pub end: usize,
}
```

### 3.3 核心协议定义
```rust
// codex-rs/protocol/src/user_input.rs
#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
pub struct ByteRange {
    pub start: usize,
    pub end: usize,
}

impl ByteRange {
    pub fn new(start: usize, end: usize) -> Self {
        Self { start, end }
    }

    pub fn len(&self) -> usize {
        self.end - self.start
    }

    pub fn is_empty(&self) -> bool {
        self.start == self.end
    }

    pub fn contains(&self, offset: usize) -> bool {
        self.start <= offset && offset < self.end
    }
}
```

### 3.4 类型转换
```rust
// v2.rs:3981-3997
impl From<CoreByteRange> for ByteRange {
    fn from(value: CoreByteRange) -> Self {
        Self {
            start: value.start,
            end: value.end,
        }
    }
}

impl From<ByteRange> for CoreByteRange {
    fn from(value: ByteRange) -> Self {
        Self {
            start: value.start,
            end: value.end,
        }
    }
}
```

### 3.5 序列化特性
| 特性 | 说明 |
|------|------|
| `rename_all = "camelCase"` | 字段使用 camelCase |
| `usize` → `number` | Rust 的 `usize` 映射为 TypeScript 的 `number` |
| 无 `Option` 包装 | 两个字段都是必填的 |

---

## 4. 关键代码路径与文件引用

### 4.1 源文件位置
| 文件 | 路径 | 说明 |
|------|------|------|
| v2.rs | `codex-rs/app-server-protocol/src/protocol/v2.rs:3976-3997` | App-Server v2 定义和转换 |
| user_input.rs | `codex-rs/protocol/src/user_input.rs` | 核心协议定义 |

### 4.2 生成文件位置
| 文件 | 路径 | 说明 |
|------|------|------|
| ByteRange.ts | `codex-rs/app-server-protocol/schema/typescript/v2/ByteRange.ts` | TypeScript 类型定义 |
| JSON Schema | `codex-rs/app-server-protocol/schema/json/v2/ByteRange.json` | JSON Schema 定义 |

### 4.3 使用位置
| 文件 | 路径 | 用途 |
|------|------|------|
| TextElement | `v2.rs:4002-4007` | 文本元素的字节范围 |
| UserInput | `v2.rs:4045-4055` | 用户输入中的文本元素 |

### 4.4 代码引用链
```
UserInput::Text
    └── text: String
    └── elements: Vec<TextElement>
            └── TextElement
                    ├── byte_range: ByteRange
                    │       ├── start: usize
                    │       └── end: usize
                    └── placeholder: Option<String>
```

### 4.5 TextElement 完整定义
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TextElement {
    /// Byte range in the parent `text` buffer that this element occupies.
    pub byte_range: ByteRange,
    /// Optional human-readable placeholder for the element, displayed in the UI.
    placeholder: Option<String>,
}
```

---

## 5. 依赖与外部交互

### 5.1 直接依赖
`ByteRange` 是基础结构体类型，不依赖其他自定义类型。

### 5.2 上游依赖
| 依赖 | 来源 | 用途 |
|------|------|------|
| `ts-rs` | Rust crate | 生成 TypeScript 类型 |
| `schemars` | Rust crate | 生成 JSON Schema |
| `serde` | Rust crate | 序列化/反序列化 |

### 5.3 外部交互
| 交互方 | 交互方式 | 说明 |
|--------|----------|------|
| TextElement | 嵌套使用 | 作为 `byte_range` 字段类型 |
| UserInput | 嵌套使用 | 通过 TextElement 间接使用 |
| UI 系统 | 位置计算 | 根据范围渲染高亮、工具提示等 |
| 编辑器 | 编辑操作 | 基于范围的文本编辑 |

### 5.4 数据流
```
用户输入文本
    ↓ 解析
TextElement 识别（如 @file:path）
    ↓ 计算字节位置
ByteRange { start, end }
    ↓ 序列化
JSON { "start": N, "end": M }
    ↓ 传输
服务器 / 其他客户端
    ↓ 反序列化
ByteRange
    ↓ 使用
UI 渲染 / 持久化 / 编辑操作
```

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

#### 风险 1：字节偏移 vs 字符偏移混淆
- **问题**：用户可能混淆字节偏移和字符（Unicode 码点）偏移
- **影响**：在包含多字节字符（如中文、emoji）的文本中，位置计算错误
- **示例**：
  ```
  文本："你好"（6 字节，UTF-8）
  错误：{ start: 0, end: 2 }  // 以为是 2 个字符
  正确：{ start: 0, end: 6 }  // 实际是 6 个字节
  ```
- **缓解**：
  - 文档明确说明使用字节偏移
  - 提供辅助函数进行转换
  - UI 层做好适配

#### 风险 2：范围越界
- **问题**：`end` 可能超过文本长度，或 `start > end`
- **影响**：数组越界访问、panic 或错误渲染
- **缓解**：
  - 添加范围验证
  - 使用 saturating 运算

#### 风险 3：文本修改后范围失效
- **问题**：文本编辑后，原有的 `ByteRange` 可能指向错误位置
- **影响**：高亮错位、编辑操作错误
- **缓解**：
  - 文本修改时同步更新范围
  - 使用相对位置或标记而非绝对偏移

#### 风险 4：`usize` 平台差异
- **问题**：Rust 的 `usize` 在 32 位和 64 位平台大小不同
- **影响**：极端情况下可能溢出
- **缓解**：
  - 使用 `u64` 替代 `usize` 进行序列化
  - 限制文本大小

### 6.2 边界情况

| 场景 | 行为 | 说明 |
|------|------|------|
| `start === end` | 空范围 | 有效但长度为 0 |
| `start > end` | 无效范围 | 应该被验证拒绝 |
| `end` 超过文本长度 | 越界 | 应该被验证拒绝 |
| 负值 | 反序列化错误 | TypeScript `number` 可为负，但语义错误 |
| 浮点数 | 反序列化错误 | 应该只接受整数 |

### 6.3 改进建议

#### 建议 1：添加验证方法
```rust
impl ByteRange {
    pub fn validate(&self, text_len: usize) -> Result<(), ValidationError> {
        if self.start > self.end {
            return Err(ValidationError::InvalidRange {
                reason: "start cannot be greater than end",
            });
        }
        if self.end > text_len {
            return Err(ValidationError::OutOfBounds {
                end: self.end,
                text_len,
            });
        }
        Ok(())
    }

    pub fn is_valid(&self) -> bool {
        self.start <= self.end
    }
}
```

#### 建议 2：提供辅助函数
```rust
impl ByteRange {
    /// 检查两个范围是否相交
    pub fn intersects(&self, other: &ByteRange) -> bool {
        self.start < other.end && other.start < self.end
    }

    /// 计算交集
    pub fn intersection(&self, other: &ByteRange) -> Option<ByteRange> {
        let start = self.start.max(other.start);
        let end = self.end.min(other.end);
        if start < end {
            Some(ByteRange { start, end })
        } else {
            None
        }
    }

    /// 合并两个相邻或相交的范围
    pub fn merge(&self, other: &ByteRange) -> Option<ByteRange> {
        if self.intersects(other) || self.end == other.start || other.end == self.start {
            Some(ByteRange {
                start: self.start.min(other.start),
                end: self.end.max(other.end),
            })
        } else {
            None
        }
    }
}
```

#### 建议 3：字符偏移转换
```rust
impl ByteRange {
    /// 转换为字符偏移（假设文本是有效的 UTF-8）
    pub fn to_char_range(&self, text: &str) -> Option<CharRange> {
        let start_char = text[..self.start].chars().count();
        let end_char = text[..self.end].chars().count();
        Some(CharRange {
            start: start_char,
            end: end_char,
        })
    }

    /// 从字符偏移创建
    pub fn from_char_range(char_range: CharRange, text: &str) -> Option<ByteRange> {
        // 实现字符到字节的转换
    }
}

pub struct CharRange {
    pub start: usize,
    pub end: usize,
}
```

#### 建议 4：使用 u64 替代 usize
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ByteRange {
    pub start: u64,  // 替代 usize
    pub end: u64,
}
```

#### 建议 5：范围更新追踪
```rust
pub struct ByteRangeWithVersion {
    pub range: ByteRange,
    pub text_version: u64,  // 文本版本号
}

// 文本编辑时更新范围
pub fn adjust_ranges(
    ranges: &mut [ByteRange],
    edit_start: usize,
    edit_end: usize,
    new_text_len: usize,
) {
    let delta = new_text_len as isize - (edit_end - edit_start) as isize;
    for range in ranges {
        if range.start >= edit_end {
            range.start = (range.start as isize + delta) as usize;
            range.end = (range.end as isize + delta) as usize;
        } else if range.end <= edit_start {
            // 范围在编辑点之前，不受影响
        } else {
            // 范围与编辑区域相交，需要特殊处理
            // 可能标记为无效或重新计算
        }
    }
}
```

#### 建议 6：TypeScript 类型增强
```typescript
// 添加 branded type 增强类型安全
export type ByteOffset = number & { __brand: 'ByteOffset' };

export type ByteRange = { 
    start: ByteOffset, 
    end: ByteOffset,
};

// 验证函数
export function isValidByteRange(range: ByteRange): boolean {
    return Number.isInteger(range.start) 
        && Number.isInteger(range.end)
        && range.start >= 0 
        && range.end >= 0
        && range.start <= range.end;
}
```

### 6.4 性能考虑
- `ByteRange` 是轻量级结构体，只包含两个 `usize`
- 适合频繁创建和传递
- 复制成本低（在 64 位平台上仅 16 字节）
- 建议内联使用，避免堆分配
