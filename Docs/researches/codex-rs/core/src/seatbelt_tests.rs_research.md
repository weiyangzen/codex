# seatbelt_tests.rs 深度研究文档

## 场景与职责

`seatbelt_tests.rs` 是 Codex 项目中 macOS Seatbelt 沙箱机制的综合测试模块。它位于 `codex-rs/core/src/` 目录下，负责验证 macOS 平台沙箱策略生成的正确性和安全性。这些测试确保 Codex 在受限环境中执行外部命令时，能够正确地应用文件系统访问控制、网络策略和权限扩展。

该测试文件是 Codex 安全架构的关键组成部分，直接验证 `seatbelt.rs` 中实现的沙箱策略生成逻辑，确保沙箱配置能够：
- 限制文件系统访问范围（读/写权限）
- 控制网络访问能力
- 保护敏感目录（如 `.git` 和 `.codex`）免受未授权写入
- 正确集成代理网络配置

## 功能点目的

### 1. 基础策略验证
测试 `MACOS_SEATBELT_BASE_POLICY` 是否包含必要的系统调用权限，特别是 CPU 信息查询所需的 sysctl：
- `machdep.cpu.brand_string` - 用于获取 CPU 品牌信息
- `hw.model` - 用于获取硬件模型信息

### 2. 网络策略测试
验证动态网络策略生成的正确性：
- 代理端口白名单机制
- 本地绑定权限控制
- Unix Domain Socket 访问控制
- 受限网络与完全网络模式的切换

### 3. 文件系统访问控制测试
- 验证不可读路径从完全磁盘访问中被排除
- 验证可读根目录中的不可读子路径被正确处理
- 确保 `.git` 和 `.codex` 目录在可写根目录中被自动设为只读

### 4. macOS 权限扩展测试
验证 Seatbelt 配置文件扩展（如自动化权限、偏好设置访问、日历访问等）的正确集成。

### 5. 安全边界测试
- 验证即使授予了特定 bundle ID 的自动化权限，`lsopen` 仍然被禁止
- 确保沙箱策略能够阻止对敏感配置文件的写入

## 具体技术实现

### 关键测试数据结构

```rust
// 代理策略输入参数
struct ProxyPolicyInputs {
    ports: Vec<u16>,                    // 允许的代理端口列表
    has_proxy_config: bool,             // 是否配置了代理
    allow_local_binding: bool,          // 是否允许本地绑定
    unix_domain_socket_policy: UnixDomainSocketPolicy,  // Unix socket 策略
}

// Unix Domain Socket 策略枚举
enum UnixDomainSocketPolicy {
    AllowAll,
    Restricted { allowed: Vec<AbsolutePathBuf> },
}
```

### 核心测试辅助函数

**`assert_seatbelt_denied`** - 验证 Seatbelt 是否正确地拒绝了操作：
```rust
fn assert_seatbelt_denied(stderr: &[u8], path: &Path) {
    let stderr = String::from_utf8_lossy(stderr);
    let expected = format!("bash: {}: Operation not permitted\n", path.display());
    assert!(
        stderr == expected
            || stderr.contains("sandbox-exec: sandbox_apply: Operation not permitted"),
        "unexpected stderr: {stderr}"
    );
}
```

**`seatbelt_policy_arg`** - 从生成的参数中提取策略文本：
```rust
fn seatbelt_policy_arg(args: &[String]) -> &str {
    let policy_index = args
        .iter()
        .position(|arg| arg == "-p")
        .expect("seatbelt args should include -p");
    args.get(policy_index + 1)
        .expect("seatbelt args should include policy text")
}
```

### 关键测试用例分析

#### 1. 网络策略路由测试 (`create_seatbelt_args_routes_network_through_proxy_ports`)
验证当配置代理端口时，策略是否正确限制网络出口到指定的本地端口：
- 生成 `(allow network-outbound (remote ip "localhost:PORT"))` 规则
- 确保不生成全局 `(allow network-outbound)` 规则
- 验证本地绑定规则的有条件生成

#### 2. 不可读路径排除测试
验证 `FileSystemSandboxPolicy` 中标记为 `None` 访问权限的路径：
- 从完全磁盘读取访问中排除
- 从完全磁盘写入访问中排除
- 使用 `require-not` 和 `subpath` 组合实现负向权限控制

#### 3. `.git` 和 `.codex` 保护测试 (`create_seatbelt_args_with_read_only_git_and_codex_subpaths`)
这是一个综合性安全测试，验证：
- 当可写根目录包含 `.git` 或 `.codex` 子目录时，这些子目录自动变为只读
- 使用 `require-all` 和 `require-not` 组合实现细粒度权限控制
- 实际执行 Seatbelt 命令验证策略效果

测试结构使用 `PopulatedTmp` 辅助结构创建测试环境：
```rust
struct PopulatedTmp {
    vulnerable_root: PathBuf,           // 包含 .git 和 .codex 的目录
    vulnerable_root_canonical: PathBuf,
    dot_git_canonical: PathBuf,
    dot_codex_canonical: PathBuf,
    empty_root: PathBuf,                // 不包含敏感目录的目录
    empty_root_canonical: PathBuf,
}
```

