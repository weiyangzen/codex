# landlock.rs 研究文档

## 场景与职责

`landlock.rs` 是 Codex 核心库中负责 **Linux 沙箱命令生成** 的模块。它作为 Linux 平台沙箱的适配层，将高级沙箱策略（`SandboxPolicy`）转换为 `codex-linux-sandbox` 辅助程序可理解的命令行参数。

**核心职责：**
1. **命令生成**：构建调用 `codex-linux-sandbox` 的完整命令行参数
2. **策略序列化**：将文件系统和网络沙箱策略序列化为 JSON 传递
3. **特性标志控制**：管理 `use_legacy_landlock` 和 `allow_network_for_proxy` 等特性开关
4. **进程启动协调**：与 `spawn.rs` 协作启动受沙箱保护的子进程

**在沙箱架构中的位置：**
```
┌─────────────────────────────────────────────────────────────┐
│                    Codex Core (codex-rs/core)                │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐  │
│  │  exec.rs    │───▶│ landlock.rs │───▶│   spawn.rs      │  │
│  │ (执行决策)   │    │ (命令生成)   │    │ (进程启动)       │  │
│  └─────────────┘    └─────────────┘    └─────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              codex-linux-sandbox (独立可执行文件)             │
│         (bubblewrap + seccomp 实际沙箱实现)                   │
└─────────────────────────────────────────────────────────────┘
```

## 功能点目的

### 1. 沙箱命令生成 (`spawn_command_under_linux_sandbox`)

**目的**：为给定的 shell 工具命令生成并执行受沙箱保护的进程。

**参数说明：**
| 参数 | 类型 | 说明 |
|------|------|------|
| `codex_linux_sandbox_exe` | `P: AsRef<Path>` | Linux 沙箱辅助程序路径 |
| `command` | `Vec<String>` | 实际要执行的命令及其参数 |
| `command_cwd` | `PathBuf` | 命令执行的工作目录 |
| `sandbox_policy` | `&SandboxPolicy` | 传统沙箱策略 |
| `sandbox_policy_cwd` | `&Path` | 策略解析的基准目录 |
| `use_legacy_landlock` | `bool` | 是否使用旧版 Landlock 实现 |
| `stdio_policy` | `StdioPolicy` | 标准 IO 策略（继承或重定向） |
| `network` | `Option<&NetworkProxy>` | 网络代理配置 |
| `env` | `HashMap<String, String>` | 环境变量 |

**执行流程：**
1. 将传统 `SandboxPolicy` 转换为新的 `FileSystemSandboxPolicy`
2. 将传统 `SandboxPolicy` 转换为 `NetworkSandboxPolicy`
3. 生成命令行参数
4. 调用 `spawn_child_async` 启动进程

### 2. 策略参数生成 (`create_linux_sandbox_command_args_for_policies`)

**目的**：将多种沙箱策略转换为 `codex-linux-sandbox` 的命令行参数。

**生成的参数结构：**
```
codex-linux-sandbox \
  --sandbox-policy-cwd <path> \
  --command-cwd <path> \
  --sandbox-policy <legacy_json> \
  --file-system-sandbox-policy <fs_policy_json> \
  --network-sandbox-policy <network_policy_json> \
  [--use-legacy-landlock] \
  [--allow-network-for-proxy] \
  -- \
  <actual_command...>
```

**设计考量：**
- 传统策略 JSON 用于向后兼容
- 分离的文件系统和网络策略支持增量迁移
- `--` 分隔符防止命令参数被误解析为选项

### 3. 简化参数生成 (`create_linux_sandbox_command_args`)

**目的**：用于测试场景的简化命令生成（仅传递目录和特性标志，不包含策略 JSON）。

**使用场景：**
- 单元测试验证命令行结构
- 不需要完整策略的场景

### 4. 网络代理支持 (`allow_network_for_proxy`)

**目的**：控制是否为网络代理开启网络访问。

