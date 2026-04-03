# TextRange.ts 研究文档

## 场景与职责

`TextRange` 是 Codex App-Server Protocol v2 API 中的文本范围类型，用于标识源代码或文本内容中的一个连续片段。该类型主要服务于：

1. **错误定位**：在配置警告、解析错误中标识问题代码的具体范围
2. **代码高亮**：为 IDE 提供需要高亮或标记的文本区域
3. **变更追踪**：标识代码修改、建议替换的文本范围

## 功能点目的

### 核心功能

| 字段 | 类型 | 说明 |
|------|------|------|
| `start` | `TextPosition` | 范围起始位置（包含） |
| `end` | `TextPosition` | 范围结束位置（不包含） |

### 设计特点

1. **半开区间**：采用 `[start, end)` 半开区间语义，便于计算范围长度
2. **组合设计**：复用 `TextPosition` 类型，确保位置表示的一致性
3. **方向性**：`start` 必须在 `end` 之前或相同位置

## 具体技术实现

### TypeScript 类型定义

```typescript
import type { TextPosition } from "./TextPosition";

export type TextRange = { 
  start: TextPosition, 
  end: TextPosition, 
};
```

### Rust 源码对应

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TextRange {
    pub start: TextPosition,
    pub end: TextPosition,
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源码）
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 5830-5836): Rust 类型定义

### 下游使用方
- `ConfigWarningNotification.ts`: 使用 `TextRange` 标识配置文件中警告的具体位置

### 相关类型
- `TextPosition.ts`: 位置类型，作为 `TextRange` 的组成元素

## 依赖与外部交互

### 导入依赖
```typescript
import type { TextPosition } from "./TextPosition";
```

### 使用示例

```typescript
import type { TextRange, TextPosition } from "./v2";

// 定义一个文本范围（第10行第5列 到 第12行第20列）
const range: TextRange = {
  start: { line: 10, column: 5 },
  end: { line: 12, column: 20 }
};

// 在配置警告中使用
const warning = {
  summary: "Deprecated configuration key",
  range: range,
  path: "/path/to/config.toml"
};
```

## 风险、边界与改进建议

### 边界情况

1. **空范围**：当 `start` 等于 `end` 时，表示空范围
2. **反向范围**：`start` 在 `end` 之后，属于无效范围，需要校验
3. **跨行范围**：范围可以跨越多行，计算长度时需要考虑行边界

### 改进建议

1. **添加验证方法**：提供 `isValidRange()` 检查 start <= end
2. **工具函数**：
   - `rangeLength()`: 计算范围内字符数
   - `contains(position)`: 检查位置是否在范围内
   - `intersects(other)`: 检查两个范围是否相交
3. **序列化校验**：在反序列化时验证范围有效性

### 注意事项

- 该文件为**自动生成**，修改会被覆盖
- 半开区间语义需要在使用文档中明确说明
- 与 LSP (Language Server Protocol) 的 Range 类型语义一致
