# seatbelt.rs 研究文档

## 场景与职责

本文件是 Codex **macOS Seatbelt 沙盒的实现核心**，负责构建和执行 Seatbelt 沙盒策略。它将高层的 `SandboxPolicy` 转换为低级的 Seatbelt Profile Language (SBPL) 策略，并通过 `sandbox-exec` 命令启动受保护的进程。

**核心职责**：
- 将 `SandboxPolicy` 转换为 Seatbelt SBPL 策略
- 支持文件系统访问控制（读/写根目录）
- 支持网络访问控制（代理、Unix socket）
- 支持 macOS 特定权限扩展（Contacts、Calendar、Automation 等）
- 安全地执行 `sandbox-exec` 命令

## 功能点目的

### 1. 进程启动 (`spawn_command_under_seatbelt`)
在 Seatbelt 沙盒中异步启动子进程：
- 构建完整的 `sandbox-exec` 命令行
- 设置环境变量（`CODEX_SANDBOX=seatbelt`）
- 通过 `spawn_child_async` 执行

### 2. 策略生成 (`create_seatbelt_command_args`)
将高层策略转换为 SBPL 策略字符串：
- 合并基础策略、文件策略、网络策略
- 处理平台默认值
- 应用权限扩展

### 3. 网络策略 (`dynamic_network_policy`)
根据网络配置生成动态网络规则：
- 代理环境变量解析
- 本地回环绑定控制
- Unix domain socket 访问控制

### 4. 文件系统策略 (`build_seatbelt_access_policy`)
构建文件访问规则：
- 可读/可写根目录参数化
- 排除子路径支持（负向权限）
- 全磁盘访问优化

## 具体技术实现

### 策略文件嵌入

```rust
const MACOS_SEATBELT_BASE_POLICY: &str = include_str!("seatbelt_base_policy.sbpl");
const MACOS_SEATBELT_NETWORK_POLICY: &str = include_str!("seatbelt_network_policy.sbpl");
const MACOS_RESTRICTED_READ_ONLY_PLATFORM_DEFAULTS: &str = 
    include_str!("restricted_read_only_platform_defaults.sbpl");
```

### 核心函数流程

#### `spawn_command_under_seatbelt`
```rust
pub async fn spawn_command_under_seatbelt(
    command: Vec<String>,
    command_cwd: PathBuf,
    sandbox_policy: &SandboxPolicy,
    sandbox_policy_cwd: &Path,
    stdio_policy: StdioPolicy,
    network: Option<&NetworkProxy>,
    mut env: HashMap<String, String>,
) -> std::io::Result<Child>
```

**执行流程**：
1. 构建 Seatbelt 命令参数 (`create_seatbelt_command_args`)
2. 设置 `CODEX_SANDBOX=seatbelt` 环境变量
3. 使用固定路径 `/usr/bin/sandbox-exec` 执行
4. 通过 `spawn_child_async` 启动进程

#### `create_seatbelt_command_args_for_policies_with_extensions`
```rust
pub fn create_seatbelt_command_args_for_policies_with_extensions(
    command: Vec<String>,
    file_system_sandbox_policy: &FileSystemSandboxPolicy,
    network_sandbox_policy: NetworkSandboxPolicy,
    sandbox_policy_cwd: &Path,
    enforce_managed_network: bool,
    network: Option<&NetworkProxy>,
    extensions: Option<&MacOsSeatbeltProfileExtensions>,
) -> Vec<String>
```

**策略构建流程**：
```
1. 文件写入策略
   ├── 全磁盘写入？→ (allow file-write* (regex #"^/"))
   └── 受限写入？→ 构建参数化的 subpath 规则

2. 文件读取策略
   ├── 全磁盘读取？→ (allow file-read*)
   └── 受限读取？→ 构建参数化的 subpath 规则

3. 网络策略
   ├── 代理配置？→ 允许特定 localhost 端口
   ├── Unix socket？→ 允许特定路径
   └── 默认 → 允许/拒绝网络访问

4. 权限扩展
   └── 从 MacOsSeatbeltProfileExtensions 构建

5. 组装完整策略
   └── base + read + write + network + platform_defaults + extensions
```

### 网络策略详解

#### 代理端口解析
```rust
fn proxy_loopback_ports_from_env(env: &HashMap<String, String>) -> Vec<u16> {
    // 解析 HTTP_PROXY、HTTPS_PROXY、ALL_PROXY 等环境变量
    // 提取 localhost/127.0.0.1/::1 的端口号
    // 支持 http://、socks5:// 等协议
}
```

#### Unix Socket 策略
```rust
fn unix_socket_policy(proxy: &ProxyPolicyInputs) -> String {
    if AllowAll {
        // 允许所有 Unix socket
        "(allow network-bind (local unix-socket))"
        "(allow network-outbound (remote unix-socket))"
    } else {
        // 允许特定路径（参数化）
        "(allow network-bind (local unix-socket (subpath (param "UNIX_SOCKET_PATH_0"))))"
    }
}
```

### 文件系统策略构建

