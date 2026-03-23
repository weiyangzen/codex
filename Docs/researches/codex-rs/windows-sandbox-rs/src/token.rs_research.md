# token.rs 研究文档

## 场景与职责

`token.rs` 是 Codex Windows Sandbox 的**访问令牌管理模块**，负责创建和管理用于沙箱进程的安全令牌（Security Tokens）。该模块实现了基于 Windows 受限令牌（Restricted Tokens）和 Capability SID 的权限隔离机制，是沙箱安全模型的核心组件。

该模块的主要职责：
1. **创建受限令牌**：基于当前进程令牌创建权限受限的新令牌
2. **Capability SID 集成**：将 Capability SID 注入令牌，用于文件系统 ACL 匹配
3. **令牌权限管理**：启用/禁用特定权限（如 `SeChangeNotifyPrivilege`）
4. **Logon SID 提取**：获取当前登录会话的 SID 用于资源访问

## 功能点目的

### 1. 受限令牌创建
- 使用 `CreateRestrictedToken` API 创建权限受限的令牌
- 应用 `DISABLE_MAX_PRIVILEGE`、`LUA_TOKEN`、`WRITE_RESTRICTED` 标志
- 移除管理员权限，降低特权级别

### 2. Capability SID 支持
- 支持将 Capability SID 添加到令牌的组列表
- 实现工作区特定的 Capability SID（基于 CWD）
- 支持多 Capability SID（用于 WorkspaceWrite 策略）

### 3. 默认 DACL 配置
- 设置宽松的默认 DACL，允许沙箱进程创建管道/IPC 对象
- 避免 PowerShell 管道等场景中的 `ACCESS_DENIED` 错误

### 4. 权限管理
- 启用 `SeChangeNotifyPrivilege`（遍历检查通知权限）
- 确保沙箱进程可以正常访问文件系统

## 具体技术实现

### 关键数据结构

```rust
// 令牌创建标志
const DISABLE_MAX_PRIVILEGE: u32 = 0x01;  // 禁用所有特权
const LUA_TOKEN: u32 = 0x04;              // 限制管理员权限（Limited User Account）
const WRITE_RESTRICTED: u32 = 0x08;       // 写入限制
const GENERIC_ALL: u32 = 0x1000_0000;     // 通用所有权限

// 已知 SID 常量
const WIN_WORLD_SID: i32 = 1;             // Everyone SID
const SE_GROUP_LOGON_ID: u32 = 0xC0000000; // Logon SID 属性标志

// TokenDefaultDacl 信息结构
#[repr(C)]
struct TokenDefaultDaclInfo {
    default_dacl: *mut ACL,
}

// 链接令牌结构（用于获取关联令牌）
#[repr(C)]
struct TOKEN_LINKED_TOKEN {
    linked_token: HANDLE,
}
const TOKEN_LINKED_TOKEN_CLASS: i32 = 19; // TokenLinkedToken
```

### 关键流程

#### 创建只读令牌 (`create_readonly_token_with_cap`)

```rust
pub unsafe fn create_readonly_token_with_cap(
    psid_capability: *mut c_void,
) -> Result<(HANDLE, *mut c_void)> {
    let base = get_current_token_for_restriction()?;
    let res = create_readonly_token_with_cap_from(base, psid_capability);
    CloseHandle(base);
    res
}
```

流程：
1. 获取当前进程的令牌（带 `TOKEN_DUPLICATE | TOKEN_ASSIGN_PRIMARY` 等权限）
2. 基于基础令牌创建带 Capability SID 的受限令牌
3. 关闭基础令牌句柄
4. 返回新令牌句柄和 Capability SID 指针

#### 创建受限令牌核心逻辑 (`create_token_with_caps_from`)

