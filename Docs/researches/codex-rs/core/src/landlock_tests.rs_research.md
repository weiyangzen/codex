# landlock_tests.rs 研究文档

## 场景与职责

`landlock_tests.rs` 是 `codex-rs/core/src/landlock.rs` 的配套单元测试文件，负责验证 Linux 沙箱命令生成功能的正确性。该测试文件确保 `landlock.rs` 模块能够正确构建调用 `codex-linux-sandbox` 辅助程序的命令行参数。

**核心测试场景：**
1. 验证 `--use-legacy-landlock` 标志在请求时正确传递
2. 验证 `--allow-network-for-proxy` 标志在请求时正确传递
3. 验证分离的策略参数（文件系统和网络）正确序列化并传递
4. 验证命令行参数顺序和格式符合预期

**测试范围限制：**
- 仅测试命令行参数生成，不测试实际进程启动
- 使用简化测试函数 `create_linux_sandbox_command_args` 和完整函数 `create_linux_sandbox_command_args_for_policies`
- 不涉及与 `codex-linux-sandbox` 可执行文件的实际交互

## 功能点目的

### 1. 旧版 Landlock 标志测试 (`legacy_landlock_flag_is_included_when_requested`)

**目的**：验证 `use_legacy_landlock` 参数正确映射到 `--use-legacy-landlock` 命令行标志。

**测试逻辑：**
```rust
// 默认情况：不包含标志
let default_bwrap = create_linux_sandbox_command_args(..., false, false);
assert!(!default_bwrap.contains(&"--use-legacy-landlock".to_string()));

// 启用情况：包含标志
let legacy_landlock = create_linux_sandbox_command_args(..., true, false);
assert!(legacy_landlock.contains(&"--use-legacy-landlock".to_string()));
```

**业务背景**：
- Landlock 是 Linux 内核的安全模块，用于文件系统访问控制
- 项目可能同时支持新版和旧版 Landlock API
- 通过命令行标志让辅助程序选择使用哪个版本

### 2. 代理网络标志测试 (`proxy_flag_is_included_when_requested`)

**目的**：验证 `allow_network_for_proxy` 参数正确映射到 `--allow-network-for-proxy` 命令行标志。

**测试逻辑：**
```rust
let args = create_linux_sandbox_command_args(..., true, true);
assert!(args.contains(&"--allow-network-for-proxy".to_string()));
```

**业务背景**：
- 当启用托管网络需求时，允许沙箱进程通过代理访问网络
- 这是严格网络限制模式下的例外机制

### 3. 分离策略参数测试 (`split_policy_flags_are_included`)

**目的**：验证新的分离策略参数（文件系统和网络）正确传递。

**测试逻辑：**
```rust
let args = create_linux_sandbox_command_args_for_policies(
    command,
    command_cwd,
    &sandbox_policy,
    &file_system_sandbox_policy,
    network_sandbox_policy,
    cwd,
    true,  // use_legacy_landlock
    false, // allow_network_for_proxy
);

// 验证 --file-system-sandbox-policy 存在且值非空
assert!(args.windows(2).any(|w| w[0] == "--file-system-sandbox-policy" && !w[1].is_empty()));

// 验证 --network-sandbox-policy 值为 "restricted"
assert!(args.windows(2).any(|w| w[0] == "--network-sandbox-policy" && w[1] == "\"restricted\""));

// 验证 --command-cwd 正确设置
assert!(args.windows(2).any(|w| w[0] == "--command-cwd" && w[1] == "/tmp/link"));
```

**业务背景**：
- 传统 `SandboxPolicy` 正在被新的分离策略替代
- 分离策略提供更细粒度的控制
- 同时传递新旧策略以支持向后兼容

### 4. 代理网络条件测试 (`proxy_network_requires_managed_requirements`)

**目的**：验证 `allow_network_for_proxy` 函数的正确逻辑。

**测试逻辑：**
```rust
assert_eq!(allow_network_for_proxy(false), false);
assert_eq!(allow_network_for_proxy(true), true);
```