**逻辑：**
```rust
pub(crate) fn allow_network_for_proxy(enforce_managed_network: bool) -> bool {
    // 当启用托管网络需求时，请求仅代理网络访问
    // 否则保持现有行为（限制网络）
    enforce_managed_network
}
```

这允许在严格网络限制模式下，子进程仍可通过代理访问特定网络资源。

## 具体技术实现

### 核心函数实现

```rust
pub async fn spawn_command_under_linux_sandbox<P>(
    codex_linux_sandbox_exe: P,
    command: Vec<String>,
    command_cwd: PathBuf,
    sandbox_policy: &SandboxPolicy,
    sandbox_policy_cwd: &Path,
    use_legacy_landlock: bool,
    stdio_policy: StdioPolicy,
    network: Option<&NetworkProxy>,
    env: HashMap<String, String>,
) -> std::io::Result<Child>
where
    P: AsRef<Path>,
{
    // 策略转换：传统策略 → 新策略格式
    let file_system_sandbox_policy =
        FileSystemSandboxPolicy::from_legacy_sandbox_policy(sandbox_policy, sandbox_policy_cwd);
    let network_sandbox_policy = NetworkSandboxPolicy::from(sandbox_policy);
    
    // 生成命令参数
    let args = create_linux_sandbox_command_args_for_policies(
        command,
        command_cwd.as_path(),
        sandbox_policy,
        &file_system_sandbox_policy,
        network_sandbox_policy,
        sandbox_policy_cwd,
        use_legacy_landlock,
        allow_network_for_proxy(/*enforce_managed_network*/ false),
    );
    
    // 启动进程
    spawn_child_async(SpawnChildRequest {
        program: codex_linux_sandbox_exe.as_ref().to_path_buf(),
        args,
        arg0: Some("codex-linux-sandbox"),
        cwd: command_cwd,
        network_sandbox_policy,
        network,
        stdio_policy,
        env,
    }).await
}
```

### 命令参数构建

```rust
pub fn create_linux_sandbox_command_args_for_policies(
    command: Vec<String>,
    command_cwd: &Path,
    sandbox_policy: &SandboxPolicy,
    file_system_sandbox_policy: &FileSystemSandboxPolicy,
    network_sandbox_policy: NetworkSandboxPolicy,
    sandbox_policy_cwd: &Path,
    use_legacy_landlock: bool,
    allow_network_for_proxy: bool,
) -> Vec<String> {
    // 序列化策略为 JSON
    let sandbox_policy_json = serde_json::to_string(sandbox_policy)
        .unwrap_or_else(|err| panic!("failed to serialize sandbox policy: {err}"));
    let file_system_policy_json = serde_json::to_string(file_system_sandbox_policy)
        .unwrap_or_else(|err| panic!("failed to serialize filesystem sandbox policy: {err}"));
    let network_policy_json = serde_json::to_string(&network_sandbox_policy)
        .unwrap_or_else(|err| panic!("failed to serialize network sandbox policy: {err}"));
    
    // 路径转换为字符串（必须有效 UTF-8）
    let sandbox_policy_cwd = sandbox_policy_cwd
        .to_str()
        .unwrap_or_else(|| panic!("cwd must be valid UTF-8"))
        .to_string();
    let command_cwd = command_cwd
        .to_str()
        .unwrap_or_else(|| panic!("command cwd must be valid UTF-8"))
        .to_string();
    
    // 构建参数列表
    let mut linux_cmd: Vec<String> = vec![
        "--sandbox-policy-cwd".to_string(),
        sandbox_policy_cwd,
        "--command-cwd".to_string(),
        command_cwd,
        "--sandbox-policy".to_string(),
        sandbox_policy_json,
        "--file-system-sandbox-policy".to_string(),
        file_system_policy_json,
        "--network-sandbox-policy".to_string(),
        network_policy_json,
    ];
    
    // 条件添加特性标志
    if use_legacy_landlock {
        linux_cmd.push("--use-legacy-landlock".to_string());
    }
    if allow_network_for_proxy {
        linux_cmd.push("--allow-network-for-proxy".to_string());
    }
    
    // 分隔符和实际命令
    linux_cmd.push("--".to_string());
    linux_cmd.extend(command);
    linux_cmd
}
```

