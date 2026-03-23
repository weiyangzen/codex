# program_resolver.rs 研究文档

## 场景与职责

`program_resolver.rs` 是 `codex-rmcp-client` crate 中的跨平台程序解析模块。该模块解决了 Windows 和 Unix 系统在可执行文件解析上的差异，确保 MCP 服务器程序能够在不同平台上正确启动。

核心职责：
1. **跨平台程序解析**: 统一处理 Windows 和 Unix 的程序路径解析
2. **Windows 脚本支持**: 解决 Windows 需要显式文件扩展名（.cmd, .bat）的问题
3. **PATH 环境解析**: 在 Windows 上搜索 PATH 环境变量查找可执行文件

## 功能点目的

### 问题背景

**Unix 系统**：
- 通过 shebang (`#!`) 机制直接执行脚本
- `Command::new("node")` 可直接执行

**Windows 系统**：
- 需要显式文件扩展名（`.cmd`, `.bat`, `.exe`）
- `Command::new("npx")` 会失败，需要 `Command::new("npx.cmd")`
- PATH 搜索需要 `PATHEXT` 环境变量参与

### 解决方案

```rust
// Unix: 直接返回原程序名
pub fn resolve(program: OsString, _env: &HashMap<String, String>) -> std::io::Result<OsString> {
    Ok(program)
}

// Windows: 使用 which crate 解析完整路径
pub fn resolve(program: OsString, env: &HashMap<String, String>) -> std::io::Result<OsString> {
    // 使用 which::which_in 搜索 PATH
    // 回退到原程序名让 Command 处理错误
}
```

## 具体技术实现

### Unix 实现

```rust
#[cfg(unix)]
pub fn resolve(program: OsString, _env: &HashMap<String, String>) -> std::io::Result<OsString> {
    Ok(program)
}
```

**设计理由**：
- Unix 内核原生支持 shebang
- PATH 解析由操作系统处理
- 无需额外操作

### Windows 实现

```rust
#[cfg(windows)]
pub fn resolve(program: OsString, env: &HashMap<String, String>) -> std::io::Result<OsString> {
    // 获取当前目录用于相对路径解析
    let cwd = env::current_dir()
        .map_err(|e| std::io::Error::other(format!("Failed to get current directory: {e}")))?;

    // 从环境变量获取 PATH
    let search_path = env.get("PATH");

    // 使用 which crate 解析
    match which::which_in(&program, search_path, &cwd) {
        Ok(resolved) => {
            debug!("Resolved {:?} to {:?}", program, resolved);
            Ok(resolved.into_os_string())
        }
        Err(e) => {
            debug!("Failed to resolve {:?}: {}. Using original path", program, e);
            // 回退到原程序名
            Ok(program)
        }
    }
}
```

**关键依赖**：`which` crate

### 使用场景

该模块主要用于 `rmcp_client.rs` 中启动子进程 MCP 服务器：

```rust
// rmcp_client.rs
let resolved_program = program_resolver::resolve(program.clone(), &envs)?;
let mut command = Command::new(resolved_program);
```

**支持的程序类型**：
- `npx` → `npx.cmd` (Node.js 包执行器)
- `pnpm` → `pnpm.cmd` (包管理器)
- `yarn` → `yarn.cmd` (包管理器)
- 任何在 PATH 中的脚本或可执行文件

## 关键代码路径与文件引用

### 内部依赖

| 依赖项 | 路径 | 用途 |
|--------|------|------|
| `create_env_for_mcp_server` | `crate::utils` | 测试中使用创建环境 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `which` | Windows 上的可执行文件搜索 |
| `tracing::debug` | Windows 上的调试日志 |

### 调用关系

```
program_resolver.rs
├── 被 rmcp_client.rs 调用
│   └── resolve() 在创建子进程传输时
└── 内部使用
    ├── which::which_in (Windows)
    └── std::env::current_dir (Windows)
```

### 代码路径

