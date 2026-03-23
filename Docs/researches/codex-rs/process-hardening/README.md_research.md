# README.md 研究文档

## 场景与职责

该文件是 `codex-process-hardening` crate 的文档入口，向开发者和用户介绍该 crate 的功能和使用场景。它位于 crate 根目录，是 GitHub 和 crates.io 上展示的首要文档。

## 功能点目的

1. **功能概述**：简要介绍 crate 的核心功能——进程加固
2. **使用场景说明**：说明该函数设计为在 `main()` 之前调用（通过 `#[ctor::ctor]`）
3. **安全措施列举**：列出该 crate 实现的具体安全加固措施

## 具体技术实现

### 文档结构

```markdown
# codex-process-hardening

This crate provides `pre_main_hardening()`, which is designed to be called 
pre-`main()` (using `#[ctor::ctor]`) to perform various process hardening steps, such as

- disabling core dumps
- disabling ptrace attach on Linux and macOS
- removing dangerous environment variables such as `LD_PRELOAD` and `DYLD_*`
```

### 关键功能点详解

#### 1. 禁用核心转储（Core Dumps）

**目的**：防止进程崩溃时生成内存转储文件，避免敏感信息泄露

**实现机制**：
- Linux/Android：使用 `prctl(PR_SET_DUMPABLE, 0)` 标记进程不可 dump
- 所有 Unix 平台：使用 `setrlimit(RLIMIT_CORE, 0)` 设置核心文件大小限制为 0

**代码路径**：
- `src/lib.rs:46` - `prctl` 调用
- `src/lib.rs:109-123` - `setrlimit` 实现

#### 2. 禁用 ptrace 附加

**目的**：防止调试器附加到进程，保护运行时内存数据

**平台差异**：
- Linux/Android：`prctl(PR_SET_DUMPABLE, 0)` 同时禁用 ptrace
- macOS：`ptrace(PT_DENY_ATTACH)` 明确禁止调试器附加
- BSD：仅通过 `setrlimit` 限制核心转储

**代码路径**：
- `src/lib.rs:46` - Linux 实现
- `src/lib.rs:85` - macOS 实现

#### 3. 清理危险环境变量

**目的**：防止动态链接器被劫持，避免恶意代码注入

**清理的变量**：
- Linux：`LD_PRELOAD`, `LD_LIBRARY_PATH` 等所有 `LD_*` 变量
- macOS：`DYLD_INSERT_LIBRARIES`, `DYLD_LIBRARY_PATH` 等所有 `DYLD_*` 变量

**代码路径**：
- `src/lib.rs:60-66` - Linux 环境变量清理
- `src/lib.rs:99-105` - macOS 环境变量清理
- `src/lib.rs:131-143` - 通用前缀匹配函数

### 使用模式

```rust
use codex_process_hardening::pre_main_hardening;

#[ctor::ctor]
fn pre_main() {
    pre_main_hardening();
}

fn main() {
    // 进程已进入加固状态
}
```

**实际使用示例**：
- `codex-rs/responses-api-proxy/src/main.rs:4-7` - responses-api-proxy 使用此模式

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/process-hardening/README.md` - 本文档

### 实现文件
- `codex-rs/process-hardening/src/lib.rs` - 完整实现（190 行）

### 使用示例
- `codex-rs/responses-api-proxy/src/main.rs` - 实际使用案例
- `codex-rs/responses-api-proxy/README.md` - 安全说明文档

### 构建配置
- `codex-rs/process-hardening/Cargo.toml` - 包配置
- `codex-rs/process-hardening/BUILD.bazel` - Bazel 构建配置

## 依赖与外部交互

### 外部 crate 依赖

| 依赖 | 用途 |
|------|------|
| `libc` | 提供系统调用接口（prctl, ptrace, setrlimit） |
| `ctor` | 由调用方使用，用于在 main 之前执行初始化代码 |

### 系统调用接口

| 系统调用 | 平台 | 用途 |
|----------|------|------|
| `prctl(PR_SET_DUMPABLE)` | Linux/Android | 禁用进程可 dump 性 |
| `ptrace(PT_DENY_ATTACH)` | macOS | 禁止调试器附加 |
| `setrlimit(RLIMIT_CORE)` | Unix | 设置核心文件大小限制 |

### 环境变量操作

- `std::env::vars_os()` - 获取所有环境变量
- `std::env::remove_var()` - 删除指定环境变量（unsafe 操作）

### 调用方

目前该 crate 被以下组件使用：
- `codex-responses-api-proxy` - OpenAI API 代理服务，用于保护 API 密钥

## 风险、边界与改进建议

### 风险

1. **过早退出风险**：如果加固操作失败，进程会立即退出（exit code 5-7），这可能导致难以调试的启动失败

2. **unsafe 代码使用**：环境变量删除使用 `unsafe` 块，虽然操作本身安全，但增加了代码审查复杂度

3. **非 UTF-8 环境变量处理**：代码使用 `OsStrExt::as_bytes()` 处理环境变量名，需要确保正确处理非 UTF-8 数据

4. **Windows 未实现**：Windows 平台目前为空实现，存在安全缺口

### 边界

1. **无法撤销**：一旦执行加固，无法动态撤销（如需要调试时）

2. **单点调用设计**：函数设计为只调用一次，多次调用是幂等的但无意义

3. **错误处理严格**：任何系统调用失败都会导致进程退出，没有降级模式

4. **测试限制**：由于加固操作会修改进程全局状态，某些测试可能需要在隔离进程中运行

### 改进建议

1. **完善文档**：
   - 添加使用示例代码
   - 说明各平台的具体行为差异
   - 添加故障排除指南

2. **添加配置选项**：
   ```rust
   pub struct HardeningOptions {
       pub disable_core_dumps: bool,
       pub disable_ptrace: bool,
       pub sanitize_env: bool,
       pub exit_on_error: bool,  // 允许降级模式
   }
   ```

3. **Windows 支持**：
   - 实现 Windows 平台的等效加固措施
   - 考虑使用 `SetProcessMitigationPolicy` API

4. **日志记录**：
   - 添加可选的日志输出，记录执行的加固操作
   - 使用 `tracing` 或 `log` crate 进行结构化日志

5. **测试增强**：
   - 添加集成测试验证加固效果
   - 测试非 UTF-8 环境变量处理
   - 添加文档测试（doctests）

6. **API 扩展**：
   - 提供查询当前加固状态的函数
   - 提供部分加固的细粒度控制

7. **文档改进建议**：
   ```markdown
   ## 快速开始
   
   ```toml
   [dependencies]
   codex-process-hardening = "0.0.0"
   ctor = "0.6"
   ```
   
   ```rust
   #[ctor::ctor]
   fn init() {
       codex_process_hardening::pre_main_hardening();
   }
   ```
   
   ## 平台支持
   
   | 功能 | Linux | macOS | Windows | BSD |
   |------|-------|-------|---------|-----|
   | 禁用核心转储 | ✅ | ✅ | ❌ | ✅ |
   | 禁用 ptrace | ✅ | ✅ | N/A | ❌ |
   | 清理 LD_* | ✅ | N/A | N/A | ✅ |
   | 清理 DYLD_* | N/A | ✅ | N/A | N/A |
   ```
