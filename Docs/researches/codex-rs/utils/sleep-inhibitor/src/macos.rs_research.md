# macos.rs 研究文档

## 场景与职责

`macos.rs` 是 `codex-utils-sleep-inhibitor` crate 的 **macOS 平台实现**，使用 Apple 原生的 **IOKit 电源管理框架** 阻止系统进入空闲睡眠状态。与 Linux 的子进程模型不同，macOS 实现直接调用系统 API，更加轻量和可靠。

**核心设计决策**：
1. **原生 API 调用**：使用 `IOPMAssertionCreateWithName` 和 `IOPMAssertionRelease`
2. **断言（Assertion）模型**：创建电源断言对象，系统跟踪所有断言并综合决策是否允许睡眠
3. **自动释放**：通过 `Drop` trait 确保断言在对象销毁时释放

## 功能点目的

### 1. 电源断言管理
- **目的**：在 Agent Turn 执行期间阻止系统空闲睡眠
- **断言类型**：`PreventUserIdleSystemSleep` - 阻止用户空闲时的系统睡眠，但不强制显示器保持开启
- **断言级别**：`kIOPMAssertionLevelOn` (255) - 启用断言

### 2. 与 CoreFoundation 集成
- **目的**：IOKit API 使用 CoreFoundation 字符串类型
- **实现**：使用 `core-foundation` crate 进行安全的 Rust/CF 类型转换

### 3. 错误处理与日志
- **目的**：API 调用失败时不 panic，记录警告日志
- **策略**：创建失败仅记录日志，释放失败也仅记录日志，不影响主程序流程

### 4. 幂等性保证
- **目的**：允许重复调用 `acquire()` 而不创建多个断言
- **实现**：检查 `self.assertion.is_some()`，已存在则直接返回

## 具体技术实现

### 模块结构

```rust
// IOKit 绑定子模块
#[allow(...)]  // 允许 bindgen 生成代码的命名风格
mod iokit {
    #[link(name = "IOKit", kind = "framework")]
    unsafe extern "C" {}
    
    include!("iokit_bindings.rs");  // 包含生成的 FFI 绑定
}

// 类型别名简化
type IOPMAssertionID = iokit::IOPMAssertionID;
type IOPMAssertionLevel = iokit::IOPMAssertionLevel;
type IOReturn = iokit::IOReturn;
```

### 核心数据结构

```rust
#[derive(Debug, Default)]
pub(crate) struct SleepInhibitor {
    assertion: Option<MacSleepAssertion>,  // 当前持有的断言
}

#[derive(Debug)]
struct MacSleepAssertion {
    id: IOPMAssertionID,  // IOKit 断言标识符
}
```

### 常量定义

```rust
const ASSERTION_REASON: &str = "Codex is running an active turn";
const ASSERTION_TYPE_PREVENT_USER_IDLE_SYSTEM_SLEEP: &str = "PreventUserIdleSystemSleep";
```

**断言类型说明**：
- `PreventUserIdleSystemSleep`：阻止系统因用户空闲而睡眠
- 对比 `PreventUserIdleDisplaySleep`：还会保持显示器开启（本实现不使用）

### 关键方法实现

#### acquire() - 获取电源断言

```rust
pub(crate) fn acquire(&mut self) {
    // 幂等性检查
    if self.assertion.is_some() {
        return;
    }
    
    match MacSleepAssertion::create(ASSERTION_REASON) {
        Ok(assertion) => {
            self.assertion = Some(assertion);
        }
        Err(error) => {
            warn!(
                iokit_error = error,
                "Failed to create macOS sleep-prevention assertion"
            );
        }
    }
}
```

#### MacSleepAssertion::create() - 创建断言

```rust
fn create(name: &str) -> Result<Self, IOReturn> {
    // 创建 CoreFoundation 字符串
    let assertion_type = CFString::new(ASSERTION_TYPE_PREVENT_USER_IDLE_SYSTEM_SLEEP);
    let assertion_name = CFString::new(name);
    let mut id: IOPMAssertionID = 0;
    
    // 类型转换：core-foundation 和 bindgen 的 CFStringRef 类型不兼容
    // 需要显式 cast
    let assertion_type_ref: iokit::CFStringRef = 
        assertion_type.as_concrete_TypeRef().cast();
    let assertion_name_ref: iokit::CFStringRef = 
        assertion_name.as_concrete_TypeRef().cast();
    
    // 调用 IOKit API
    let result = unsafe {
        iokit::IOPMAssertionCreateWithName(
            assertion_type_ref,
            iokit::kIOPMAssertionLevelOn as IOPMAssertionLevel,
            assertion_name_ref,
            &mut id,
        )
    };
    
    // 检查结果
    if result == iokit::kIOReturnSuccess as IOReturn {
        Ok(Self { id })
    } else {
        Err(result)
    }
}
```

**关键安全注释**：
- `assertion_type_ref` 和 `assertion_name_ref` 在调用期间必须有效（CFString 被 IOKit 内部复制）
- `&mut id` 是有效的输出指针

#### Drop 实现 - 自动释放

```rust
impl Drop for MacSleepAssertion {
    fn drop(&mut self) {
        let result = unsafe {
            iokit::IOPMAssertionRelease(self.id)
        };
        
        if result != iokit::kIOReturnSuccess as IOReturn {
            warn!(
                iokit_error = result,
                "Failed to release macOS sleep-prevention assertion"
            );
        }
    }
}
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/utils/sleep-inhibitor/src/macos.rs`（107 行）

### 依赖文件
| 文件 | 关系 | 说明 |
|------|------|------|
| `iokit_bindings.rs` | 内联包含 | FFI 绑定定义 |
| `lib.rs` | 调用方 | 条件编译选择本模块作为 `imp` |