**业务背景**：
- 网络代理访问权限仅在启用托管网络需求时授予
- 这是安全设计：默认拒绝，显式允许

## 具体技术实现

### 测试辅助函数使用

测试使用两个不同层级的函数：

```rust
// 简化版（仅测试目录和标志）
pub(crate) fn create_linux_sandbox_command_args(
    command: Vec<String>,
    command_cwd: &Path,
    sandbox_policy_cwd: &Path,
    use_legacy_landlock: bool,
    allow_network_for_proxy: bool,
) -> Vec<String>

// 完整版（包含策略序列化）
pub fn create_linux_sandbox_command_args_for_policies(
    command: Vec<String>,
    command_cwd: &Path,
    sandbox_policy: &SandboxPolicy,
    file_system_sandbox_policy: &FileSystemSandboxPolicy,
    network_sandbox_policy: NetworkSandboxPolicy,
    sandbox_policy_cwd: &Path,
    use_legacy_landlock: bool,
    allow_network_for_proxy: bool,
) -> Vec<String>
```

### 断言技术

**使用 `windows(2)` 进行键值对验证：**
```rust
args.windows(2).any(|window| { 
    window[0] == "--file-system-sandbox-policy" && !window[1].is_empty() 
})
```
这种技术用于验证 `"--flag" "value"` 形式的命令行参数对。

**使用 `contains` 进行简单存在性验证：**
```rust
args.contains(&"--use-legacy-landlock".to_string())
```

### 测试数据

```rust
// 标准测试命令
let command = vec!["/bin/true".to_string()];

// 测试路径
let command_cwd = Path::new("/tmp/link");
let cwd = Path::new("/tmp");

// 只读沙箱策略
let sandbox_policy = SandboxPolicy::new_read_only_policy();
```

## 关键代码路径与文件引用

### 被测试的源文件

| 文件 | 说明 |
|------|------|
| `/home/sansha/Github/codex/codex-rs/core/src/landlock.rs` | 主实现文件 |

### 测试函数到被测函数的映射

```
landlock_tests.rs
├── legacy_landlock_flag_is_included_when_requested
│   └── tests → create_linux_sandbox_command_args(..., use_legacy_landlock, _)
├── proxy_flag_is_included_when_requested
│   └── tests → create_linux_sandbox_command_args(..., _, allow_network_for_proxy)
├── split_policy_flags_are_included
│   └── tests → create_linux_sandbox_command_args_for_policies(...)
└── proxy_network_requires_managed_requirements
    └── tests → allow_network_for_proxy(enforce_managed_network)
```

### 依赖类型

```rust
use super::*;  // landlock.rs 的公共接口
use pretty_assertions::assert_eq;
```

测试中使用的策略类型：
- `SandboxPolicy` - 传统沙箱策略
- `FileSystemSandboxPolicy` - 文件系统沙箱策略
- `NetworkSandboxPolicy` - 网络沙箱策略

## 依赖与外部交互

### 测试框架依赖

| 依赖 | 用途 |
|------|------|
| `pretty_assertions` | 提供更清晰的断言失败输出 |
| `std::path::Path` | 路径处理 |

### 被测模块依赖

测试中隐式依赖（通过 `use super::*`）：
- `SandboxPolicy::new_read_only_policy()` - 创建测试策略
- `FileSystemSandboxPolicy::from()` - 策略转换
- `NetworkSandboxPolicy::from()` - 策略转换

### 无外部进程交互

本测试文件**不**涉及：
- 实际启动 `codex-linux-sandbox` 进程
- 文件系统操作（除路径字符串处理外）
- 网络操作

## 风险、边界与改进建议

### 已知限制

1. **测试范围有限**
   - 仅验证命令行参数生成，不验证实际沙箱行为
   - 不测试与 `codex-linux-sandbox` 的集成

