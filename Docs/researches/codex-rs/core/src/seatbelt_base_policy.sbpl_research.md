# seatbelt_base_policy.sbpl 研究文档

## 场景与职责

本文件是 Codex **macOS Seatbelt 沙盒的基础策略文件**，定义了所有沙盒化进程的默认安全基线。它采用"默认拒绝（deny default）"原则，然后显式允许必要的系统操作，确保进程在最小权限下运行。

**核心职责**：
- 建立默认拒绝的安全基线
- 允许基本的进程操作（fork、exec、signal）
- 允许系统信息查询（sysctl）
- 允许必要的 IPC 和 IOKit 访问
- 支持终端交互（PTY）

## 功能点目的

### 1. 默认拒绝基线
```lisp
(deny default)
```
所有未明确允许的操作都被拒绝，这是安全沙盒的核心原则。

### 2. 进程生命周期管理
```lisp
(allow process-exec)      ; 执行子进程
(allow process-fork)      ; 创建子进程
(allow signal (target same-sandbox))  ; 信号通信（同沙盒内）
(allow process-info* (target same-sandbox))  ; 进程信息查询
```

### 3. 系统信息访问
允许查询硬件和系统信息，这对大多数应用程序正常运行是必需的：
- CPU 信息（类型、频率、核心数）
- 内存信息
- 操作系统版本
- 网络路由表

### 4. 终端和PTY支持
```lisp
(allow pseudo-tty)        ; 创建伪终端
(allow file-read* file-write* file-ioctl (literal "/dev/ptmx"))
```
支持交互式 shell 和终端应用程序。

### 5. 必要系统服务
- `com.apple.system.opendirectoryd.libinfo` - 用户信息查询
- `com.apple.PowerManagement.control` - 电源管理
- `RootDomainUserClient` - IOKit 根域访问

## 具体技术实现

### 策略结构

```lisp
(version 1)

; 1. 默认拒绝
(deny default)

; 2. 进程管理
(allow process-exec)
(allow process-fork)
...

; 3. 文件访问（最小）
(allow file-write-data
  (require-all
    (path "/dev/null")
    (vnode-type CHARACTER-DEVICE)))

; 4. 系统控制
(allow sysctl-read ...)
(allow sysctl-write ...)

; 5. IOKit
(allow iokit-open ...)

; 6. Mach IPC
(allow mach-lookup ...)

; 7. POSIX IPC
(allow ipc-posix-sem)

; 8. 终端
(allow pseudo-tty)
...
```

### 关键规则详解

#### Sysctl 读取规则
允许查询的系统参数分为几类：

1. **硬件信息**
   ```lisp
   (sysctl-name "hw.activecpu")
   (sysctl-name "hw.cpufrequency")
   (sysctl-name "hw.memsize")
   (sysctl-name "hw.physicalcpu")
   ```

2. **CPU 特性检测**
   ```lisp
   (sysctl-name-prefix "hw.optional.arm.")
   (sysctl-name-prefix "hw.optional.armv8_")
   ```

3. **系统信息**
   ```lisp
   (sysctl-name "kern.osproductversion")
   (sysctl-name "kern.osrelease")
   (sysctl-name "kern.hostname")
   ```

4. **网络和进程**
   ```lisp
   (sysctl-name-prefix "net.routetable.")
   (sysctl-name-prefix "kern.proc.pid.")
   ```

#### 终端设备规则
```lisp
; PTY 主设备
(allow file-read* file-write* file-ioctl (literal "/dev/ptmx"))

; PTY 从设备（带沙盒扩展）
(allow file-read* file-write*
  (require-all
    (regex #"^/dev/ttys[0-9]+")
    (extension "com.apple.sandbox.pty")))

; 为已存在的 PTY 提供 ioctl 支持
(allow file-ioctl (regex #"^/dev/ttys[0-9]+"))
```

### 设计参考

注释中明确引用了 Chrome 的沙盒策略：
- https://source.chromium.org/chromium/chromium/src/+/main:sandbox/policy/mac/common.sb
- https://source.chromium.org/chromium/chromium/src/+/main:sandbox/policy/mac/renderer.sb

Chrome 的策略作为行业最佳实践，为 Codex 的沙盒设计提供了参考。

## 关键代码路径与文件引用

### 引用关系
```
seatbelt.rs (line 28)
  └── const MACOS_SEATBELT_BASE_POLICY: &str
      └── include_str!("seatbelt_base_policy.sbpl")
```

### 使用流程
1. `create_seatbelt_command_args_for_policies_with_extensions` 构建完整策略
2. 将 `MACOS_SEATBELT_BASE_POLICY` 作为第一部分
3. 追加文件、网络、扩展等策略

### 相关文件
- `seatbelt_network_policy.sbpl` - 网络访问规则
- `restricted_read_only_platform_defaults.sbpl` - 平台默认值
- `seatbelt.rs` - 策略构建和执行

## 依赖与外部交互

### 系统依赖
- **macOS Seatbelt 框架**: 内核级沙盒机制
- **TrustedBSD MAC**: 强制访问控制框架
- **XNU 内核**: 系统调用过滤

### 与动态策略的交互
基础策略提供静态基线，动态策略在运行时添加：
```rust
let mut policy_sections = vec![
    MACOS_SEATBELT_BASE_POLICY.to_string(),      // 本文件
    file_read_policy,                            // 动态生成
    file_write_policy,                           // 动态生成
    network_policy,                              // 动态生成
];
if include_platform_defaults {
    policy_sections.push(MACOS_RESTRICTED_READ_ONLY_PLATFORM_DEFAULTS.to_string());
}
```

## 风险、边界与改进建议

### 潜在风险

1. **过度授权**
   - `process-exec` 和 `process-fork` 允许无限制的子进程创建
   - 子进程继承沙盒策略，但仍可能滥用资源

2. **信息泄露**
   - 大量 sysctl 读取可能用于系统指纹识别
   - 网络路由表信息可能泄露网络拓扑

3. **终端逃逸**
   - PTY 访问可能允许终端逃逸攻击
   - `file-ioctl` 在 PTY 上可能被滥用

### 边界限制

1. **静态策略**
   - 无法根据运行时条件调整
   - 所有规则在编译时确定

2. **平台版本**
   - 不同 macOS 版本可能需要不同的 sysctl
   - 新系统调用可能未覆盖

3. **最小文件访问**
   - 仅允许 `/dev/null` 写入
   - 实际文件访问需要动态策略补充

### 改进建议

1. **定期审查**
   - 与 Chrome 策略保持同步更新
   - 审查每个新 macOS 版本所需的 sysctl

2. **最小化权限**
   ```lisp
   ; 建议：考虑限制某些 sysctl
   ; 当前：允许所有 net.routetable
   ; 建议：仅允许特定路由表查询
   ```

3. **子进程控制**
   - 考虑添加子进程数量限制
   - 考虑限制特定可执行文件的执行

4. **审计日志**
   - 添加策略加载日志
   - 记录违反策略的尝试

5. **文档完善**
   - 为每个 sysctl 规则添加注释说明用途
   - 记录为什么需要每个 Mach 服务访问

6. **测试策略**
   - 添加测试验证基础策略可加载
   - 测试最小应用程序在基础策略下能否运行
