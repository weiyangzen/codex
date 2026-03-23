# desktop.rs 研究文档

## 场景与职责

`desktop.rs` 实现 Windows 桌面隔离功能，用于创建和管理私有桌面（Private Desktop）。这是 Windows 沙箱安全的重要组件，通过将沙箱进程运行在独立的桌面会话中，实现：
- UI 隔离：沙箱进程无法与主桌面窗口交互
- 输入隔离：防止键盘/鼠标输入被沙箱进程截获
- 视觉隔离：沙箱窗口不会出现在主桌面

该模块在以下场景中使用：
- 高安全性要求的沙箱执行（`use_private_desktop: true`）
- 防止沙箱进程通过窗口消息攻击主桌面
- 防止沙箱进程通过屏幕截图/录屏窃取敏感信息

## 功能点目的

### 1. 桌面启动信息管理
- **`LaunchDesktop`**: 桌面启动信息封装
- 管理桌面名称和启动信息字符串
- 支持私有桌面和默认桌面两种模式

### 2. 私有桌面创建
- **`PrivateDesktop`**: 私有桌面句柄管理
- 使用 `CreateDesktopW` 创建独立桌面
- 生成随机桌面名称避免冲突

### 3. 桌面权限配置
- **`grant_desktop_access`**: 授予当前登录 SID 对私有桌面的访问权限
- 使用 `SetEntriesInAclW` + `SetSecurityInfo` 配置 DACL
- 确保沙箱进程能够在新桌面上创建窗口

### 4. 资源生命周期管理
- **`Drop for PrivateDesktop`**: 自动关闭桌面句柄
- 使用 `CloseDesktop` 清理资源

## 具体技术实现

### 关键数据结构

```rust
pub struct LaunchDesktop {
    _private_desktop: Option<PrivateDesktop>,
    startup_name: Vec<u16>,  // 宽字符桌面名称，用于 STARTUPINFOW.lpDesktop
}

struct PrivateDesktop {
    handle: isize,           // HDESK 桌面句柄
    name: String,            // 桌面名称（如 "CodexSandboxDesktop-a1b2c3d4"）
}

// 桌面权限常量（来自 Windows API）
const DESKTOP_ALL_ACCESS: u32 = DESKTOP_READOBJECTS
    | DESKTOP_CREATEWINDOW
    | DESKTOP_CREATEMENU
    | DESKTOP_HOOKCONTROL
    | DESKTOP_JOURNALRECORD
    | DESKTOP_JOURNALPLAYBACK
    | DESKTOP_ENUMERATE
    | DESKTOP_WRITEOBJECTS
    | DESKTOP_SWITCHDESKTOP
    | DESKTOP_DELETE
    | DESKTOP_READ_CONTROL
    | DESKTOP_WRITE_DAC
    | DESKTOP_WRITE_OWNER;
```

### 桌面创建流程

```
LaunchDesktop::prepare(use_private_desktop, logs_base_dir)
  └─> 如果 use_private_desktop:
  │     └─> PrivateDesktop::create(logs_base_dir)
  │           └─> 生成随机名称: "CodexSandboxDesktop-{随机128位十六进制}"
  │           └─> CreateDesktopW(name, DESKTOP_ALL_ACCESS)
  │           └─> 如果失败: 记录错误并返回错误
  │           └─> grant_desktop_access(handle, logs_base_dir)
  │           │     └─> get_current_token_for_restriction()
  │           │     └─> get_logon_sid_bytes(token)
  │           │     └─> CloseHandle(token)
  │           │     └─> 构建 EXPLICIT_ACCESS_W (GRANT_ACCESS, DESKTOP_ALL_ACCESS)
  │           │     └─> SetEntriesInAclW(entries, null, &mut updated_dacl)
  │           │     └─> SetSecurityInfo(handle, SE_WINDOW_OBJECT, DACL_SECURITY_INFORMATION, updated_dacl)
  │           │     └─> LocalFree(updated_dacl)
  │           └─> 返回 PrivateDesktop { handle, name }
  │     └─> startup_name = "Winsta0\\{name}" (宽字符)
  └─> 否则:
        └─> startup_name = "Winsta0\\Default" (宽字符)
  └─> 返回 LaunchDesktop { _private_desktop, startup_name }
```

### 权限授予细节

```rust
let entries = [EXPLICIT_ACCESS_W {
    grfAccessPermissions: DESKTOP_ALL_ACCESS,
    grfAccessMode: GRANT_ACCESS,
    grfInheritance: 0,
    Trustee: TRUSTEE_W {
        pMultipleTrustee: ptr::null_mut(),
        MultipleTrusteeOperation: 0,
        TrusteeForm: TRUSTEE_IS_SID,
        TrusteeType: TRUSTEE_IS_UNKNOWN,
        ptstrName: logon_sid.as_mut_ptr() as *mut c_void as *mut u16,
    },
}];
```

注意：`ptstrName` 实际上指向 SID 字节，而非真正的宽字符串。这是 Windows API 的特殊用法。

## 关键代码路径与文件引用

### 主要调用方

| 调用方 | 调用函数 | 场景 |
|--------|----------|------|
| `process.rs` | `LaunchDesktop::prepare` | 创建进程时指定桌面 |

### 被调用模块