### 调用路径
```
lib.rs (SleepInhibitor::acquire/release)
  └── macos.rs (本文件)
       ├── MacSleepAssertion::create()
       │   ├── CFString::new()              // core-foundation
       │   └── iokit::IOPMAssertionCreateWithName()  // IOKit
       └── Drop::drop()
           └── iokit::IOPMAssertionRelease() // IOKit
```

### 外部框架
| 框架 | 用途 |
|------|------|
| `IOKit.framework` | 电源管理 API |
| `CoreFoundation.framework` | 字符串类型（通过 core-foundation crate） |

## 依赖与外部交互

### 编译时依赖
```toml
[target.'cfg(target_os = "macos")'.dependencies]
core-foundation = "0.9"
```

### 运行时系统依赖
- **IOKit.framework**：macOS 系统框架，始终可用
- **CoreFoundation.framework**：macOS 基础框架

### FFI 绑定详情

#### IOKit 函数
```c
// 创建命名电源断言
IOReturn IOPMAssertionCreateWithName(
    CFStringRef assertionType,
    IOPMAssertionLevel assertionLevel,
    CFStringRef assertionName,
    IOPMAssertionID *assertionID
);

// 释放电源断言
IOReturn IOPMAssertionRelease(IOPMAssertionID assertionID);
```

#### 类型映射
| C 类型 | Rust 类型 | 说明 |
|--------|-----------|------|
| `IOPMAssertionID` | `u32` | 断言标识符 |
| `IOPMAssertionLevel` | `u32` | 0=Off, 255=On |
| `IOReturn` | `c_int` | 返回码，0=成功 |
| `CFStringRef` | `*const __CFString` | CoreFoundation 字符串 |

## 风险、边界与改进建议

### 当前风险

#### 1. 类型转换风险
**代码位置**：`macos.rs:73-74`
```rust
let assertion_type_ref: iokit::CFStringRef = 
    assertion_type.as_concrete_TypeRef().cast();
```

- **风险**：`core-foundation` crate 和 bindgen 生成的 `CFStringRef` 是不同的不透明类型
- **缓解**：`.cast()` 是安全的，因为两者都是指向 `__CFString` 的指针
- **未来风险**：如果 core-foundation crate 改变内部表示，可能导致问题

#### 2. IOKit 错误静默处理
- **风险**：`acquire()` 失败仅记录警告，调用方无法感知
- **影响**：用户可能认为睡眠抑制已启用，实际上没有
- **缓解**：符合 crate 整体设计（不传播错误），但可考虑增加状态查询接口

#### 3. 断言 ID 0 的歧义
- **风险**：`IOPMAssertionID` 是 `u32`，0 是有效值，但也常用于表示"无效"
- **实际**：IOKit 返回的 ID 通常从 1 开始，但文档未明确保证

### 边界情况

#### 1. 多次 Acquire
```rust
pub(crate) fn acquire(&mut self) {
    if self.assertion.is_some() {
        return;  // 幂等性保证
    }
    // ...
}
```

#### 2. 未调用 Acquire 直接 Release
```rust
pub(crate) fn release(&mut self) {
    self.assertion = None;  // Option::take 会自动调用 Drop
}
```

#### 3. 进程崩溃
- **场景**：程序 panic 或收到 SIGKILL
- **行为**：`MacSleepAssertion` 的 `Drop` 可能不执行
- **缓解**：
  - macOS 会自动清理进程持有的所有电源断言
  - 系统级保护，无需额外处理

### 改进建议

#### 1. 增加断言状态查询
```rust
impl SleepInhibitor {
    pub(crate) fn has_assertion(&self) -> bool {
        self.assertion.is_some()
    }
}
```

#### 2. 更详细的错误信息
将 `IOReturn` 转换为可读的错误描述：
```rust
fn ioreturn_to_string(code: IOReturn) -> &'static str {
    match code {
        0 => "success",
        // ... 其他错误码
        _ => "unknown error",
    }
}
```

#### 3. 支持更多断言类型
当前仅使用 `PreventUserIdleSystemSleep`，可考虑支持：
- `PreventSystemSleep`：更严格的阻止（包括强制睡眠）
- `PreventUserIdleDisplaySleep`：同时保持显示器开启

#### 4. 断言名称国际化
当前使用硬编码英文描述，可考虑：
```rust
#[cfg(feature = "i18n")]
const ASSERTION_REASON: &str = /* 本地化字符串 */;
```

#### 5. 类型安全改进
考虑使用 newtype 模式包装 `IOPMAssertionID`：
```rust
struct AssertionId(IOPMAssertionID);
impl Drop for AssertionId { /* ... */ }
```

### 与 caffeinate 的对比

macOS 提供了命令行工具 `caffeinate`，本实现与其对比：

| 特性 | caffeinate | 本实现 |
|------|------------|--------|
| 实现方式 | 子进程 | 直接 API 调用 |
| 资源开销 | 高（额外进程） | 低（仅 API 调用） |
| 精确控制 | 有限 | 完整（可精确控制断言类型） |
| 崩溃清理 | 依赖进程组 | 依赖 Drop + 系统清理 |

**设计优势**：直接 API 调用避免了子进程管理复杂性，更加可靠。

### 测试建议

#### 单元测试（困难）
IOKit API 需要实际 macOS 环境，难以在 CI 中测试：
- 可考虑使用 mock 接口
- 或在 macOS runner 上运行集成测试

#### 手动测试清单
1. 验证系统偏好设置中显示 Codex 的断言
2. 验证长时间任务期间系统不睡眠
3. 验证任务结束后系统恢复正常睡眠行为
4. 验证程序崩溃后断言被清理