```
RmcpClient::create_pending_transport()
├── TransportRecipe::Stdio { program, ... }
│   ├── create_env_for_mcp_server()  // 创建环境变量
│   ├── program_resolver::resolve(program, &envs)  // 解析程序路径
│   └── Command::new(resolved_program)  // 创建命令
```

## 依赖与外部交互

### 与 `which` crate 的交互

```rust
which::which_in(&program, search_path, &cwd)
```

**参数**：
- `program`: 要查找的程序名
- `search_path`: PATH 环境变量值（可选）
- `cwd`: 当前工作目录（用于相对路径解析）

**行为**：
- 搜索 `PATHEXT` 中定义的扩展名（Windows）
- 返回完整绝对路径

### 环境变量使用

| 变量 | 用途 |
|------|------|
| `PATH` | 可执行文件搜索路径 |
| `PATHEXT` | Windows 可执行文件扩展名列表 |

## 风险、边界与改进建议

### 当前设计特点

1. **Unix 零开销**: Unix 实现直接返回，无额外开销
2. **Windows 容错**: 解析失败时回退到原程序名，不阻断执行
3. **调试日志**: Windows 上记录解析成功/失败信息

### 潜在风险

1. **Windows 解析失败回退**: 如果 `which` 失败但程序实际可执行，回退后可能成功或失败
   - 场景：程序在当前目录但不在 PATH 中
   - 行为：回退后 `Command` 可能找到或找不到

2. **环境变量污染**: 使用传入的 `env` 参数而非 `std::env::var_os`，确保使用 MCP 服务器配置的环境

3. **相对路径处理**: `which::which_in` 使用传入的 `cwd`，但 `Command` 可能使用不同的工作目录

### 边界情况

1. **空 PATH**: `which` 会返回错误，回退到原程序名
2. **权限不足**: 即使找到程序，执行时可能因权限失败
3. **符号链接**: `which` 返回链接目标路径，不影响执行

### 测试覆盖

| 测试用例 | 平台 | 描述 |
|----------|------|------|
| `test_unix_executes_script_without_extension` | Unix | 验证无扩展名可执行 |
| `test_windows_fails_without_extension` | Windows | 验证无扩展名失败 |
| `test_windows_succeeds_with_extension` | Windows | 验证有扩展名成功 |
| `test_resolved_program_executes_successfully` | All | 验证解析后程序可执行 |

### 测试辅助结构

```rust
struct TestExecutableEnv {
    _temp_dir: TempDir,           // 保持目录存活
    program_name: String,         // 测试程序名
    mcp_env: HashMap<String, String>, // MCP 环境
}
```

**测试程序创建**：
- Windows: 创建 `.cmd` 文件，`@echo off\nexit 0`
- Unix: 创建无扩展名文件，`#!/bin/sh\nexit 0`，设置 0o755 权限

### 改进建议

1. **缓存机制**: 对解析结果进行缓存，避免重复搜索 PATH
2. **错误信息增强**: Windows 解析失败时提供更详细的搜索路径信息
3. **扩展名提示**: 如果 `program.cmd` 存在但请求的是 `program`，可给出提示
4. **跨平台测试**: 当前测试使用 `#[cfg]` 分割，可考虑使用模拟统一测试

### 代码质量

1. **文档完善**: 模块级文档详细说明了设计背景和平台差异
2. **条件编译**: 使用 `#[cfg(unix)]` / `#[cfg(windows)]` 清晰分离平台实现
3. **错误处理**: Windows 实现将错误转换为 `std::io::Error`

### 平台兼容性矩阵

| 功能 | Unix | Windows | 说明 |
|------|------|---------|------|
| 程序解析 | 直接返回 | which 搜索 | Unix 依赖 OS |
| 脚本执行 | shebang | 需扩展名 | Windows 需 .cmd/.bat |
| PATH 搜索 | OS 处理 | which crate | 两者效果一致 |
| 相对路径 | OS 处理 | which 解析 | 需确保 cwd 一致 |