```rust
unsafe fn create_token_with_caps_from(
    base_token: HANDLE,
    psid_capabilities: &[*mut c_void],
) -> Result<HANDLE> {
    // 1. 获取 Logon SID（用于资源访问）
    let mut logon_sid_bytes = get_logon_sid_bytes(base_token)?;
    let psid_logon = logon_sid_bytes.as_mut_ptr() as *mut c_void;
    
    // 2. 获取 Everyone SID（用于通用访问）
    let mut everyone = world_sid()?;
    let psid_everyone = everyone.as_mut_ptr() as *mut c_void;
    
    // 3. 构建 SID 列表：Capabilities..., Logon, Everyone
    let mut entries: Vec<SID_AND_ATTRIBUTES> = 
        vec![std::mem::zeroed(); psid_capabilities.len() + 2];
    
    // 填充 Capability SIDs
    for (i, psid) in psid_capabilities.iter().enumerate() {
        entries[i].Sid = *psid;
        entries[i].Attributes = 0;
    }
    
    // 填充 Logon SID
    entries[logon_idx].Sid = psid_logon;
    entries[logon_idx].Attributes = 0;
    
    // 填充 Everyone SID
    entries[logon_idx + 1].Sid = psid_everyone;
    entries[logon_idx + 1].Attributes = 0;
    
    // 4. 创建受限令牌
    let mut new_token: HANDLE = 0;
    let flags = DISABLE_MAX_PRIVILEGE | LUA_TOKEN | WRITE_RESTRICTED;
    let ok = CreateRestrictedToken(
        base_token,
        flags,
        0, std::ptr::null(),  // 禁用 SID 列表（未使用）
        0, std::ptr::null(),  // 删除权限列表（未使用）
        entries.len() as u32,
        entries.as_mut_ptr(), // 限制的 SID 列表
        &mut new_token,
    );
    
    // 5. 设置默认 DACL
    let mut dacl_sids = vec![psid_logon, psid_everyone];
    dacl_sids.extend_from_slice(psid_capabilities);
    set_default_dacl(new_token, &dacl_sids)?;
    
    // 6. 启用 SeChangeNotifyPrivilege
    enable_single_privilege(new_token, "SeChangeNotifyPrivilege")?;
    
    Ok(new_token)
}
```

#### 获取 Logon SID (`get_logon_sid_bytes`)

```rust
pub unsafe fn get_logon_sid_bytes(h_token: HANDLE) -> Result<Vec<u8>> {
    // 策略 1：扫描 TokenGroups 查找 SE_GROUP_LOGON_ID 属性的 SID
    if let Some(v) = scan_token_groups_for_logon(h_token) {
        return Ok(v);
    }
    
    // 策略 2：如果当前令牌是链接令牌，获取关联令牌再扫描
    // 使用 TokenLinkedToken 信息类
    
    Err(anyhow!("Logon SID not present on token"))
}
```

扫描逻辑：
1. 调用 `GetTokenInformation` 获取 `TokenGroups`
2. 遍历 `SID_AND_ATTRIBUTES` 数组
3. 查找 `Attributes & SE_GROUP_LOGON_ID == SE_GROUP_LOGON_ID` 的条目
4. 使用 `CopySid` 复制 SID 字节

#### 设置默认 DACL (`set_default_dacl`)

```rust
unsafe fn set_default_dacl(h_token: HANDLE, sids: &[*mut c_void]) -> Result<()> {
    // 为每个 SID 创建 EXPLICIT_ACCESS_W 条目
    // 权限：GENERIC_ALL
    // 访问模式：GRANT_ACCESS
    // 继承：0（不继承）
    
    // 使用 SetEntriesInAclW 创建新 DACL
    // 使用 SetTokenInformation 设置 TokenDefaultDacl
}
```

### Windows API 使用

| 功能 | API 函数 |
|------|----------|
| 令牌操作 | `OpenProcessToken`, `CreateRestrictedToken`, `SetTokenInformation`, `GetTokenInformation` |
| SID 操作 | `CreateWellKnownSid`, `CopySid`, `GetLengthSid` |
| 权限管理 | `LookupPrivilegeValueW`, `AdjustTokenPrivileges` |
| ACL 操作 | `SetEntriesInAclW` |
| 句柄管理 | `CloseHandle`, `LocalFree` |

### 安全标志详解

```rust
// CreateRestrictedToken 标志
const DISABLE_MAX_PRIVILEGE: u32 = 0x01;
// 禁用令牌中的所有特权，创建低特权令牌

const LUA_TOKEN: u32 = 0x04;
// 限制管理员令牌（Limited User Account）
// 移除管理员组的权限，即使 SID 仍在令牌中

const WRITE_RESTRICTED: u32 = 0x08;
// 写入限制模式
// 访问检查时需要同时满足受限令牌和非受限令牌的 DACL
```

## 关键代码路径与文件引用

### 本文件内部函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `get_current_token_for_restriction` | 147-168 | 获取可用于创建受限令牌的基础令牌 |
| `create_readonly_token_with_cap` | 287-294 | 创建带 Capability 的只读令牌 |
| `create_readonly_token_with_cap_from` | 300-306 | 从指定基础令牌创建只读令牌 |
| `create_workspace_write_token_with_caps_from` | 312-317 | 创建工作区写入令牌（多 Capability） |
| `create_readonly_token_with_caps_from` | 323-328 | 创建多 Capability 只读令牌 |
| `create_token_with_caps_from` | 330-380 | 核心受限令牌创建逻辑 |
| `get_logon_sid_bytes` | 170-253 | 获取令牌的 Logon SID |
| `scan_token_groups_for_logon` | 171-211 | 扫描 TokenGroups 查找 Logon SID |
| `world_sid` | 108-127 | 创建 Everyone SID |
| `convert_string_sid_to_sid` | 131-143 | 字符串 SID 转换为 PSID |
| `set_default_dacl` | 54-106 | 设置令牌的默认 DACL |
| `enable_single_privilege` | 254-283 | 启用单个特权 |

