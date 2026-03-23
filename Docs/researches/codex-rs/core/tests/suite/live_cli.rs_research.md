# live_cli.rs 研究文档

## 场景与职责

`live_cli.rs` 是 Codex Rust 核心库的**实时集成测试**（Live Integration Tests），专注于验证 Codex CLI 二进制文件在真实环境中的行为。与使用 Mock 服务器的单元测试不同，这些测试直接调用编译后的 `codex-rs` 二进制文件，并与真实的 OpenAI API 交互。

### 核心职责
1. **验证 CLI 端到端功能**：确保编译后的二进制文件能正常工作
2. **测试真实 API 集成**：与真实的 OpenAI `/v1/responses` 端点交互
3. **验证工具调用链**：测试模型生成工具调用 -> CLI 执行 -> 结果返回的完整流程
4. **提供冒烟测试**：快速验证核心功能在真实环境中是否可用

### 重要说明
所有测试都被标记为 `#[ignore]`，默认不运行，因为：
1. 需要有效的 `OPENAI_API_KEY` 环境变量
2. 调用真实 API 产生费用
3. 测试执行时间依赖于 API 响应时间
4. 需要网络连接

---

## 功能点目的

### 1. 文件创建测试 (`live_create_file_hello_txt`)
- **目的**：验证模型可以通过 `apply_patch` 工具创建文件
- **测试场景**：
  - 提示词："Use the shell tool with the apply_patch command to create a file named hello.txt containing the text 'hello'."
  - 验证文件 `hello.txt` 被创建
  - 验证文件内容包含 "hello"

### 2. 工作目录打印测试 (`live_print_working_directory`)
- **目的**：验证模型可以执行 shell 命令并返回结果
- **测试场景**：
  - 提示词："Print the current working directory using the shell function."
  - 验证输出包含当前工作目录路径

---

## 具体技术实现

### 测试基础设施

#### API Key 获取

```rust
fn require_api_key() -> String {
    std::env::var("OPENAI_API_KEY")
        .expect("OPENAI_API_KEY env var not set — skip running live tests")
}
```

#### CLI 执行辅助函数

```rust
fn run_live(prompt: &str) -> (assert_cmd::assert::Assert, TempDir) {
    let dir = TempDir::new().unwrap();
    
    // 构建命令
    let mut cmd = Command::new(codex_utils_cargo_bin::cargo_bin("codex-rs").unwrap());
    cmd.current_dir(dir.path());
    cmd.env("OPENAI_API_KEY", require_api_key());
    
    // 配置参数
    cmd.arg("--allow-no-git-exec")
        .arg("-v")
        .arg("--")
        .arg(prompt);
    
    // 设置 stdio
    cmd.stdin(Stdio::piped());
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());
    
    // 启动进程
    let mut child = cmd.spawn().expect("failed to spawn codex-rs");
    
    // 发送终止换行符
    child.stdin.as_mut().unwrap().write_all(b"\n").unwrap();
    
    // Tee 输出到终端和缓冲区
    let stdout_handle = tee(child.stdout.take().unwrap(), std::io::stdout());
    let stderr_handle = tee(child.stderr.take().unwrap(), std::io::stderr());
    
    // 等待完成
    let status = child.wait().expect("failed to wait on child");
    let stdout = stdout_handle.join().unwrap();
    let stderr = stderr_handle.join().unwrap();
    
    // 构造 Assert 对象
    let output = std::process::Output { status, stdout, stderr };
    (output.assert(), dir)
}
```

#### Tee 辅助函数

```rust
fn tee<R: Read + Send + 'static>(
    mut reader: R,
    mut writer: impl Write + Send + 'static,
) -> thread::JoinHandle<Vec<u8>> {
    thread::spawn(move || {
        let mut buf = Vec::new();
        let mut chunk = [0u8; 4096];
        loop {
            match reader.read(&mut chunk) {
                Ok(0) => break,
                Ok(n) => {
                    writer.write_all(&chunk[..n]).ok();
                    writer.flush().ok();
                    buf.extend_from_slice(&chunk[..n]);
                }
                Err(_) => break,
            }
        }
        buf
    })
}
```

