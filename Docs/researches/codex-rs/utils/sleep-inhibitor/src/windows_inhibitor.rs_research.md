# windows_inhibitor.rs 研究文档

## 场景与职责

`windows_inhibitor.rs` 是 `codex-utils-sleep-inhibitor` crate 的 **Windows 平台实现**，使用 Windows 的 **电源管理 API**（`PowerCreateRequest` / `PowerSetRequest` / `PowerClearRequest`）阻止系统进入空闲睡眠状态。

**核心设计决策**：
1. **原生 API 调用**：直接调用 `windows-sys` 提供的 Windows API 绑定
2. **电源请求（Power Request）模型**：创建电源请求对象并设置请求类型
3. **RAII 资源管理**：通过 `PowerRequest` 结构体的 `Drop` 实现自动清理
4. **匹配 macOS 语义**：使用 `PowerRequestSystemRequired` 仅阻止系统睡眠，不强制显示器保持开启

## 功能点目的

### 1. 电源请求管理
- **目的**：在 Agent Turn 执行期间阻止系统空闲睡眠
- **请求类型**：`PowerRequestSystemRequired` - 告诉系统当前正在执行重要任务，不应进入睡眠
- **语义**：与 macOS 的 `PreventUserIdleSystemSleep` 等效

### 2. 宽字符串处理
- **目的**：Windows API 使用 UTF-16 宽字符串
- **实现**：使用 `OsStr::encode_wide()` 转换 Rust 字符串

### 3. 错误处理与资源清理
- **目的**：API 调用失败时不 panic，确保资源不泄漏
- **策略**：
  - `PowerCreateRequest` 失败 → 返回错误，无资源泄漏
  - `PowerSetRequest` 失败 → 关闭句柄，返回错误
  - `Drop` 失败 → 记录警告，不 panic

### 4. 幂等性保证
- **目的**：允许重复调用 `acquire()` 而不创建多个请求
- **实现**：检查 `self.request.is_some()`，已存在则直接返回

## 具体技术实现

### 核心数据结构

```rust
#[derive(Debug, Default)]
pub(crate) struct WindowsSleepInhibitor {
    request: Option<PowerRequest>,  // 当前持有的电源请求
}

#[derive(Debug)]
struct PowerRequest {
    handle: windows_sys::Win32::Foundation::HANDLE,  // 电源请求句柄
    request_type: POWER_REQUEST_TYPE,                // 请求类型
}
```

### Windows API 导入

```rust
use windows_sys::Win32::Foundation::CloseHandle;
use windows_sys::Win32::Foundation::INVALID_HANDLE_VALUE;
use windows_sys::Win32::System::Power::{
    POWER_REQUEST_TYPE, PowerClearRequest, PowerCreateRequest, 
    PowerRequestSystemRequired, PowerSetRequest
};
use windows_sys::Win32::System::SystemServices::POWER_REQUEST_CONTEXT_VERSION;
use windows_sys::Win32::System::Threading::{
    POWER_REQUEST_CONTEXT_SIMPLE_STRING, REASON_CONTEXT, REASON_CONTEXT_0
};
```

### 常量定义

```rust
const ASSERTION_REASON: &str = "Codex is running an active turn";
```

### 关键方法实现

#### acquire() - 获取电源请求

```rust
pub(crate) fn acquire(&mut self) {
    // 幂等性检查
    if self.request.is_some() {
        return;
    }
    
    match PowerRequest::new_system_required(ASSERTION_REASON) {
        Ok(request) => {
            self.request = Some(request);
        }
        Err(error) => {
            warn!(
                reason = %error,
                "Failed to acquire Windows sleep-prevention request"
            );
        }
    }
}
```

#### PowerRequest::new_system_required() - 创建系统必需请求

```rust
fn new_system_required(reason: &str) -> Result<Self, String> {
    // 1. 转换原因字符串为 UTF-16
    let mut wide_reason: Vec<u16> = 
        OsStr::new(reason).encode_wide().chain(once(0)).collect();
    
    // 2. 构造 REASON_CONTEXT
    let context = REASON_CONTEXT {
        Version: POWER_REQUEST_CONTEXT_VERSION,  // 版本号
        Flags: POWER_REQUEST_CONTEXT_SIMPLE_STRING,  // 简单字符串模式
        Reason: REASON_CONTEXT_0 {
            SimpleReasonString: wide_reason.as_mut_ptr(),  // 宽字符串指针
        },
    };
    
    // 3. 创建电源请求
    let handle = unsafe { PowerCreateRequest(&context) };
    if handle.is_null() || handle == INVALID_HANDLE_VALUE {
        let error = std::io::Error::last_os_error();
        return Err(format!("PowerCreateRequest failed: {error}"));
    }
    
    // 4. 设置请求类型
    let request_type = PowerRequestSystemRequired;
    if unsafe { PowerSetRequest(handle, request_type) } == 0 {
        let error = std::io::Error::last_os_error();
        // 错误时清理句柄
        let _ = unsafe { CloseHandle(handle) };
        return Err(format!("PowerSetRequest failed: {error}"));
    }
    
    Ok(Self { handle, request_type })
}
```

