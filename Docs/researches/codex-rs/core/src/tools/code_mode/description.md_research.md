# description.md 研究文档

## 场景与职责

`description.md` 是 **Code Mode `exec` 工具的文档模板**，用于向模型描述 `exec` 工具的功能、使用方式和全局辅助函数。该文档被嵌入到工具描述中，帮助模型理解如何正确使用 JavaScript 执行功能。

**核心定位**：
- 作为 `exec` 工具的系统提示（system prompt）的一部分
- 定义 `exec` 工具的输入格式（原始 JavaScript 源码）
- 说明可用的全局辅助函数和嵌套工具调用方式
- 描述执行控制参数（`yield_time_ms`, `max_output_tokens`）

## 功能点目的

### 1. 执行环境说明
```markdown
- Runs raw JavaScript in an isolated context (no Node, no file system, or network access, no console).
```
- 明确告知模型执行环境的限制：无 Node.js API、无文件系统、无网络访问、无 console
- 这是安全沙箱的关键特性，防止恶意代码执行

### 2. 输入格式规范
```markdown
- Send raw JavaScript source text, not JSON, quoted strings, or markdown code fences.
```
- 强调输入应为原始 JavaScript 源码，而非 JSON 或 Markdown 代码块
- 这与传统函数工具（接收 JSON 参数）形成对比

### 3. Pragma 指令支持
```markdown
- You may optionally start the tool input with a first-line pragma like `// @exec: {"yield_time_ms": 10000, "max_output_tokens": 1000}`.
- `yield_time_ms` asks `exec` to yield early after that many milliseconds if the script is still running.
- `max_output_tokens` sets the token budget for direct `exec` results. By default the result is truncated to 10000 tokens.
```
- 支持通过第一行注释传递执行参数
- `yield_time_ms`：控制脚本在多长时间后主动让出控制权（允许模型介入）
- `max_output_tokens`：限制输出结果的 token 数量

### 4. 嵌套工具调用说明
```markdown
- All nested tools are available on the global `tools` object, for example `await tools.exec_command(...)`.
- Tool names are exposed as normalized JavaScript identifiers, for example `await tools.mcp__ologs__get_profile(...)`.
- Tool methods take either string or object as parameter.
- They return either a structured value or a string based on the description above.
```
- 说明如何通过 `tools` 对象调用其他工具
- 工具名称会被规范化为有效的 JavaScript 标识符（如 `mcp__ologs__get_profile`）
- 参数可以是字符串或对象，返回值类型取决于工具定义

### 5. 全局辅助函数文档
| 函数 | 签名 | 用途 |
|------|------|------|
| `exit()` | `exit(): void` | 立即成功结束脚本（类似顶层 return） |
| `text()` | `text(value): InputTextItem` | 追加文本项并返回它 |
| `image()` | `image(url \| object): InputImageItem` | 追加图像项并返回它 |
| `store()` | `store(key, value): void` | 存储可序列化值供后续调用使用 |
| `load()` | `load(key): any` | 读取存储的值，不存在返回 undefined |
| `notify()` | `notify(value): void` | 立即注入额外的 custom_tool_call_output |
| `ALL_TOOLS` | `Array<{name, description}>` | 可用嵌套工具的元数据 |
| `yield_control()` | `yield_control(): void` | 立即让出累积的输出给模型 |

## 具体技术实现

### 文档结构
```markdown
description.md
├── 执行环境说明（隔离上下文）
├── 输入格式规范（原始 JS 源码）
├── Pragma 指令说明
│   ├── yield_time_ms
│   └── max_output_tokens
├── 嵌套工具调用说明
│   ├── tools 全局对象
│   ├── 工具名称规范化
│   ├── 参数类型
│   └── 返回值类型
└── 全局辅助函数详细说明
    ├── exit()
    ├── text()
    ├── image()
    ├── store()
    ├── load()
    ├── notify()
    ├── ALL_TOOLS
    └── yield_control()
