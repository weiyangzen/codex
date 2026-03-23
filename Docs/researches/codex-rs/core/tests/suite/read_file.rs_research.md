# read_file.rs 研究文档

## 场景与职责

`read_file.rs` 是 Codex Core 的集成测试套件，专门测试 **read_file 工具** 功能。该工具允许 AI 助手读取文件内容，支持按行范围读取和缩进感知块读取两种模式。

**注意**: 该测试当前被标记为 `#[ignore = "disabled until we enable read_file tool"]`，表示 `read_file` 工具尚未在生产环境启用，相关功能可能仍在开发中。

## 功能点目的

### 1. 文件读取能力验证
验证 AI 可以通过工具调用读取指定文件的指定行范围。

### 2. 行号格式化
验证输出格式包含行号前缀（如 `L2: second`），便于 AI 精确定位代码位置。

### 3. 偏移和限制参数
验证 `offset`（起始行，1-indexed）和 `limit`（最大行数）参数正确工作。

## 具体技术实现

### 工具参数结构

```rust
// read_file 工具的参数
{
    "file_path": "/absolute/path/to/file",  // 绝对路径
    "offset": 2,                             // 从第 2 行开始（1-indexed）
    "limit": 2,                              // 最多读取 2 行
}
```

### 预期输出格式

```
L2: second
L3: third
```

- 每行以 `L{行号}: ` 开头
- 行号从 1 开始计数
- 空行也会被编号

### 测试流程

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
#[ignore = "disabled until we enable read_file tool"]
async fn read_file_tool_returns_requested_lines() -> anyhow::Result<()> {
    skip_if_no_network!(Ok(()));
    
    // 1. 启动 Mock 服务器
    let server = start_mock_server().await;
    let test = test_codex().build(&server).await?;
    
    // 2. 创建测试文件
    let file_path = test.cwd.path().join("sample.txt");
    std::fs::write(&file_path, "first\nsecond\nthird\nfourth\n")?;
    let file_path = file_path.to_string_lossy().to_string();
    
    // 3. 配置工具调用响应
    let call_id = "read-file-call";
    let arguments = json!({
        "file_path": file_path,
        "offset": 2,
        "limit": 2,
    }).to_string();
    
    let mocks = mount_function_call_agent_response(
        &server, 
        call_id, 
        &arguments, 
        "read_file"
    ).await;
    
    // 4. 触发工具调用
    test.submit_turn("please inspect sample.txt").await?;
    
    // 5. 验证结果
    let req = mocks.completion.single_request();
    let (output_text_opt, _) = req
        .function_call_output_content_and_success(call_id)
        .expect("output present");
    let output_text = output_text_opt.expect("output text present");
    
    // 预期输出: "L2: second\nL3: third"
    assert_eq!(output_text, "L2: second\nL3: third");
    
    Ok(())
}
```

### 测试辅助工具

```rust
// 挂载函数调用代理响应
use core_test_support::responses::mount_function_call_agent_response;

// 该函数返回 Mock 句柄，用于验证：
// - completion: 完成请求的 Mock
// - 可以通过 single_request() 获取请求详情
// - 可以通过 function_call_output_content_and_success(call_id) 获取工具输出
```

## 依赖与外部交互

### 核心依赖

| 模块 | 用途 |
|-----|------|
| `core_test_support::responses::mount_function_call_agent_response` | 模拟 AI 函数调用响应 |
| `core_test_support::responses::start_mock_server` | 启动 Mock API 服务器 |
| `core_test_support::skip_if_no_network` | 无网络时跳过测试 |
| `core_test_support::test_codex::test_codex` | 构建测试 Codex 实例 |

### 工具处理器实现

```
codex-rs/core/src/tools/handlers/read_file.rs
├── ReadFileHandler 结构体
├── ReadFileArgs 参数解析
├── ReadMode 枚举（Slice / Indentation）
├── slice::read() - 简单行范围读取
└── indentation::read_block() - 缩进感知块读取
```

### 工具注册

```rust
// codex-rs/core/src/tools/handlers/mod.rs
pub fn create_builtin_tools() -> Vec<ToolDefinition> {
    vec![
        // ... 其他工具
        // read_file 工具（当前可能未启用）
    ]
}
```

## 风险、边界与改进建议

### 已知边界

1. **功能未启用**: 测试被 `#[ignore]` 标记，`read_file` 工具当前未在生产环境启用。

2. **平台限制**: 文件顶部有 `#![cfg(not(target_os = "windows"))]`，Windows 平台跳过。

3. **测试覆盖有限**: 当前仅测试 Slice 模式，未测试 Indentation 模式。

### 工具实现细节

从 `codex-rs/core/src/tools/handlers/read_file.rs` 可以看到完整实现支持：

**Slice 模式**:
- 按行号范围读取
- 支持大文件（流式读取）
- 自动处理换行符（`\n` / `\r\n`）
- 行长度限制（500 字符）

**Indentation 模式**:
- 基于缩进层级智能识别代码块
- 支持 `max_levels` 限制缩进深度
- 支持 `include_siblings` 包含同级块
- 支持 `include_header` 包含头部注释

### 改进建议

1. **启用测试**: 当 `read_file` 工具准备就绪时，移除 `#[ignore]` 标记。

2. **扩展测试覆盖**:
   ```rust
   // 建议添加的测试
   async fn read_file_with_indentation_mode();
   async fn read_file_offset_beyond_file_length();
   async fn read_file_empty_file();
   async fn read_file_binary_file();
   async fn read_file_permission_denied();
   ```

3. **错误处理测试**: 验证各种错误情况（文件不存在、权限不足、路径非绝对）的正确处理。

4. **大文件测试**: 测试大文件（>1000 行）的读取性能和内存使用。

5. **并发读取测试**: 测试多个并发 `read_file` 调用的行为。

6. **与 view 工具对比**: `read_file` 与现有的 `view` 工具功能有重叠，需要明确两者定位差异。

### 相关文件引用

- 测试文件: `codex-rs/core/tests/suite/read_file.rs` (42 行)
- 工具实现: `codex-rs/core/src/tools/handlers/read_file.rs` (489 行)
- 工具单元测试: `codex-rs/core/src/tools/handlers/read_file_tests.rs`
- 工具注册: `codex-rs/core/src/tools/handlers/mod.rs`
- 工具规范: `codex-rs/core/src/tools/spec.rs`