#### 4. Git 指针文件测试 (`create_seatbelt_args_with_read_only_git_pointer_file`)
验证当 `.git` 是一个指向外部 git 目录的指针文件时，沙箱是否正确保护：
- 指针文件本身不可写入
- 指针指向的实际 git 目录也不可写入

## 关键代码路径与文件引用

### 主要依赖关系

```
seatbelt_tests.rs
├── seatbelt.rs (被测试的主要实现)
│   ├── MACOS_SEATBELT_BASE_POLICY (内联策略模板)
│   ├── create_seatbelt_command_args()
│   ├── dynamic_network_policy()
│   └── spawn_command_under_seatbelt()
├── seatbelt_permissions.rs (权限扩展)
│   ├── MacOsSeatbeltProfileExtensions
│   └── build_seatbelt_extensions()
├── protocol module
│   ├── SandboxPolicy
│   └── ReadOnlyAccess
└── codex_protocol::permissions
    ├── FileSystemSandboxPolicy
    ├── FileSystemAccessMode
    └── NetworkSandboxPolicy
```

### 策略文件模板
测试验证的策略模板通过 `include_str!` 嵌入：
- `seatbelt_base_policy.sbpl` - 基础沙箱策略
- `seatbelt_network_policy.sbpl` - 网络策略模板
- `restricted_read_only_platform_defaults.sbpl` - 平台默认只读策略

### 执行路径
测试通过 `/usr/bin/sandbox-exec` 实际执行验证：
```rust
let output = Command::new(MACOS_PATH_TO_SEATBELT_EXECUTABLE)
    .args(&args)
    .current_dir(&cwd)
    .output()
    .expect("execute seatbelt command");
```

## 依赖与外部交互

### 外部系统依赖
1. **macOS `sandbox-exec`** - 位于 `/usr/bin/sandbox-exec`，是实际的沙箱执行工具
2. **Git** - 用于创建测试用的 git 仓库结构
3. **标准 Shell** (`/bin/bash`, `/bin/zsh`, `/bin/sh`) - 用于执行测试命令

### 内部模块依赖
| 模块 | 用途 |
|------|------|
| `seatbelt.rs` | 被测试的沙箱策略生成实现 |
| `seatbelt_permissions.rs` | macOS 特定权限扩展 |
| `protocol` | `SandboxPolicy` 等策略类型定义 |
| `codex_protocol::permissions` | 文件系统和网络权限类型 |
| `codex_utils_absolute_path::AbsolutePathBuf` | 绝对路径处理 |

### 测试框架
- `pretty_assertions::assert_eq` - 提供美观的差异输出
- `tempfile::TempDir` - 创建临时测试目录
- 标准 Rust 测试框架 (`#[test]`)

## 风险、边界与改进建议

### 已知风险

1. **平台限制**
   - 所有测试仅在 macOS 上有效，其他平台会被条件编译排除
   - 测试需要实际的 `sandbox-exec` 工具，在某些 CI 环境可能不可用

2. **环境依赖**
   - `populate_tmpdir` 函数依赖系统 `git` 命令
   - 测试需要写入临时文件系统

3. **测试执行时间**
   - 部分测试实际执行 Seatbelt 命令，可能比纯单元测试慢
   - `bundle_id_automation_keeps_lsopen_denied` 测试使用 Python ctypes 验证沙箱状态

### 边界情况

1. **路径规范化**
   - `normalize_path_for_sandbox` 拒绝相对路径
   - 测试验证符号链接和复杂路径结构的处理

2. **代理配置边界**
   - 代理端口为空但有代理配置时的回退行为
   - 托管网络要求与代理配置的交互

3. **并发安全**
   - `getpwuid_r` 的使用避免 `getpwuid` 的线程安全问题（在注释中提到 musl 静态构建的竞态条件）

### 改进建议

1. **测试覆盖率扩展**
   - 增加对 `MacOsSeatbeltProfileExtensions` 所有权限类型的完整测试
   - 添加更多边界条件测试（如极长路径、特殊字符路径）

2. **错误消息改进**
   - 当前测试失败时的错误消息可以包含更多上下文信息
   - 考虑添加策略文本的 diff 输出

3. **性能优化**
   - 考虑将部分集成测试转换为纯单元测试，减少对 `sandbox-exec` 的依赖
   - 使用模拟对象测试策略生成逻辑

4. **跨平台抽象**
   - 虽然 Seatbelt 是 macOS 特有，但可以考虑抽象出通用的沙箱测试接口
   - 便于未来其他平台沙箱机制的测试

5. **文档增强**
   - 添加更多关于 Seatbelt 策略语法的内联文档
   - 解释 `require-all`/`require-not` 等复杂策略结构的用途

### 安全考虑

1. **测试本身的安全性**
   - 测试创建了真实的 git 仓库和文件，确保清理逻辑正确
   - `PopulatedTmp` 结构使用 `tempfile` 确保临时目录被清理

2. **沙箱逃逸防护**
   - 测试验证了敏感目录的保护，但应定期审计新添加的测试
   - 确保测试不会意外地放宽沙箱限制