```

### 在代码中的使用

**mod.rs 中的常量定义**（第 35 行）：
```rust
const CODE_MODE_DESCRIPTION_TEMPLATE: &str = include_str!("description.md");
```

**tool_description 函数中的使用**（第 72-99 行）：
```rust
pub(crate) fn tool_description(enabled_tools: &[(String, String)], code_mode_only: bool) -> String {
    let description_template = CODE_MODE_DESCRIPTION_TEMPLATE.trim_end();
    if !code_mode_only {
        return description_template.to_string();
    }
    // ... 在 code_mode_only 模式下追加嵌套工具引用
}
```

### 与 code_mode_description.rs 的协作

`code_mode_description.rs` 中的 `augment_tool_spec_for_code_mode` 函数会为每个嵌套工具追加 TypeScript 声明：

```rust
tool.description = append_code_mode_sample(
    &tool.description,
    &tool.name,
    "args",
    // ... 参数类型
    // ... 返回类型
);
```

这些追加的声明会与 `description.md` 的内容合并，形成完整的工具描述。

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/description.md`

### 调用方
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/mod.rs`
  - `tool_description()` 函数使用此模板生成工具描述
  - 常量 `CODE_MODE_DESCRIPTION_TEMPLATE` 嵌入此文件内容

### 相关文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode_description.rs` - 为嵌套工具生成 TypeScript 声明
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/wait_description.md` - `wait` 工具的文档模板

### 数据流
```
description.md
    │
    ├──> mod.rs:CODE_MODE_DESCRIPTION_TEMPLATE (编译时嵌入)
    │
    ├──> mod.rs:tool_description() (生成基础描述)
    │       │
    │       └──> 如果 code_mode_only: true
    │               └──> 追加嵌套工具引用
    │
    └──> 最终作为 exec 工具的 description 提供给模型
```

## 依赖与外部交互

### 输入依赖
| 来源 | 数据 | 说明 |
|------|------|------|
| 编译时 | 文件内容 | 通过 `include_str!` 嵌入 |
| 运行时 | enabled_tools | 可用的嵌套工具列表（用于 code_mode_only 模式） |

### 输出使用
| 目标 | 数据 | 说明 |
|------|------|------|
| 模型 | 工具描述 | 作为 system prompt 的一部分 |
| ToolSpec | description 字段 | 工具的元数据描述 |

### 与 runner.cjs 的对应关系
- `description.md` 中描述的全局函数（`text`, `image`, `store` 等）对应 `runner.cjs` 中 `createCodeModeHelpers` 创建的实际实现
- 文档中的 `tools` 对象对应 `runner.cjs` 中的 `createGlobalToolsNamespace` 创建的命名空间

## 风险、边界与改进建议

### 风险点

1. **文档与实现不同步**
   - `description.md` 描述的功能必须与 `runner.cjs` 的实现保持一致
   - 如果修改了 runner 中的 API 而忘记更新文档，模型会得到错误信息

2. **Token 开销**
   - 文档内容较长，会增加每次请求的 token 数量
   - 在 `code_mode_only` 模式下，还会追加所有嵌套工具的声明

3. **参数类型描述模糊**
   - `text()` 的参数描述为 `string | number | boolean | undefined | null`，但实际实现可能更严格
   - `image()` 的 detail 参数可选值在文档中没有明确列出

### 边界情况

1. **空 enabled_tools**
   - 当没有可用嵌套工具时，`tool_description` 不会追加工具引用部分
   - 这可能导致模型尝试调用不存在的工具

2. **code_mode_only 模式**
   - 在此模式下，模型被指示只使用 `exec/wait` 工具
   - 所有其他工具必须通过 `tools.xxx()` 方式调用

### 改进建议

1. **版本控制**
   - 在文档中添加版本号，便于追踪文档与实现的兼容性
   - 例如：`// Code Mode API v1.2`

2. **更详细的类型说明**
   ```markdown
   - `image(imageUrlOrItem: string | { image_url: string; detail?: "auto" | "low" | "high" | "original" | null })`
   ```
   当前文档缺少 detail 参数的可选值说明

3. **示例代码**
   - 添加更多使用示例，帮助模型理解复杂场景
   - 例如：如何组合使用 `store` 和 `load`，如何调用嵌套工具

4. **错误处理说明**
   - 说明脚本执行出错时的行为
   - 说明 `notify()` 和 `text()` 的区别和使用场景

5. **性能提示**
   - 添加关于 `yield_time_ms` 最佳实践的说明
   - 解释何时应该使用 `yield_control()` 主动让出

6. **与 wait_description.md 的交叉引用**
   - 在文档末尾添加对 `wait` 工具的引用
   - 说明 `exec` 和 `wait` 的配合使用模式
