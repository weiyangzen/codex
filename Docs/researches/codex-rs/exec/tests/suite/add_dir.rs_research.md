# add_dir.rs 深度研究文档

## 场景与职责

`add_dir.rs` 是 `codex-exec` CLI 工具的集成测试模块，专门验证 `--add-dir` 命令行参数的功能。该参数允许用户在执行 Codex 任务时指定额外的可写目录，扩展了沙箱的写入范围。

**核心场景**：
- 用户需要让 Codex 能够访问和修改主工作目录之外的多个目录
- 验证 CLI 参数解析和传递的正确性
- 确保沙箱策略能够正确合并多个额外目录

## 功能点目的

### 1. 单目录添加测试 (`accepts_add_dir_flag`)
验证 `--add-dir` 参数能够被正确解析并传递给底层沙箱系统，使命令能够成功执行。

### 2. 多目录添加测试 (`accepts_multiple_add_dir_flags`)
验证多个 `--add-dir` 参数可以同时使用，且都能被正确传递到沙箱配置中。

## 具体技术实现

### 关键流程

```
测试启动
  ↓
创建临时目录 (tempfile::tempdir)
  ↓
启动 Mock SSE 服务器 (wiremock)
  ↓
构造 codex-exec 命令
  ├── --skip-git-repo-check (跳过 Git 检查)
  ├── --sandbox workspace-write (沙箱模式)
  ├── --add-dir <temp_dir1>
  ├── --add-dir <temp_dir2>
  └── <prompt>
  ↓
执行命令并验证退出码为 0
```

### 数据结构

**CLI 参数定义**（来自 `codex-rs/exec/src/cli.rs`）：
```rust
#[arg(long = "add-dir", value_name = "DIR", value_hint = clap::ValueHint::DirPath)]
pub add_dir: Vec<PathBuf>,
```

**配置覆盖**（来自 `codex-rs/exec/src/lib.rs`）：
```rust
ConfigOverrides {
    additional_writable_roots: add_dir,
    // ...
}
```

### 测试工具链

| 组件 | 用途 |
|------|------|
| `tempfile::tempdir()` | 创建临时目录用于测试 |
| `wiremock::MockServer` | 模拟 OpenAI Responses API |
| `assert_cmd::Command` | 断言命令执行结果 |
| `core_test_support::responses` | SSE 事件构造和 Mock 服务器 |

### SSE Mock 事件流

```rust
responses::sse(vec![
    responses::ev_response_created("response_1"),
    responses::ev_assistant_message("response_1", "Task completed"),
    responses::ev_completed("response_1"),
])
```

## 关键代码路径与文件引用

### 被测试代码路径

1. **CLI 参数解析**: `codex-rs/exec/src/cli.rs:71-72`
   - `--add-dir` 参数定义为 `Vec<PathBuf>`，支持多次使用

2. **运行时配置**: `codex-rs/exec/src/lib.rs:360`
   - `additional_writable_roots: add_dir` 传递给配置覆盖

3. **沙箱策略应用**: `codex-rs/core/src/config/mod.rs`
   - `additional_writable_roots` 被合并到沙箱的可写根目录列表

### 测试依赖

- `core_test_support::test_codex_exec::test_codex_exec` - 测试环境构造器
- `core_test_support::responses::start_mock_server` - Mock SSE 服务器
- `core_test_support::responses::mount_sse_once` - 挂载单次响应

## 依赖与外部交互

### 外部依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| `tempfile` | workspace | 临时目录创建 |
| `wiremock` | workspace | HTTP Mock 服务器 |
| `assert_cmd` | workspace | 命令行测试断言 |
| `tokio` | workspace | 异步运行时 |

### 环境变量

- `CODEX_HOME` - 由 `test_codex_exec()` 自动设置为临时目录
- `CODEX_API_KEY` - 自动设置为 "dummy"

### 平台限制

```rust
#![cfg(not(target_os = "windows"))]
```

测试在非 Windows 平台运行，因为沙箱机制在 Windows 上有不同实现。

## 风险、边界与改进建议

### 当前风险

1. **测试覆盖不足**: 仅验证参数被接受，未验证目录实际可写性
2. **Mock 依赖**: 使用固定 SSE 响应，不测试真实 API 交互
3. **沙箱行为未验证**: 未验证额外目录在沙箱中确实可写

### 边界情况

1. **路径包含空格**: 未测试带空格的路径
2. **相对路径**: 未测试相对路径解析
3. **不存在的目录**: 未测试目录不存在时的行为
4. **权限问题**: 未测试无权限访问的目录

### 改进建议

1. **增强验证**: 添加测试验证额外目录确实可写
   ```rust
   // 建议添加：验证文件写入
   let test_file = temp_dir1.path().join("test.txt");
   std::fs::write(&test_file, "test").unwrap();
   assert!(test_file.exists());
   ```

2. **边界测试**: 添加以下测试用例
   - 不存在的目录处理
   - 权限不足的目录
   - 包含特殊字符的路径
   - 符号链接目录

3. **集成测试**: 与真实沙箱机制集成测试，而非仅验证参数传递

4. **文档**: 添加 `--add-dir` 的使用示例到 CLI 帮助文本