| 模块 | 函数 | 用途 |
|------|------|------|
| `token.rs` | `get_current_token_for_restriction`, `get_logon_sid_bytes` | 获取登录 SID |
| `logging.rs` | `debug_log` | 错误日志记录 |
| `winutil.rs` | `to_wide`, `format_last_error` | 字符串转换和错误格式化 |

### 代码引用路径

```
codex-rs/windows-sandbox-rs/src/desktop.rs
  ├─> 依赖: token.rs (get_current_token_for_restriction, get_logon_sid_bytes)
  ├─> 依赖: logging.rs (debug_log)
  ├─> 依赖: winutil.rs (to_wide, format_last_error)
  ├─> 被 process.rs 使用
  └─> Windows API: Win32::System::StationsAndDesktops, Win32::Security::Authorization
```

## 依赖与外部交互

### 内部依赖
- **`token.rs`**: 获取当前进程令牌和登录 SID
- **`logging.rs`**: 调试日志记录
- **`winutil.rs`**: 字符串编码转换和错误格式化

### 外部依赖
- **windows-sys**: Windows API 绑定
  - `Win32::System::StationsAndDesktops`: 桌面管理 API
  - `Win32::Security::Authorization`: ACL 管理
  - `Win32::Foundation`: 错误处理和句柄管理
- **rand**: 随机数生成（桌面名称）

### Windows API 使用

| API | 用途 |
|-----|------|
| `CreateDesktopW` | 创建新桌面 |
| `CloseDesktop` | 关闭桌面句柄 |
| `SetEntriesInAclW` | 构建 ACL |
| `SetSecurityInfo` | 设置对象安全信息 |
| `LocalFree` | 释放内存 |
| `GetLastError` | 获取错误码 |

### 环境交互
- 创建桌面属于 Window Station `Winsta0`（交互式窗口站）
- 桌面名称格式：`Winsta0\DesktopName`
- 需要 `SeCreateGlobalPrivilege` 或类似权限创建桌面

## 风险、边界与改进建议

### 安全风险

1. **桌面句柄泄露**
   - 如果 `PrivateDesktop` 未正确 `Drop`，句柄泄露
   - 但 `Drop` 实现已确保 `CloseDesktop` 调用

2. **权限配置错误**
   - 如果 `grant_desktop_access` 失败，桌面无法使用
   - 当前实现会销毁桌面并返回错误（安全失败）

3. **名称冲突**
   - 使用 128 位随机数，冲突概率极低（2^-128）
   - 但 `CreateDesktopW` 如果返回已存在错误，应处理重试

4. **资源耗尽**
   - 每个桌面消耗内核资源（堆内存、GDI 对象等）
   - 大量并发沙箱可能导致资源耗尽

### 边界条件

| 边界 | 处理 |
|------|------|
| CreateDesktopW 失败 | 记录错误，返回错误 |
| grant_desktop_access 失败 | 关闭桌面，返回错误 |
| 令牌获取失败 | 传播错误 |
| 登录 SID 获取失败 | 传播错误 |
| 非 Windows 平台 | 模块被条件编译排除 |

### 改进建议

1. **名称冲突处理**
   ```rust
   // 当前: 直接使用随机名称
   // 建议: 处理 ERROR_ALREADY_EXISTS 并重试
   loop {
       let name = format!("CodexSandboxDesktop-{:x}", rng.gen::<u128>());
       match CreateDesktopW(...) {
           Ok(handle) => return Ok(handle),
           Err(e) if e == ERROR_ALREADY_EXISTS => continue,
           Err(e) => return Err(e),
       }
   }
   ```

2. **权限最小化**
   - 当前授予 `DESKTOP_ALL_ACCESS`
   - 建议评估是否可以限制权限（如移除 `DESKTOP_HOOKCONTROL`）

3. **桌面清理确认**
   ```rust
   // 当前: Drop 中调用 CloseDesktop 但忽略结果
   // 建议: 调试模式下记录关闭结果
   impl Drop for PrivateDesktop {
       fn drop(&mut self) {
           if self.handle != 0 {
               let result = unsafe { CloseDesktop(self.handle) };
               debug_assert!(result != 0, "CloseDesktop failed");
           }
       }
   }
   ```

4. **超时机制**
   - 桌面创建和权限设置可能阻塞
   - 建议增加超时控制

5. **可观测性增强**
   - 当前仅记录错误
   - 建议增加桌面创建/销毁的生命周期日志

6. **回退策略**
   - 私有桌面创建失败时，可考虑回退到默认桌面
   - 但需明确告知用户安全级别降低

### 测试分析

当前模块无单元测试。建议补充：

| 测试场景 | 说明 |
|----------|------|
| 私有桌面创建/销毁 | 验证生命周期管理 |
| 权限验证 | 验证登录 SID 能访问桌面 |
| 名称唯一性 | 验证并发创建不冲突 |
| 错误处理 | 模拟 API 失败场景 |
| 资源清理 | 验证 Drop 后句柄无效 |

### 注意事项

1. **桌面与窗口站**
   - 桌面属于窗口站（Window Station）
   - 默认交互窗口站是 `Winsta0`
   - 服务和非交互会话可能无 `Winsta0`

2. **进程关联**
   - 进程创建时通过 `STARTUPINFOW.lpDesktop` 指定桌面
   - 进程创建后无法更改所属桌面

3. **显示限制**
   - 私有桌面默认不可见
   - 需要 `SwitchDesktop` 才能显示（当前未实现）
