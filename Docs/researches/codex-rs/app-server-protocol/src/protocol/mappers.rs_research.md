# mappers.rs 研究文档

## 场景与职责

`mappers.rs` 是 Codex App Server Protocol 中的类型转换模块，负责在 **v1 (遗留 API)** 和 **v2 (新 API)** 之间进行参数类型的映射和转换。

该文件的核心职责是：
1. **API 版本兼容性**：实现 v1 到 v2 的参数转换，确保遗留客户端可以继续工作
2. **类型桥接**：将旧的 `ExecOneOffCommandParams` 转换为新的 `CommandExecParams`
3. **默认值填充**：在转换过程中为新 API 的必填字段提供合理的默认值

## 功能点目的

### v1 → v2 参数转换

当客户端使用 v1 API（如 `ExecOneOffCommandParams`）发送请求时，服务器需要将其转换为内部使用的 v2 类型（`CommandExecParams`）。这个转换过程需要：

1. **字段映射**：将 v1 字段映射到对应的 v2 字段
2. **默认值填充**：v2 新增字段需要设置合理的默认值
3. **类型转换**：处理类型差异（如 `u64` → `i64`）

## 具体技术实现

### 核心实现

```rust
impl From<v1::ExecOneOffCommandParams> for v2::CommandExecParams {
    fn from(value: v1::ExecOneOffCommandParams) -> Self {
        Self {
            command: value.command,
            process_id: None,                    // v1 无此概念，设为 None
            tty: false,                          // v1 不支持 TTY，默认 false
            stream_stdin: false,                 // v1 不支持流式输入
            stream_stdout_stderr: false,         // v1 不支持流式输出
            output_bytes_cap: None,              // v1 无输出限制概念
            disable_output_cap: false,           // 默认启用输出限制
            disable_timeout: false,              // 默认启用超时
            timeout_ms: value.timeout_ms
                .map(|timeout| i64::try_from(timeout).unwrap_or(60_000)),
            cwd: value.cwd,
            env: None,                           // v1 不支持环境变量覆盖
            size: None,                          // v1 不支持 PTY 尺寸
            sandbox_policy: value.sandbox_policy.map(std::convert::Into::into),
        }
    }
}
```

### 字段映射详解

| v1 字段 | v2 字段 | 转换逻辑 |
|---------|---------|----------|
| `command` | `command` | 直接传递 |
| `timeout_ms` | `timeout_ms` | `u64` → `i64`，溢出时默认 60s |
| `cwd` | `cwd` | 直接传递 |
| `sandbox_policy` | `sandbox_policy` | 使用 `Into` trait 转换 |
| - | `process_id` | 设为 `None`（v1 无此概念） |
| - | `tty` | 设为 `false`（v1 不支持） |
| - | `stream_stdin` | 设为 `false`（v1 不支持） |
| - | `stream_stdout_stderr` | 设为 `false`（v1 不支持） |
| - | `output_bytes_cap` | 设为 `None`（v1 无限制） |
| - | `disable_output_cap` | 设为 `false` |
| - | `disable_timeout` | 设为 `false` |
| - | `env` | 设为 `None`（v1 不支持） |
| - | `size` | 设为 `None`（v1 不支持 PTY） |

## 关键代码路径与文件引用

### 文件关系
```
mappers.rs
├── 导入
│   ├── crate::protocol::v1 (源类型)
│   └── crate::protocol::v2 (目标类型)
└── impl From<v1::ExecOneOffCommandParams> for v2::CommandExecParams

使用位置：
├── codex-app-server (服务器端处理 v1 请求时)
└── 可能的其他兼容层代码
```

### 相关类型定义

**v1::ExecOneOffCommandParams** (位于 `protocol/v1.rs`):
```rust
pub struct ExecOneOffCommandParams {
    pub command: Vec<String>,
    pub timeout_ms: Option<u64>,
    pub cwd: Option<PathBuf>,
    pub sandbox_policy: Option<SandboxPolicy>,
}
```

**v2::CommandExecParams** (位于 `protocol/v2.rs`):
```rust
pub struct CommandExecParams {
    pub command: Vec<String>,
    pub process_id: Option<String>,
    pub tty: bool,
    pub stream_stdin: bool,
    pub stream_stdout_stderr: bool,
    pub output_bytes_cap: Option<usize>,
    pub disable_output_cap: bool,
    pub disable_timeout: bool,
    pub timeout_ms: Option<i64>,
    pub cwd: Option<PathBuf>,
    pub env: Option<HashMap<String, Option<String>>>,
    pub size: Option<CommandExecTerminalSize>,
    pub sandbox_policy: Option<SandboxPolicy>,
}
```

## 依赖与外部交互

### 内部依赖
- `crate::protocol::v1`: 源类型定义（遗留 API）
- `crate::protocol::v2`: 目标类型定义（新 API）

### 转换特性
- 使用标准库的 `From` trait 实现类型转换
- 转换是单向的（v1 → v2），没有实现反向转换
- 转换过程不会失败（非 `TryFrom`），因为所有字段都有默认值

## 风险、边界与改进建议

### 当前风险

1. **单向转换限制**
   - 只有 v1 → v2 的转换，没有反向转换
   - 如果需要将 v2 响应转换回 v1 格式，需要额外的映射逻辑

2. **默认值选择风险**
   - `unwrap_or(60_000)` 在 `timeout_ms` 转换溢出时使用固定默认值
   - 这个默认值可能不适合所有场景

3. **功能丢失**
   - v1 调用者无法使用 v2 的新功能（TTY、流式 I/O、环境变量等）
   - 这是设计上的限制，但需要明确文档说明

### 边界情况

1. **超时值溢出**
   ```rust
   timeout_ms: value.timeout_ms
       .map(|timeout| i64::try_from(timeout).unwrap_or(60_000))
   ```
   - 当 v1 的 `timeout_ms` > `i64::MAX` 时，会使用默认值 60s
   - 这在实际中不太可能发生，但仍是潜在问题

2. **路径处理**
   - `cwd` 在 v1 和 v2 中都是 `Option<PathBuf>`
   - 直接传递，没有额外的路径验证或规范化

### 改进建议

1. **增加更多映射**
   - 当前只有一个 `From` 实现
   - 建议：随着 v1 API 的废弃，逐步增加其他类型的转换

2. **使用 TryFrom 处理潜在错误**
   - 考虑将某些转换改为 `TryFrom`，以便更好地处理边界情况
   - 例如，如果 `sandbox_policy` 转换可能失败，应该使用 `TryFrom`

3. **文档化默认值**
   - 当前默认值分散在代码中
   - 建议：增加文档说明每个默认值的含义和选择理由

4. **考虑移除 v1 支持**
   - 如果 v1 API 使用率很低，可以考虑完全移除支持
   - 这样可以简化代码，减少维护负担

### 代码质量

- 文件非常简单（仅 23 行），职责单一明确
- 使用标准 `From` trait，符合 Rust 惯用法
- 建议：增加单元测试验证转换逻辑
