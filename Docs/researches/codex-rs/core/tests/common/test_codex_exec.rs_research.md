# test_codex_exec.rs 研究文档

## 文件基本信息

- **路径**: `codex-rs/core/tests/common/test_codex_exec.rs`
- **大小**: 约 48 行 (1380 bytes)
- **所属 crate**: `core_test_support`
- **用途**: `codex-exec` CLI 二进制测试辅助工具

---

## 场景与职责

`test_codex_exec.rs` 是专门为测试 `codex-exec` CLI 二进制文件而设计的轻量级辅助模块。它提供了**进程级测试**的基础设施，与 `test_codex.rs` 的**库级测试**形成互补。

### 核心职责

1. **CLI 进程封装**: 使用 `assert_cmd` 启动和控制 `codex-exec` 进程
2. **环境隔离**: 设置 `CODEX_HOME` 和 API key 环境变量
3. **服务器集成**: 将 mock 服务器 URL 传递给 CLI
4. **目录管理**: 提供临时 home 和 cwd 目录

### 与 test_codex.rs 的区别

| 特性 | test_codex.rs | test_codex_exec.rs |
|------|---------------|-------------------|
| 测试目标 | `codex_core` 库 | `codex-exec` 二进制 |
| 执行方式 | 函数调用 | 子进程启动 |
| 隔离级别 | 线程/任务 | 进程 |
| 适用场景 | 单元/集成测试 | 端到端/CLI 测试 |
| 性能 | 快 | 慢（进程启动开销） |

---

## 功能点目的

### 1. 构建器 (`TestCodexExecBuilder`)

```rust
pub struct TestCodexExecBuilder {
    home: TempDir,   // 临时 home 目录
    cwd: TempDir,    // 临时工作目录
}
```

**目的**: 为每个测试创建隔离的文件系统环境，避免：
- 测试间状态污染
- 开发者真实 `~/.codex` 被修改
- 并行测试冲突

### 2. 命令构造 (`cmd()`)

```rust
pub fn cmd(&self) -> assert_cmd::Command {
    let mut cmd = assert_cmd::Command::new(
        codex_utils_cargo_bin::cargo_bin("codex-exec")
            .expect("should find binary for codex-exec")
    );
    cmd.current_dir(self.cwd.path())
        .env("CODEX_HOME", self.home.path())
        .env(CODEX_API_KEY_ENV_VAR, "dummy");
    cmd
}
```

**关键设置**:
- **二进制定位**: 使用 `cargo_bin` 自动找到编译后的 `codex-exec`
- **工作目录**: 设置为临时 cwd
- **环境变量**:
  - `CODEX_HOME`: 指向临时 home，隔离配置和状态
  - `CODEX_API_KEY`: 设置虚拟 API key，避免认证失败

### 3. 服务器集成 (`cmd_with_server()`)

```rust
pub fn cmd_with_server(&self, server: &MockServer) -> assert_cmd::Command {
    let mut cmd = self.cmd();
    let base = format!("{}/v1", server.uri());
    cmd.arg("-c")
        .arg(format!("openai_base_url={}", toml_string_literal(&base)));
    cmd
}
```

**目的**: 将 mock 服务器 URL 通过 `-c` 参数传递给 CLI，覆盖默认的 OpenAI API 地址。

**TOML 字符串处理**:
```rust
fn toml_string_literal(value: &str) -> String {
    serde_json::to_string(value).expect("serialize TOML string literal")
}
```
使用 JSON 序列化生成带引号的字符串，确保 TOML 解析正确。

### 4. 路径访问器

```rust
pub fn cwd_path(&self) -> &Path;
pub fn home_path(&self) -> &Path;
```

**目的**: 允许测试代码在临时目录中创建文件或验证输出。

---

## 具体技术实现

### 工厂函数

```rust
pub fn test_codex_exec() -> TestCodexExecBuilder {
    TestCodexExecBuilder {
        home: TempDir::new().expect("create temp home"),
        cwd: TempDir::new().expect("create temp cwd"),
    }
}
```

**设计选择**:
- 使用 `expect()` 而非 `?`，因为测试辅助工具失败应直接 panic
- 同时创建 home 和 cwd，确保两者独立

### 使用模式

```rust
// 典型测试用例
#[tokio::test]
async fn test_exec_cli() {
    let builder = test_codex_exec();
    let server = start_mock_server().await;
    
    // 在 cwd 创建测试文件
    fs::write(builder.cwd_path().join("input.txt"), "hello").unwrap();
    
    // 启动 CLI 进程
    let mut cmd = builder.cmd_with_server(&server);
    cmd.arg("--prompt").arg("read input.txt");
    
    // 断言退出码和输出
    cmd.assert().success().stdout(predicate::str::contains("hello"));
}
```

---

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `lib.rs` | 模块导出 |
| `responses.rs` | `start_mock_server()` |

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `assert_cmd` | CLI 测试框架（断言、进程控制） |
| `tempfile` | `TempDir` 临时目录 |
| `wiremock` | `MockServer` |
| `codex_core` | `CODEX_API_KEY_ENV_VAR` 常量 |
| `codex_utils_cargo_bin` | `cargo_bin()` 二进制定位 |

### 调用方

该模块被 `codex-rs/exec/tests/` 中的测试使用：
- `codex-rs/exec/tests/suite/` 下的端到端测试

---

## 依赖与外部交互

### 1. CLI 参数协议

依赖 `codex-exec` 的以下参数：
- `-c, --config <KEY=VALUE>`: 内联配置覆盖
- `--prompt <TEXT>`: 执行单个 prompt

### 2. 环境变量协议

依赖 `codex-exec` 识别的环境变量：
- `CODEX_HOME`: 配置和状态目录
- `CODEX_API_KEY` (或 `OPENAI_API_KEY`): API 认证

### 3. 文件系统布局

```
{temp_home}/
├── config.toml      # 配置文件
├── auth.json        # 认证信息
└── ...

{temp_cwd}/
├── input.txt        # 测试输入文件
└── output.txt       # 测试输出文件
```

---

## 风险、边界与改进建议

### 已知风险

| 风险 | 影响 | 缓解 |
|------|------|------|
| 二进制未编译 | 测试失败 | 确保 `cargo build` 先执行 |
| 环境变量泄漏 | 测试间污染 | 每个测试新建 builder |
| 临时目录清理 | 磁盘空间 | `TempDir` Drop 时自动清理 |

### 边界条件

1. **单例 builder**: 每个测试应创建新的 builder，不可复用
2. **进程隔离**: CLI 进程的 panic 不会传播到测试进程
3. **异步限制**: `cmd()` 返回的 `Command` 是同步 API

### 改进建议

1. **异步支持**: 添加 `cmd_async()` 支持异步测试
2. **日志捕获**: 捕获 CLI 的 stderr 用于调试
3. **超时控制**: 添加默认超时防止测试挂起
4. **并行优化**: 支持同时运行多个 CLI 实例
5. **资源限制**: 添加内存/CPU 限制防止资源耗尽

### 测试覆盖

该模块本身无单元测试（太小），依赖调用方的集成测试覆盖。

建议补充：
- 二进制存在性检查测试
- 环境变量设置验证测试
- TOML 字符串转义测试