**关键安全注释**：
- `context` 在 `PowerCreateRequest` 调用期间必须有效（Windows 会复制数据）
- `wide_reason` 必须保持存活直到 API 调用完成
- 错误路径必须关闭句柄防止泄漏

#### Drop 实现 - 自动清理

```rust
impl Drop for PowerRequest {
    fn drop(&mut self) {
        // 1. 清除电源请求
        if unsafe { PowerClearRequest(self.handle, self.request_type) } == 0 {
            let error = std::io::Error::last_os_error();
            warn!(
                reason = %error,
                "Failed to clear Windows sleep-prevention request"
            );
        }
        
        // 2. 关闭句柄
        if unsafe { CloseHandle(self.handle) } == 0 {
            let error = std::io::Error::last_os_error();
            warn!(
                reason = %error,
                "Failed to close Windows sleep-prevention request handle"
            );
        }
    }
}
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/utils/sleep-inhibitor/src/windows_inhibitor.rs`（119 行）

### 依赖关系
| 文件 | 关系 |
|------|------|
| `lib.rs` | 调用方，条件编译选择本模块作为 `imp` |

### 调用路径
```
lib.rs (SleepInhibitor::acquire/release)
  └── windows_inhibitor.rs (本文件)
       ├── PowerRequest::new_system_required()
       │   ├── OsStr::encode_wide()         // 字符串转换
       │   ├── PowerCreateRequest()         // Windows API
       │   └── PowerSetRequest()            // Windows API
       └── Drop::drop()
           ├── PowerClearRequest()          // Windows API
           └── CloseHandle()                // Windows API
```

## 依赖与外部交互

### 编译时依赖
```toml
[target.'cfg(target_os = "windows")'.dependencies]
windows-sys = { version = "0.61.2", features = [
    "Win32_Foundation",
    "Win32_System_Power",
    "Win32_System_SystemServices",
    "Win32_System_Threading",
] }
```

### Windows API 详解

#### PowerCreateRequest
```c
HANDLE PowerCreateRequest(
    PREASON_CONTEXT Context  // 请求原因上下文
);
```
- 创建电源请求对象
- 返回句柄，失败返回 NULL 或 INVALID_HANDLE_VALUE

#### PowerSetRequest
```c
BOOL PowerSetRequest(
    HANDLE PowerRequest,      // 电源请求句柄
    POWER_REQUEST_TYPE RequestType  // 请求类型
);
```
- 设置电源请求类型
- 返回非零表示成功

#### PowerClearRequest
```c
BOOL PowerClearRequest(
    HANDLE PowerRequest,
    POWER_REQUEST_TYPE RequestType
);
```
- 清除指定的电源请求
- 必须在 `CloseHandle` 前调用

#### 请求类型
| 类型 | 说明 |
|------|------|
| `PowerRequestDisplayRequired` | 保持显示器开启 |
| `PowerRequestSystemRequired` | 阻止系统睡眠（本实现使用） |
| `PowerRequestAwayModeRequired` | 进入离开模式（媒体录制场景） |
| `PowerRequestExecutionRequired` | 阻止执行节流（Windows 8+） |

### REASON_CONTEXT 结构
```c
typedef struct _REASON_CONTEXT {
    ULONG Version;      // POWER_REQUEST_CONTEXT_VERSION
    DWORD Flags;        // POWER_REQUEST_CONTEXT_SIMPLE_STRING 或 DETAILED
    union {
        LPWSTR SimpleReasonString;  // 简单字符串（本实现使用）
        struct {
            HMODULE LocalizedReasonModule;
            ULONG   LocalizedReasonId;
            ULONG   ReasonStringCount;
            LPWSTR  *ReasonStrings;
        } Detailed;
    } Reason;
} REASON_CONTEXT, *PREASON_CONTEXT;
```

## 风险、边界与改进建议

### 当前风险

#### 1. 字符串编码风险
**代码位置**：`windows_inhibitor.rs:62`
```rust
let mut wide_reason: Vec<u16> = OsStr::new(reason).encode_wide().chain(once(0)).collect();
```

- **风险**：`encode_wide()` 使用平台特定的宽字符编码（Windows 上是 UTF-16）
- **当前状态**：Windows 上 UTF-16 是标准，安全
- **潜在问题**：如果原因字符串包含无法编码的字符，可能被替换为 `U+FFFD`