### 命令行参数

```bash
codex-rs \
  --allow-no-git-exec \  # 允许在非 git 仓库中执行
  -v \                    # 启用详细输出
  -- \                    # 参数分隔符
  "prompt"               # 用户提示词
```

### 测试执行流程

1. **环境准备**：
   - 创建临时目录作为工作目录
   - 获取 `OPENAI_API_KEY`

2. **进程启动**：
   - 启动 `codex-rs` 二进制文件
   - 通过 stdin 发送提示词
   - 发送换行符触发执行

3. **输出捕获**：
   - 使用 tee 模式同时输出到终端和缓冲区
   - 支持实时查看执行进度

4. **结果验证**：
   - 验证进程退出状态
   - 验证文件系统变更
   - 验证输出内容

---

## 关键代码路径与文件引用

### 测试文件
- **当前文件**：`codex-rs/core/tests/suite/live_cli.rs` (148 行)

### CLI 实现
- **`codex-rs/cli/`**：Codex CLI 实现（如果存在独立 crate）
- **`codex-rs/core/src/main.rs`** 或 **`codex-rs/core/src/bin/codex.rs`**：CLI 入口点

### 依赖的工具
- **`codex_utils_cargo_bin`**：定位编译后的二进制文件

### 外部依赖
- **`assert_cmd`**：CLI 测试断言
- **`predicates`**：谓词匹配
- **`tempfile`**：临时目录管理

---

## 依赖与外部交互

### 外部依赖
1. **OpenAI API**：需要有效的 API key 和网络连接
2. **编译后的二进制文件**：`codex-rs` 必须已编译
3. **Node.js**：某些功能可能需要 Node.js（如 js_repl）

### 内部依赖
1. **codex_core**：核心库功能
2. **codex_utils_cargo_bin**：二进制文件定位

### 环境变量
- `OPENAI_API_KEY`：OpenAI API 密钥（必需）

---

## 风险、边界与改进建议

### 已知风险

1. **费用风险**：
   - 每次测试调用真实 API，产生费用
   - 模型可能执行意外操作（如循环调用）

2. **不稳定性**：
   - 依赖网络连接和 API 可用性
   - 模型响应可能有差异，导致测试不稳定

3. **执行时间**：
   - 测试执行时间取决于 API 响应时间
   - 可能比单元测试慢几个数量级

4. **环境依赖**：
   - 需要特定的环境变量
   - 需要编译后的二进制文件

### 边界情况

1. **API 限制**：
   - 可能触发速率限制
   - 建议增加重试逻辑

2. **模型行为变化**：
   - 模型更新可能导致行为变化
   - 测试可能需要相应调整

3. **超时处理**：
   - 当前实现没有显式超时
   - 长时间运行的测试可能挂起

### 改进建议

1. **增加测试覆盖**：
   - 测试更多工具（shell、apply_patch、js_repl 等）
   - 测试错误处理（无效输入、权限错误等）
   - 测试多轮对话

2. **稳定性改进**：
   - 增加超时机制
   - 增加重试逻辑
   - 使用更确定性的提示词

3. **成本优化**：
   - 使用 cheaper 模型进行冒烟测试
   - 增加测试选择机制（只运行特定测试）

4. **CI 集成**：
   - 配置定期运行（如每日一次）
   - 在发布前运行完整测试
   - 使用环境变量控制是否运行

5. **文档改进**：
   - 提供运行测试的详细指南
   - 说明预期费用
   - 提供故障排除指南

### 运行方式

```bash
# 设置 API key
export OPENAI_API_KEY="sk-..."

# 运行被忽略的测试
cargo test --test live_cli -- --ignored

# 运行特定测试
cargo test --test live_cli live_create_file_hello_txt -- --ignored --exact
```