### 策略类型定义（来自 codex_protocol）

```rust
// 文件系统沙箱策略
pub struct FileSystemSandboxPolicy {
    pub kind: FileSystemSandboxKind,  // Restricted | Unrestricted | ExternalSandbox
    pub entries: Vec<FileSystemSandboxEntry>,
}

pub struct FileSystemSandboxEntry {
    pub path: FileSystemPath,         // 路径或特殊路径（如 :root, :cwd）
    pub access: FileSystemAccessMode, // Read | Write | None
}

// 网络沙箱策略
pub enum NetworkSandboxPolicy {
    Restricted,  // 默认：限制网络
    Enabled,     // 允许网络
}
```

## 关键代码路径与文件引用

### 内部调用关系

```
landlock.rs
├── spawn_command_under_linux_sandbox
│   ├── FileSystemSandboxPolicy::from_legacy_sandbox_policy
│   ├── NetworkSandboxPolicy::from
│   ├── create_linux_sandbox_command_args_for_policies
│   │   ├── serde_json::to_string(sandbox_policy)
│   │   ├── serde_json::to_string(file_system_sandbox_policy)
│   │   └── serde_json::to_string(network_sandbox_policy)
│   └── spawn_child_async (from spawn.rs)
└── create_linux_sandbox_command_args (测试用)
```

### 跨模块依赖

**上游调用方：**
| 调用方 | 场景 |
|--------|------|
| `exec.rs` / `unified_exec.rs` | 执行 shell 工具时启动沙箱进程 |

**下游依赖：**
| 被调用方 | 用途 |
|----------|------|
| `spawn.rs::spawn_child_async` | 实际启动子进程 |
| `codex_protocol::permissions::*` | 策略类型定义 |
| `codex_network_proxy::NetworkProxy` | 网络代理配置 |

### 相关文件

| 文件路径 | 关系 |
|----------|------|
| `/home/sansha/Github/codex/codex-rs/core/src/spawn.rs` | 进程启动实现 |
| `/home/sansha/Github/codex/codex-rs/core/src/exec.rs` | 执行层，调用 landlock |
| `/home/sansha/Github/codex/codex-rs/protocol/src/permissions.rs` | 策略类型定义 |
| `/home/sansha/Github/codex/codex-rs/network_proxy/src/lib.rs` | NetworkProxy 定义 |
| `docs/linux_sandbox.md` | Linux 沙箱文档 |

