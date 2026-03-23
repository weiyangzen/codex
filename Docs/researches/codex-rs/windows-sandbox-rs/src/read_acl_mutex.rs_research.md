# read_acl_mutex.rs 深度研究文档

## 场景与职责

`read_acl_mutex.rs` 是 Windows Sandbox 模块中的**读 ACL 互斥锁管理器**，用于协调多个进程对读 ACL 设置的访问。这是一个专门的同步原语，确保在设置读 ACL 时的互斥性，防止并发修改导致的安全策略冲突。

### 核心职责
1. **互斥锁创建**：创建命名的 Windows 互斥锁（Mutex）
2. **锁获取**：尝试获取互斥锁的所有权
3. **锁检测**：检查互斥锁是否已被其他进程持有
4. **自动释放**：使用 RAII 模式确保锁的可靠释放

## 功能点目的

### 1. `ReadAclMutexGuard` - 互斥锁守卫
```rust
pub struct ReadAclMutexGuard {
    handle: HANDLE,
}
```
- 实现 `Drop` trait，在作用域结束时自动释放互斥锁
- 封装 Windows 互斥锁句柄

### 2. `read_acl_mutex_exists` - 互斥锁存在检测
```rust
pub fn read_acl_mutex_exists() -> Result<bool>
```
- **用途**：检查读 ACL 互斥锁是否已被其他进程创建
- **实现**：尝试打开已存在的互斥锁
- **返回**：
  - `Ok(true)`：互斥锁存在（有其他进程正在设置读 ACL）
  - `Ok(false)`：互斥锁不存在
  - `Err(...)`：打开失败（非"未找到"错误）

### 3. `acquire_read_acl_mutex` - 获取互斥锁
```rust
pub fn acquire_read_acl_mutex() -> Result<Option<ReadAclMutexGuard>>
```
- **用途**：尝试创建并获取读 ACL 互斥锁
- **实现**：
  1. 调用 `CreateMutexW` 创建命名互斥锁
  2. 检查 `GetLastError()` 是否为 `ERROR_ALREADY_EXISTS`
  3. 如已存在，关闭句柄并返回 `Ok(None)`
  4. 如创建成功，返回 `Ok(Some(ReadAclMutexGuard))`

**使用模式**：
```rust
if let Some(guard) = acquire_read_acl_mutex()? {
    // 执行读 ACL 设置操作
    // guard 在作用域结束时自动释放
} else {
    // 互斥锁已被其他进程持有
    // 可以选择等待或跳过
}
```

## 具体技术实现

### 互斥锁命名
```rust
const READ_ACL_MUTEX_NAME: &str = "Local\\CodexSandboxReadAcl";
```
- 使用 `Local\` 前缀，表示互斥锁在当前会话（Terminal Services session）中可见
- 名称：`CodexSandboxReadAcl`

### Windows API 调用

#### 创建互斥锁
```rust
let handle = unsafe { 
    CreateMutexW(std::ptr::null_mut(), 1, name.as_ptr()) 
};
```
- 第二个参数 `1` 表示立即获取所有权
- 安全属性为 `null`（使用默认安全描述符）

#### 检查已存在
```rust
let err = unsafe { GetLastError() };
if err == ERROR_ALREADY_EXISTS {
    unsafe { CloseHandle(handle); }
    return Ok(None);
}
```

#### 释放互斥锁
```rust
impl Drop for ReadAclMutexGuard {
    fn drop(&mut self) {
        unsafe {
            let _ = ReleaseMutex(self.handle);
            CloseHandle(self.handle);
        }
    }
}
```

### 错误处理
- `CreateMutexW` 返回 0：创建失败，返回错误
- `OpenMutexW` 返回 0 且 `GetLastError() == ERROR_FILE_NOT_FOUND`：互斥锁不存在
- 其他错误：转换为 `anyhow::Error`

## 关键代码路径与文件引用

### 内部依赖
| 函数 | 来源 | 用途 |
|------|------|------|
| `to_wide` | `winutil.rs` | 字符串转宽字符 |

### 被调用方
| 调用方 | 场景 |
|--------|------|
| `setup_orchestrator.rs` | 设置流程中协调读 ACL 设置 |
| `elevated` 设置助手 | 提权进程中协调读 ACL 设置 |

### 导出接口
该模块的函数通常通过内部模块使用，不直接对外导出。

## 依赖与外部交互

### Windows API
```rust
use windows_sys::Win32::System::Threading::CreateMutexW;
use windows_sys::Win32::System::Threading::OpenMutexW;
use windows_sys::Win32::System::Threading::ReleaseMutex;
use windows_sys::Win32::System::Threading::MUTEX_ALL_ACCESS;
use windows_sys::Win32::Foundation::CloseHandle;
use windows_sys::Win32::Foundation::GetLastError;
use windows_sys::Win32::Foundation::ERROR_ALREADY_EXISTS;
use windows_sys::Win32::Foundation::ERROR_FILE_NOT_FOUND;
```

### 外部 Crate
- `anyhow`：错误处理

## 风险、边界与改进建议

### 已知风险

1. **互斥锁泄漏**
   - 问题：进程崩溃时互斥锁可能保持信号状态
   - 缓解：Windows 会在进程终止时自动释放其持有的互斥锁
   - 注意：如果进程在 `ReleaseMutex` 前崩溃，其他进程需要等待超时

2. **会话隔离**
   - 问题：`Local\` 前缀限制在当前 Terminal Services 会话
   - 影响：在远程桌面或 Fast User Switching 场景下，不同会话的进程无法看到同一互斥锁
   - 缓解：这是设计行为，确保会话隔离

3. **权限问题**
   - 问题：默认安全描述符可能限制其他用户访问
   - 缓解：确保设置进程和检查进程在同一用户上下文运行

### 边界条件

1. **重复获取**：同一进程可以多次获取同一互斥锁（递归获取）
2. **跨进程获取**：不同进程竞争创建，先创建者获得所有权
3. **句柄限制**：系统句柄表满时创建失败
4. **名称冲突**：与其他应用程序使用相同名称的互斥锁

### 改进建议

1. **超时机制**
   - 当前：无超时，立即返回
   - 建议：添加 `acquire_read_acl_mutex_with_timeout` 函数

2. **命名空间隔离**
   - 当前：固定名称
   - 建议：支持基于 codex_home 的动态命名，支持多实例

3. **审计日志**
   - 当前：无日志记录
   - 建议：记录互斥锁获取和释放事件

4. **统计信息**
   - 建议：添加获取等待时间统计

5. **替代同步原语**
   - 考虑使用 `CreateSemaphore` 允许有限并发
   - 或使用条件变量实现更复杂的协调

### 使用场景

读 ACL 设置需要互斥的原因：
1. **ACL 计算**：读根目录列表可能很大，计算需要时间
2. **ACL 应用**：应用 ACL 到文件系统是 IO 密集型操作
3. **并发安全**：多个进程同时修改同一目录的 ACL 可能导致不一致

### 性能考虑

1. **快速检查**：`read_acl_mutex_exists` 是轻量级操作
2. **立即返回**：`acquire_read_acl_mutex` 不阻塞，立即返回结果
3. **资源开销**：每个持有互斥锁的进程消耗一个内核对象

### 安全考虑

1. **拒绝服务**
   - 风险：恶意进程可以创建同名互斥锁并永不释放
   - 缓解：使用基于会话的命名空间限制影响范围

2. **信息泄露**
   - 风险：互斥锁名称可能泄露应用程序信息
   - 缓解：使用通用名称 `CodexSandboxReadAcl`