#### `build_seatbelt_access_policy`
```rust
fn build_seatbelt_access_policy(
    action: &str,           // "file-read*" 或 "file-write*"
    param_prefix: &str,     // "READABLE_ROOT" 或 "WRITABLE_ROOT"
    roots: Vec<SeatbeltAccessRoot>,
) -> (String, Vec<(String, PathBuf)>)
```

**示例输出**：
```lisp
(allow file-write*
  (require-all 
    (subpath (param "WRITABLE_ROOT_0"))
    (require-not (subpath (param "WRITABLE_ROOT_0_RO_0")))
  )
)
```

### 安全考虑

#### 固定可执行路径
```rust
pub const MACOS_PATH_TO_SEATBELT_EXECUTABLE: &str = "/usr/bin/sandbox-exec";
```
- 防止 PATH 注入攻击
- 如果 `/usr/bin/sandbox-exec` 被篡改，攻击者已拥有 root 权限

#### 路径归一化
```rust
fn normalize_path_for_sandbox(path: &Path) -> Option<AbsolutePathBuf> {
    // 拒绝相对路径
    // 尝试 canonicalize，失败则使用绝对路径
}
```

## 关键代码路径与文件引用

### 调用关系
```
exec.rs (process_exec_tool_call)
  └── sandboxing/mod.rs
        └── execute_env
              └── spawn_command_under_seatbelt (macOS only)

unified_exec/process.rs
  └── spawn_command_under_seatbelt
```

### 依赖关系
```rust
// 输入
use crate::protocol::SandboxPolicy;
use crate::seatbelt_permissions::MacOsSeatbeltProfileExtensions;
use codex_protocol::permissions::{FileSystemSandboxPolicy, NetworkSandboxPolicy};
use codex_network_proxy::NetworkProxy;

// 输出
use tokio::process::Child;
```

### 相关文件
- `seatbelt_base_policy.sbpl` - 基础策略（deny default）
- `seatbelt_network_policy.sbpl` - 网络访问规则
- `restricted_read_only_platform_defaults.sbpl` - 平台默认值
- `seatbelt_permissions.rs` - 权限扩展构建
- `seatbelt_tests.rs` - 单元测试

## 依赖与外部交互

### 系统依赖
| 依赖 | 用途 |
|-----|------|
| `/usr/bin/sandbox-exec` | macOS Seatbelt 沙盒执行器 |
| `libc` | `confstr` 系统调用 |
| `tokio::process` | 异步进程管理 |

### 外部配置
- **环境变量**: `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, `NO_PROXY`
- **系统路径**: `DARWIN_USER_CACHE_DIR`（通过 `confstr` 获取）

### 网络代理集成
```rust
use codex_network_proxy::{
    NetworkProxy, PROXY_URL_ENV_KEYS, 
    has_proxy_url_env_vars, proxy_url_env_value
};
```

## 风险、边界与改进建议

### 潜在风险

1. **策略注入风险**
   - 用户提供的 writable_roots 直接嵌入策略
   - 需要确保路径不包含 SBPL 特殊字符

2. **TOCTOU 竞争**
   - 路径归一化和实际访问之间可能存在竞争
   - 符号链接可能在检查后被替换

3. **网络策略绕过**
   - 代理配置解析可能不完整
   - 某些网络访问可能未完全限制

4. **内存消耗**
   - 策略字符串可能很大（包含多个 subpath 规则）
   - 大量权限扩展时可能超出命令行长度限制

### 边界限制

1. **macOS 专属**
   - 仅适用于 macOS 平台
   - 其他平台使用不同沙盒机制

2. **sandbox-exec 限制**
   - 需要系统完整性保护（SIP）未禁用
   - 某些系统调用可能无法完全限制

3. **策略复杂性**
   - SBPL 语法复杂，容易出错
   - 调试困难，需要手动检查生成的策略

### 改进建议

1. **安全加固**
   ```rust
   // 建议：验证路径字符
   fn validate_path_for_sandbox(path: &str) -> Result<(), Error> {
       if path.contains('"') || path.contains('\\') {
           bail!("Invalid characters in sandbox path");
       }
       Ok(())
   }
   ```

2. **策略验证**
   - 添加 `sandbox-exec -v` 验证生成的策略
   - 提供调试模式输出完整策略

3. **性能优化**
   - 缓存生成的策略（相同配置复用）
   - 压缩参数名称减少命令行长度

4. **可观测性**
   ```rust
   // 建议：记录策略摘要
   tracing::debug!(
       policy_hash = %sha256::digest(&full_policy),
       num_rules = %policy_sections.len(),
       "Generated Seatbelt policy"
   );
   ```

5. **错误处理增强**
   - 区分策略生成错误和沙盒执行错误
   - 提供用户友好的错误消息

6. **测试增强**
   - 添加策略生成快照测试
   - 添加实际沙盒执行测试（在 CI 中）
   - 测试各种边缘情况（超长路径、特殊字符）

7. **文档完善**
   - 提供 SBPL 策略调试指南
   - 记录常见问题和解决方案