#### 2. 句柄泄漏风险（已缓解）
- **场景**：`PowerSetRequest` 失败后需要关闭句柄
- **当前实现**：正确调用 `CloseHandle`
- **验证**：代码审查确认无泄漏路径

#### 3. API 调用失败静默处理
- **风险**：`acquire()` 失败仅记录警告，调用方无法感知
- **影响**：用户可能认为睡眠抑制已启用，实际上没有
- **与 macOS/Linux 一致**：符合 crate 整体设计

#### 4. Windows 版本兼容性
- **风险**：`PowerCreateRequest` API 需要 Windows 7 或更高版本
- **缓解**：Windows 7 已停止支持，当前目标平台均支持此 API

### 边界情况

#### 1. 多次 Acquire
```rust
pub(crate) fn acquire(&mut self) {
    if self.request.is_some() {
        return;  // 幂等性保证
    }
    // ...
}
```

#### 2. 空字符串原因
- **场景**：`ASSERTION_REASON` 被修改为空字符串
- **行为**：`wide_reason` 将只包含 null 终止符，API 调用仍然有效

#### 3. 进程崩溃
- **场景**：程序 panic 或异常终止
- **行为**：`PowerRequest` 的 `Drop` 可能不执行
- **缓解**：
  - Windows 在进程终止时会自动清理资源
  - 电源请求不会无限期阻止系统睡眠

### 改进建议

#### 1. 增加请求状态查询
```rust
impl WindowsSleepInhibitor {
    pub(crate) fn has_request(&self) -> bool {
        self.request.is_some()
    }
}
```

#### 2. 支持更多请求类型
当前仅使用 `PowerRequestSystemRequired`，可考虑支持：
```rust
enum WindowsInhibitMode {
    SystemRequired,      // 仅阻止系统睡眠
    DisplayRequired,     // 同时保持显示器开启
    ExecutionRequired,   // 阻止执行节流
}
```

#### 3. 错误码详细化
将 Windows 错误码转换为可读信息：
```rust
fn format_windows_error(code: u32) -> String {
    // 使用 FormatMessageW 获取系统错误描述
}
```

#### 4. 宽字符串优化
避免每次创建请求都分配 `Vec<u16>`：
```rust
// 使用 const 或 static
static WIDE_REASON: &[u16] = &[
    // 预编码的 UTF-16 字符串
];
```

#### 5. 断言名称国际化
当前使用硬编码英文描述，可考虑：
```rust
#[cfg(feature = "i18n")]
const ASSERTION_REASON: &str = /* 本地化字符串 */;
```

### 与 SetThreadExecutionState 的对比

Windows 提供了另一种睡眠抑制 API `SetThreadExecutionState`，本实现与其对比：

| 特性 | SetThreadExecutionState | PowerRequest API（本实现） |
|------|------------------------|---------------------------|
| 引入版本 | Windows 2000 | Windows 7 |
| 作用范围 | 当前线程 | 进程级电源请求对象 |
| 多线程安全 | 需要每个线程调用 | 请求对象可共享 |
| 精细控制 | 有限（ES_SYSTEM_REQUIRED 等标志） | 支持多种请求类型 |
| 原因说明 | 不支持 | 支持提供原因字符串 |
| 现代推荐 |  legacy | 推荐 |

**设计优势**：使用现代的 `PowerRequest` API，提供更好的可维护性和扩展性。

### 测试建议

#### 单元测试（困难）
Windows 电源 API 需要实际 Windows 环境，难以在 CI 中测试：
- 可考虑使用 mock 接口
- 或在 Windows runner 上运行集成测试

#### 手动测试清单
1. 验证 `powercfg /requests` 显示 Codex 的电源请求
2. 验证长时间任务期间系统不睡眠
3. 验证任务结束后 `powercfg /requests` 不再显示 Codex
4. 验证程序崩溃后电源请求被清理

#### 调试命令
```powershell
# 查看当前电源请求
powercfg /requests

# 查看电源请求覆盖
powercfg /requestsoverride

# 查看电源方案
powercfg /query
```

### 性能考虑

| 操作 | 开销 | 说明 |
|------|------|------|
| `PowerCreateRequest` | 中 | 内核对象创建 |
| `PowerSetRequest` | 低 | 设置标志 |
| `PowerClearRequest` | 低 | 清除标志 |
| `CloseHandle` | 低 | 关闭句柄 |
| 字符串编码 | 低 | 短字符串转换 |

**总体**：Windows 实现的性能开销与 macOS 相当，远低于 Linux 的子进程模型。
