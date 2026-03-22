# function_tool.rs 研究文档

## 场景与职责

本文件定义了函数调用相关的错误类型，用于工具执行过程中的错误处理。这是一个极简的错误定义模块，为 Codex 的工具系统提供标准化的错误表示。

主要职责：
1. **错误类型定义**：定义函数调用过程中可能遇到的错误
2. **错误分类**：区分可恢复错误（返回给模型）和致命错误
3. **标准化错误消息**：提供一致的错误格式

## 功能点目的

### 1. 错误类型枚举 (`FunctionCallError`)

```rust
#[derive(Debug, Error, PartialEq)]
pub enum FunctionCallError {
    #[error("{0}")]
    RespondToModel(String),
    #[error("LocalShellCall without call_id or id")]
    MissingLocalShellCallId,
    #[error("Fatal error: {0}")]
    Fatal(String),
}
```

**错误变体说明**：

| 变体 | 用途 | 处理方式 |
|-----|------|---------|
| `RespondToModel(String)` | 可恢复错误，消息应返回给模型 | 将错误信息作为工具结果返回 |
| `MissingLocalShellCallId` | 本地 Shell 调用缺少必要标识 | 内部错误，通常表示逻辑缺陷 |
| `Fatal(String)` | 致命错误，无法继续执行 | 终止当前操作，可能需要用户干预 |

### 2. 错误 trait 实现

- `Debug`：调试输出
- `Error`：标准错误 trait（来自 `thiserror`）
- `PartialEq`：支持错误比较（便于测试）

## 具体技术实现

### thiserror 宏使用

使用 `thiserror::Error` 派生宏简化错误定义：

```rust
use thiserror::Error;

#[derive(Debug, Error, PartialEq)]
pub enum FunctionCallError {
    #[error("{0}")]  // 使用字符串格式化
    RespondToModel(String),
    
    #[error("LocalShellCall without call_id or id")]  // 静态消息
    MissingLocalShellCallId,
    
    #[error("Fatal error: {0}")]
    Fatal(String),
}
```

### 错误使用模式

在工具调用代码中的典型使用：

```rust
// 伪代码示意
async fn execute_tool(call: ToolCall) -> Result<ToolResult, FunctionCallError> {
    let call_id = call.id.ok_or(FunctionCallError::MissingLocalShellCallId)?;
    
    match execute_shell_command(&call.command).await {
        Ok(output) => Ok(ToolResult::success(output)),
        Err(e) if e.is_recoverable() => {
            Err(FunctionCallError::RespondToModel(format!(
                "Command failed: {}", e
            )))
        }
        Err(e) => {
            Err(FunctionCallError::Fatal(format!(
                "System error: {}", e
            )))
        }
    }
}
```

## 关键代码路径与文件引用

### 文件关系

```
function_tool.rs
    ↓ FunctionCallError
工具调用实现 (exec.rs, shell.rs 等)
    ↓ 错误处理
错误处理/上报逻辑
```

### 预期调用方

| 调用方 | 用途 |
|-------|------|
| `exec.rs` | Shell 执行错误 |
| `shell.rs` | Shell 工具错误 |
| `mcp_tool_call.rs` | MCP 工具调用错误 |
| `client.rs` | API 调用错误处理 |

### 相关测试

- `exec_tests.rs`：可能测试错误转换
- `shell_tests.rs`：可能测试 Shell 错误
- `mcp_tool_call_tests.rs`：MCP 工具错误测试

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `thiserror::Error` | 错误派生宏 |

### 无其他依赖

本模块极简，仅依赖 `thiserror` crate。

## 风险、边界与改进建议

### 当前特点

1. **极简设计**：仅三个错误变体，职责清晰
2. **可比较性**：`PartialEq` 支持便于测试断言
3. **标准化消息**：`thiserror` 提供一致的 Display 实现

### 潜在改进

1. **错误分类细化**：
   当前分类较粗，可考虑细化：
   ```rust
   pub enum FunctionCallError {
       // 用户/模型可恢复错误
       RespondToModel(String),
       
       // 参数错误
       InvalidArguments { tool: String, reason: String },
       
       // 执行错误
       ExecutionFailed { tool: String, exit_code: i32, stderr: String },
       
       // 超时
       Timeout { tool: String, duration: Duration },
       
       // 内部错误
       MissingLocalShellCallId,
       InternalError(String),
       
       // 系统级错误
       Fatal(String),
   }
   ```

2. **错误代码支持**：
   增加错误代码便于程序化识别：
   ```rust
   pub struct ErrorCode(&'static str);
   
   impl FunctionCallError {
       pub fn code(&self) -> ErrorCode {
           match self {
               Self::RespondToModel(_) => ErrorCode("TOOL_EXECUTION_FAILED"),
               Self::MissingLocalShellCallId => ErrorCode("INTERNAL_MISSING_ID"),
               Self::Fatal(_) => ErrorCode("FATAL"),
           }
       }
   }
   ```

3. **上下文支持**：
   使用 `anyhow` 或自定义上下文：
   ```rust
   #[derive(Debug, Error)]
   #[error("Function call failed: {message}")]
   pub struct FunctionCallError {
       pub kind: ErrorKind,
       pub message: String,
       pub source: Option<Box<dyn Error>>,
   }
   ```

4. **从其他错误转换**：
   ```rust
   impl From<std::io::Error> for FunctionCallError {
       fn from(e: std::io::Error) -> Self {
           Self::Fatal(format!("IO error: {}", e))
       }
   }
   ```

### 测试建议

由于本模块极简，测试主要在调用方进行：
- 验证错误正确构造
- 验证错误消息格式
- 验证错误比较（`PartialEq`）

建议在本模块增加基础测试：
```rust
#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn respond_to_model_display() {
        let err = FunctionCallError::RespondToModel("test".to_string());
        assert_eq!(err.to_string(), "test");
    }
    
    #[test]
    fn missing_id_display() {
        let err = FunctionCallError::MissingLocalShellCallId;
        assert_eq!(err.to_string(), "LocalShellCall without call_id or id");
    }
    
    #[test]
    fn fatal_display() {
        let err = FunctionCallError::Fatal("system down".to_string());
        assert_eq!(err.to_string(), "Fatal error: system down");
    }
    
    #[test]
    fn error_equality() {
        let e1 = FunctionCallError::RespondToModel("test".to_string());
        let e2 = FunctionCallError::RespondToModel("test".to_string());
        let e3 = FunctionCallError::RespondToModel("other".to_string());
        assert_eq!(e1, e2);
        assert_ne!(e1, e3);
    }
}
```