### 调用的外部模块

| 模块 | 函数 | 用途 |
|------|------|------|
| `winutil` | `to_wide` | 字符串转宽字符 |

### 调用方

| 文件 | 函数 | 场景 |
|------|------|------|
| `lib.rs` (windows_impl) | `create_readonly_token_with_cap` | 创建只读沙箱令牌 |
| `lib.rs` (windows_impl) | `create_workspace_write_token_with_caps_from` | 创建工作区写入令牌 |
| `lib.rs` (windows_impl) | `get_current_token_for_restriction` | 获取基础令牌 |
| `lib.rs` (windows_impl) | `get_logon_sid_bytes` | 获取 Logon SID |
| `lib.rs` (windows_impl) | `convert_string_sid_to_sid` | SID 转换 |
| `elevated_impl.rs` | `create_readonly_token_with_caps_from` | 特权实现 |

## 依赖与外部交互

### 输入依赖

1. **当前进程令牌**：通过 `OpenProcessToken` 获取
2. **Capability SID 字符串**：从 `cap_sid` 文件加载或生成
3. **Windows 权限**：需要 `SE_CREATE_TOKEN_PRIVILEGE` 等权限（通常需要管理员）

### 输出产物

1. **受限令牌句柄（HANDLE）**：用于创建沙箱进程
2. **Capability SID 指针**：用于后续 ACL 操作

### 与沙箱创建流程的交互

```
windows_impl::run_windows_sandbox_capture
    |
    |-- 1. 加载 Capability SID（cap.rs）
    |
    |-- 2. 根据策略创建令牌：
    |       - ReadOnly: create_readonly_token_with_cap
    |       - WorkspaceWrite: create_workspace_write_token_with_caps_from
    |
    |-- 3. 使用令牌创建进程（process.rs）
    |
    |-- 4. 关闭令牌句柄
```

## 风险、边界与改进建议

### 安全风险

1. **内存安全**：大量使用 `unsafe` 代码操作 Windows 句柄和指针
   - 风险：句柄泄漏、悬挂指针、内存访问违规
   - 缓解：使用 RAII 模式（如 `CloseHandle`），但部分路径可能遗漏
   - 建议：实现 `Handle` 包装类型实现自动释放

2. **令牌权限**：`set_default_dacl` 授予 `GENERIC_ALL` 权限
   - 风险：过于宽松的 DACL 可能允许未授权访问
   - 缓解：仅授予必要权限（FILE_GENERIC_READ | FILE_GENERIC_WRITE | FILE_GENERIC_EXECUTE）

3. **Logon SID 获取失败**：某些令牌类型可能没有 Logon SID
   - 风险：沙箱进程无法访问网络资源
   - 缓解：尝试链接令牌作为备选
   - 建议：添加更完善的错误处理和回退机制

### 边界情况

1. **令牌类型**：
   - 主令牌 vs 模拟令牌：当前实现假设主令牌
   - 链接令牌：已处理，通过 `TokenLinkedToken` 获取关联令牌

2. **SID 格式**：
   - 支持标准 SID 字符串格式（S-1-5-...）
   - 通过 `convert_string_sid_to_sid` 转换

3. **权限不足**：
   - `CreateRestrictedToken` 需要特定权限
   - 在非管理员上下文中可能失败

### 改进建议

1. **类型安全**：
   - 实现 `SafeHandle` 包装类型，自动调用 `CloseHandle`
   - 使用 `PhantomData` 标记令牌类型（主令牌/模拟令牌）

2. **错误处理**：
   - 添加更详细的错误上下文（哪个操作失败、参数值）
   - 实现自定义错误类型替代 `anyhow` 以提高可诊断性

3. **性能优化**：
   - 缓存 `world_sid()` 结果（Everyone SID 是常量）
   - 避免重复的 `GetTokenInformation` 调用

4. **安全加固**：
   - 审查 `set_default_dacl` 的权限授予范围
   - 考虑使用 `SE_SIGNING_LEVEL` 等现代 Windows 安全特性

5. **代码结构**：
   - 将 `create_token_with_caps_from` 拆分为更小的函数
   - 提取 SID 操作为独立模块

6. **文档完善**：
   - 添加更多关于 Windows 令牌模型的注释
   - 解释不同标志（DISABLE_MAX_PRIVILEGE, LUA_TOKEN, WRITE_RESTRICTED）的具体影响
