# mod.rs 研究文档

## 场景与职责

`mod.rs` 是 `codex-api/src/requests` 模块的入口文件，负责组织和导出请求相关的子模块。该模块是 Codex API 客户端的 HTTP 请求构建层的一部分，专门处理与 OpenAI Responses API 请求相关的功能。

## 功能点目的

模块仅包含两个导出声明：

1. **`headers` 模块** (crate 内部可见)
   - 提供 HTTP 头构建工具函数
   - 包含 `build_conversation_headers`、`subagent_header`、`insert_header`
   - 仅在 crate 内部使用 (`pub(crate)`)

2. **`responses` 模块** (公开)
   - 提供 Responses API 请求相关的辅助功能
   - 包含 `Compression` 枚举和 `attach_item_ids` 函数
   - 对外公开 (`pub`)

## 具体技术实现

### 模块可见性设计

```rust
pub(crate) mod headers;  // 仅 crate 内部可见
pub mod responses;       // 完全公开
```

这种可见性设计反映了两个模块的不同用途：
- `headers`：纯粹的内部工具，由 `endpoint/responses.rs` 调用，外部不需要直接使用
- `responses`：包含 `Compression` 类型，需要被外部（如 `core/src/client.rs`）使用

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/codex-api/src/requests/mod.rs` (2 行)

### 子模块
- `codex-rs/codex-api/src/requests/headers.rs` - HTTP 头构建工具
- `codex-rs/codex-api/src/requests/responses.rs` - Responses API 请求辅助

### 使用方
- `codex-rs/codex-api/src/lib.rs` - 导入 requests 模块
- `codex-rs/codex-api/src/endpoint/responses.rs` - 使用 `headers` 和 `responses`
- `codex-rs/core/src/client.rs` - 使用 `responses::Compression`

## 依赖与外部交互

无直接外部依赖，仅作为模块组织文件。

## 风险、边界与改进建议

### 当前设计评价

该模块设计简洁，符合 Rust 模块组织的最佳实践：
- 使用 `pub(crate)` 限制内部实现细节的外泄
- 仅公开必要的外部接口

### 潜在改进

1. **文档注释**：虽然模块简单，但建议添加模块级文档注释：
   ```rust
   //! HTTP request building utilities for the Responses API.
   ```

2. **模块重命名考虑**：`requests` 模块名与 `request` 动词可能混淆，但考虑到整个 crate 的命名一致性，当前命名可接受

3. **未来扩展**：如果未来添加更多端点（如 chat completions），可能需要类似的模块结构，可考虑统一模式
