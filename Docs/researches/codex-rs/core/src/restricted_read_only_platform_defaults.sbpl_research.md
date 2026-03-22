# restricted_read_only_platform_defaults.sbpl 研究文档

## 场景与职责

本文件是 macOS Seatbelt 沙盒策略的**平台默认策略片段**，专门用于 `ReadOnlyAccess::Restricted::include_platform_defaults` 场景。它定义了在受限只读模式下，macOS 进程运行所需的最小系统资源访问权限集合。

**核心职责**：
- 为 macOS 沙盒化进程提供基本的系统资源访问能力
- 确保进程能够正常加载系统框架、访问标准系统路径
- 支持基本的 IPC、网络、文件系统操作（在受限范围内）
- 作为 Seatbelt 基础策略的补充，提供平台特定的默认规则

## 功能点目的

### 1. 系统框架和库访问
允许进程映射和执行系统框架、动态库，这是 macOS 应用程序正常运行的基础：
- `/Library/Apple/System/Library/Frameworks`
- `/System/Library/Frameworks`、`/System/Library/PrivateFrameworks`
- `/usr/lib` 等系统库路径

### 2. 标准系统路径读取
允许读取标准系统配置、时区、密码文件等：
- `/Library/Preferences`、`/var/db`
- `/private/var/db/timezone`
- `/private/etc/passwd`、`/private/etc/services`

### 3. 临时文件系统访问
提供临时文件操作能力：
- `/tmp`、`/private/tmp`
- `/var/tmp`、`/private/var/tmp`
- 支持读写操作（scratch space）

### 4. 系统服务 IPC
允许与关键系统守护进程通信：
- `com.apple.logd`（日志系统）
- `com.apple.trustd`（证书信任）
- `com.apple.cfprefsd`（偏好设置）
- `com.apple.system.opendirectoryd`（目录服务）

### 5. 设备文件访问
允许访问标准设备文件：
- `/dev/null`、`/dev/zero`
- `/dev/random`、`/dev/urandom`
- `/dev/fd/*`（文件描述符）
- `/dev/tty*`、PTY 设备（终端交互）

### 6. 网络相关（受限）
- 允许连接到 `/private/var/run/syslog`（syslog socket）
- 支持本地网络配置查询

## 具体技术实现

### 策略语法
使用 Seatbelt Profile Language (SBPL)，基于 S-expression 格式：

```lisp
; 基本允许规则
(allow file-read* file-test-existence (subpath "/usr/lib"))

; 带条件的规则
(allow system-mac-syscall 
  (require-all
    (mac-policy-name "Sandbox")
    (mac-syscall-number 67)))

; 正则匹配
(allow file-read* (regex "^/dev/fd/(0|1|2)$"))
```

### 关键规则类型

| 规则类型 | 用途 |
|---------|------|
| `file-read*` | 读取文件内容、元数据 |
| `file-write*` | 写入文件 |
| `file-map-executable` | 映射可执行文件（加载动态库） |
| `file-test-existence` | 测试文件是否存在 |
| `mach-lookup` | 查找 Mach 服务（IPC） |
| `system-socket` | 系统 socket 操作 |
| `iokit-open` | IOKit 设备访问 |
| `sysctl-read` | 读取系统控制变量 |

### 路径匹配方式

1. **`subpath`** - 匹配路径及其所有子路径
2. **`literal`** - 精确匹配完整路径
3. **`regex`** - 正则表达式匹配
4. **`path-ancestors`** - 匹配路径的所有祖先目录

## 关键代码路径与文件引用

### 引用关系
```
seatbelt.rs (line 30-31)
  └── const MACOS_RESTRICTED_READ_ONLY_PLATFORM_DEFAULTS: &str 
      └── include_str!("restricted_read_only_platform_defaults.sbpl")
```

### 使用流程
1. `seatbelt.rs::create_seatbelt_command_args_for_policies_with_extensions()` 构建策略
2. 当 `include_platform_defaults` 为 true 时，将此文件内容追加到策略
3. 通过 `sandbox-exec -p <policy>` 应用完整策略

### 相关文件
- `seatbelt_base_policy.sbpl` - 基础沙盒策略（deny default）
- `seatbelt_network_policy.sbpl` - 网络访问策略
- `seatbelt.rs` - Seatbelt 沙盒实现
- `seatbelt_permissions.rs` - 权限扩展构建

## 依赖与外部交互

### 系统依赖
- **macOS Seatbelt 框架**: `/usr/bin/sandbox-exec`
- **系统调用过滤**: 基于 TrustedBSD MAC 框架
- **Mach IPC**: 与系统守护进程通信

### 与代码的交互
- 被 `seatbelt.rs` 通过 `include_str!` 宏内嵌为字符串常量
- 运行时动态拼接到完整策略中
- 通过 `-D` 参数传递变量（如 `DARWIN_USER_CACHE_DIR`）

### 安全边界
- 此策略仅提供**只读**访问的默认值
- 写入权限由 `FileSystemSandboxPolicy` 动态计算
- 网络访问由 `seatbelt_network_policy.sbpl` 和动态策略控制

## 风险、边界与改进建议

### 潜在风险

1. **过度授权风险**
   - 当前允许访问 `/opt/homebrew/lib`、`/usr/local/lib`、`/Applications`
   - 这些路径可能包含用户安装的软件，存在供应链攻击风险

2. **IPC 攻击面**
   - 允许与多个系统服务通信（analyticsd、logd、trustd 等）
   - 恶意代码可能利用这些服务进行信息泄露

3. **临时文件竞争**
   - `/tmp` 等目录允许读写，可能存在符号链接竞争攻击

### 边界限制

1. **平台限制**
   - 仅适用于 macOS，其他平台（Linux/Windows）使用不同机制
   - 需要 `sandbox-exec` 可执行文件存在

2. **功能限制**
   - 不包含网络访问规则（由单独文件处理）
   - 不包含应用特定的权限扩展（由 `seatbelt_permissions.rs` 处理）

### 改进建议

1. **细化权限**
   - 考虑将 Homebrew 和本地库路径访问改为可选配置
   - 增加更细粒度的 sysctl 访问控制

2. **安全加固**
   - 对 `/tmp` 访问增加更多限制（如禁止跟随符号链接）
   - 考虑限制某些 Mach 服务的访问范围

3. **可观测性**
   - 增加策略加载日志，记录哪些平台默认值被应用
   - 提供调试模式显示完整生成的策略

4. **维护性**
   - 定期审查 macOS 新版本所需的额外权限
   - 与 Chrome 沙盒策略保持同步更新（参考注释中的 Chromium 链接）