2. **硬编码期望值**
   ```rust
   assert_eq!(args.windows(2).any(|window| { 
       window[0] == "--network-sandbox-policy" && window[1] == "\"restricted\"" 
   }), true);
   ```
   - 依赖 `"restricted"` 的确切字符串表示
   - 如果 `NetworkSandboxPolicy` 的序列化格式改变，测试会失败

3. **路径假设**
   - 使用 `/tmp/link` 和 `/tmp` 作为测试路径
   - 在 Windows 上这些测试会失败（但此模块仅用于 Linux）

4. **未覆盖的边界情况**
   - 空命令列表
   - 包含特殊字符的命令参数
   - 非 UTF-8 路径
   - 非常大的策略 JSON

### 边界情况分析

| 边界情况 | 测试覆盖 | 说明 |
|----------|----------|------|
| 两个标志同时启用 | ✅ | `proxy_flag_is_included_when_requested` 使用 `(true, true)` |
| 两个标志同时禁用 | ✅ | `legacy_landlock_flag_is_included_when_requested` 测试 false 情况 |
| 只读策略序列化 | ✅ | `split_policy_flags_are_included` 使用 `new_read_only_policy()` |
| 空策略 | ❌ | 未测试 |
| 包含特殊字符的路径 | ❌ | 未测试 |
| 包含空格的命令参数 | ❌ | 未测试 `--` 分隔符后的参数处理 |

### 改进建议

1. **增加参数顺序验证**
   ```rust
   #[test]
   fn args_order_is_correct() {
       let args = create_linux_sandbox_command_args_for_policies(...);
       // 验证 --sandbox-policy-cwd 在 --command-cwd 之前
       // 验证 -- 分隔符在策略参数之后、命令之前
   }
   ```

2. **增加 JSON 有效性验证**
   ```rust
   #[test]
   fn policy_json_is_valid() {
       let args = create_linux_sandbox_command_args_for_policies(...);
       let fs_policy_idx = args.iter().position(|a| a == "--file-system-sandbox-policy").unwrap();
       let fs_policy_json = &args[fs_policy_idx + 1];
       // 验证是有效的 JSON
       let _: Value = serde_json::from_str(fs_policy_json).expect("valid JSON");
   }
   ```

3. **增加特殊字符测试**
   ```rust
   #[test]
   fn handles_special_characters_in_command() {
       let command = vec!["echo".to_string(), "--flag".to_string(), "value".to_string()];
       let args = create_linux_sandbox_command_args(...);
       // 验证 -- 分隔符正确放置，防止 --flag 被解析为沙箱选项
       let separator_idx = args.iter().position(|a| a == "--").unwrap();
       let echo_idx = args.iter().position(|a| a == "echo").unwrap();
       assert!(separator_idx < echo_idx);
   }
   ```

4. **增加错误处理测试**
   ```rust
   #[test]
   #[should_panic(expected = "cwd must be valid UTF-8")]
   fn panics_on_non_utf8_path() {
       // 使用非 UTF-8 路径调用
   }
   ```

5. **使用参数化测试**
   ```rust
   #[test_case(true, true)]
   #[test_case(true, false)]
   #[test_case(false, true)]
   #[test_case(false, false)]
   fn flag_combinations(legacy: bool, proxy: bool) {
       // 测试所有标志组合
   }
   ```

### 维护注意事项

1. **与 landlock.rs 的同步**：
   - 当 `landlock.rs` 添加新命令行选项时，应同步添加测试
   - 当命令行格式改变时，测试需要更新

2. **策略序列化格式**：
   - 测试依赖 `NetworkSandboxPolicy` 序列化为 `"restricted"`
   - 如果枚举的序列化改变（如改为大写），测试会失败

3. **平台限制**：
   - 此测试文件仅应在 Linux 上运行
   - 虽然代码本身可在任何平台编译，但业务逻辑是 Linux 特定的

4. **测试命名规范**：
   - 当前使用 `snake_case` 描述性名称
   - 建议保持这种风格，清晰表达测试意图
