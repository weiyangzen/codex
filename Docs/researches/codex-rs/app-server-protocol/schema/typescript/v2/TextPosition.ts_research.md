# TextPosition.ts 研究文档

## 场景与职责

`TextPosition` 是 Codex App-Server Protocol v2 API 中的基础文本定位类型，用于在源代码或文本内容中精确标识一个位置点。该类型主要服务于以下场景：

1. **代码定位与错误报告**：在配置警告、编译错误、代码分析结果中标识具体的行号和列号
2. **文本范围标记**：与 `TextRange` 配合使用，定义文本片段的起始和结束位置
3. **IDE 集成**：为 VSCode 等编辑器提供精确的代码位置信息，支持跳转到定义、错误高亮等功能

## 功能点目的

### 核心功能

| 字段 | 类型 | 说明 |
|------|------|------|
| `line` | `number` | 1-based 行号，从1开始计数 |
| `column` | `number` | 1-based 列号，基于 Unicode scalar values 计数 |

### 设计特点

1. **1-based 索引**：采用人类友好的1-based索引，符合编辑器行号显示习惯
2. **Unicode 感知**：列号基于 Unicode scalar values，正确处理多字节字符
3. **不可变设计**：作为纯数据类型，字段均为只读

## 具体技术实现

### TypeScript 类型定义

```typescript
export type TextPosition = { 
  /**
   * 1-based line number.
   */
  line: number, 
  /**
   * 1-based column number (in Unicode scalar values).
   */
  column: number, 
};
```

### Rust 源码对应

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TextPosition {
    /// 1-based line number.
    pub line: usize,
    /// 1-based column number (in Unicode scalar values).
    pub column: usize,
}
```

### 代码生成说明

该文件由 [ts-rs](https://github.com/Aleph-Alpha/ts-rs) 工具从 Rust 源码自动生成，**禁止手动修改**。生成流程：

1. Rust 编译时通过 `#[derive(TS)]` 宏生成 TypeScript 类型定义
2. 导出路径由 `#[ts(export_to = "v2/")]` 指定
3. 字段命名通过 `#[serde(rename_all = "camelCase")]` 转换为 camelCase

## 关键代码路径与文件引用

### 上游依赖（Rust 源码）
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 5820-5828): Rust 类型定义

### 下游使用方
- `TextRange.ts`: 使用 `TextPosition` 作为 `start` 和 `end` 字段类型
- `ConfigWarningNotification.ts`: 使用 `TextRange`（包含 `TextPosition`）标识配置警告位置

### 相关类型
- `TextRange.ts`: 文本范围类型，由两个 `TextPosition` 组成

## 依赖与外部交互

### 序列化/反序列化
- 使用 `serde` 进行 JSON 序列化，字段名转换为 camelCase
- 使用 `schemars` 生成 JSON Schema 用于 API 文档验证

### 使用示例

```typescript
// 定位到第10行第5列
const position: TextPosition = { line: 10, column: 5 };

// 在错误报告中使用
const error = {
  message: "Syntax error",
  position: { line: 10, column: 5 }
};
```

## 风险、边界与改进建议

### 边界情况

1. **行号/列号为0**：虽然类型定义为1-based，但运行时可能接收到0值，需要校验
2. **大文件处理**：对于超大文件（百万行以上），number 类型在 JavaScript 中可安全表示
3. **Unicode 处理**：列号基于 Unicode scalar values，与字节偏移量不同，需要注意区分

### 改进建议

1. **添加验证装饰器**：考虑添加运行时验证确保 line/column >= 1
2. **文档补充**：增加与0-based索引系统的转换说明
3. **工具函数**：提供辅助函数如 `isValidPosition()`、`comparePositions()` 等

### 注意事项

- 该文件为**自动生成**，任何修改都会被覆盖
- 如需修改，应编辑对应的 Rust 源码并重新生成
- 版本兼容性：该类型自 v2 API 引入以来保持稳定