## 依赖与外部交互

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_protocol` | `SandboxPolicy`, `FileSystemSandboxPolicy`, `NetworkSandboxPolicy` |
| `codex_network_proxy` | `NetworkProxy` 类型 |
| `serde_json` | 策略序列化 |
| `tokio` | `Child` 类型（异步进程） |
| `std::path` | 路径处理 |

### 环境变量

本模块不直接操作环境变量，但 `spawn_child_async` 会设置：
- `CODEX_SANDBOX_NETWORK_DISABLED` - 当网络受限时设置
- `CODEX_SANDBOX` - 设置为 "seatbelt"（Linux 上可能不同）

### 外部可执行文件

| 可执行文件 | 用途 | 来源 |
|------------|------|------|
| `codex-linux-sandbox` | Linux 沙箱辅助程序 | 独立 crate 构建 |

`codex-linux-sandbox` 内部实现：
- 默认使用 `bubblewrap` 进行文件系统隔离
- 使用 `seccomp` 进行系统调用过滤
- 可选使用 `landlock` 进行额外限制

## 风险、边界与改进建议

### 已知风险

1. **路径编码假设**
   ```rust
   let sandbox_policy_cwd = sandbox_policy_cwd
       .to_str()
       .unwrap_or_else(|| panic!("cwd must be valid UTF-8"));
   ```
   - **风险**：非 UTF-8 路径会导致 panic
   - **场景**：某些 Linux 系统可能使用非 UTF-8 文件名
   - **建议**：考虑使用 `to_string_lossy` 或支持 OS 字符串

2. **JSON 序列化 panic**
   ```rust
   serde_json::to_string(sandbox_policy)
       .unwrap_or_else(|err| panic!("failed to serialize sandbox policy: {err}"));
   ```
   - **风险**：理论上策略结构应始终可序列化，但如果包含不可序列化类型（如 `std::path::PathBuf` 在某些情况下）会 panic
   - **建议**：使用 `expect` 替代 `unwrap_or_else` + panic，或返回 Result

3. **命令注入风险**
   - 用户提供的 `command` 直接附加到参数列表
   - **缓解**：`--` 分隔符防止参数被解析为选项
   - **注意**：这依赖 `codex-linux-sandbox` 正确处理 `--`

4. **策略一致性**
   - 同时传递传统策略和新策略，可能导致不一致
   - **现状**：辅助程序需要同时处理两者
   - **建议**：明确迁移路径，最终只传递新策略

### 边界情况

| 边界情况 | 处理 | 说明 |
|----------|------|------|
| 空命令 | ⚠️ | 未显式检查，依赖下游处理 |
| 非 UTF-8 路径 | ❌ | panic |
| 非常大的策略 JSON | ⚠️ | 可能触及命令行长度限制 |
| 网络代理为 None | ✅ | 正常处理 |
| 相对路径 | ✅ | 转换为字符串传递 |

### 改进建议

1. **错误处理改进**
   ```rust
   // 当前：panic
   // 建议：返回 Result
   pub fn create_linux_sandbox_command_args_for_policies(...) -> Result<Vec<String>, SandboxError> {
       let sandbox_policy_cwd = sandbox_policy_cwd
           .to_str()
           .ok_or(SandboxError::InvalidPath)?;
       // ...
   }
   ```

2. **命令行长度检查**
   ```rust
   // Linux 通常限制为 2MB (ARG_MAX)，但保守起见应检查
   const MAX_CMD_LEN: usize = 128 * 1024;
   if args.iter().map(|s| s.len()).sum::<usize>() > MAX_CMD_LEN {
       return Err(SandboxError::CommandTooLong);
   }
   ```

3. **策略验证**
   ```rust
   // 在序列化前验证策略一致性
   file_system_sandbox_policy.validate()?;
   ```

4. **日志增强**
   ```rust
   tracing::debug!(
       sandbox_exe = %codex_linux_sandbox_exe.as_ref().display(),
       command = ?command,
       "spawning sandboxed process"
   );
   ```

5. **支持 OS 字符串**
   - 考虑使用 `std::ffi::OsString` 传递参数
   - 需要 `codex-linux-sandbox` 支持 OS 字符串参数

### 测试覆盖

当前测试（`landlock_tests.rs`）：
- ✅ 验证 `--use-legacy-landlock` 标志传递
- ✅ 验证 `--allow-network-for-proxy` 标志传递
- ✅ 验证策略 JSON 参数存在且非空
- ✅ 验证 `--command-cwd` 正确传递

**建议增加的测试：**
1. 非 UTF-8 路径处理（当前会 panic）
2. 非常大的策略 JSON 处理
3. 特殊字符命令参数（含 `--` 的情况）
4. 错误路径测试（模拟序列化失败）

### 维护注意事项

1. **与 codex-linux-sandbox 的兼容性**：命令行接口变更需要同步更新
2. **策略迁移**：关注从传统策略到新策略的完整迁移进度
3. **平台差异**：此模块仅用于 Linux，macOS 使用 `seatbelt.rs`
4. **性能考虑**：JSON 序列化在每次执行时都发生，可考虑缓存（但策略可能动态变化）
