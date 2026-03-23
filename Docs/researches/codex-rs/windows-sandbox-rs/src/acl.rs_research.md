# acl.rs 研究文档

## 场景与职责

`acl.rs` 是 Windows Sandbox 的核心访问控制列表（ACL）管理模块，负责文件系统权限的读取、检查和修改。它是沙箱安全模型的基础组件，通过 Windows 安全 API 实现对文件和目录的细粒度访问控制。

该模块在以下场景中使用：
- 沙箱初始化时为工作目录设置权限
- 为 Capability SID 添加/移除文件访问权限
- 审计世界可写目录并应用拒绝写入 ACE
- 保护敏感子目录（如 `.git`, `.codex`, `.agents`）
- 为 NULL 设备（NUL）授予访问权限以支持 stdout/stderr 重定向

## 功能点目的

### 1. DACL 获取与解析
- **`fetch_dacl_handle`**: 通过文件句柄获取安全描述符和 DACL
- 使用 `CreateFileW` + `GetSecurityInfo` 组合，支持备份语义以访问目录

### 2. 权限掩码检查
- **`dacl_mask_allows`**: 检查 DACL 是否允许指定 SID 的权限掩码
- **`path_mask_allows`**: 路径包装器，单次 DACL 获取后检查
- 支持 `require_all_bits` 模式：要求所有位或任意一位匹配

### 3. 写入权限专项检测
- **`dacl_has_write_allow_for_sid`**: 检查是否存在写入允许 ACE
- **`dacl_has_write_deny_for_sid`**: 检查是否存在写入拒绝 ACE
- 用于避免不必要的 ACL 重写和检测冲突权限

### 4. ACE 管理
- **`ensure_allow_mask_aces_with_inheritance`**: 确保指定 SID 具有允许 ACE（带继承）
- **`ensure_allow_write_aces`**: 确保写入权限（使用 `WRITE_ALLOW_MASK`）
- **`add_allow_ace`**: 添加读写执行允许 ACE
- **`add_deny_write_ace`**: 添加写入拒绝 ACE（防止写入/追加/删除）
- **`revoke_ace`**: 撤销指定 SID 的所有 ACE

### 5. NULL 设备访问
- **`allow_null_device`**: 为指定 SID 授予 NUL 设备的读写执行权限
- 解决沙箱进程 stdout/stderr 重定向到 NUL 时的访问问题

## 具体技术实现

### 关键数据结构

```rust
// 通用映射定义
const SE_KERNEL_OBJECT: u32 = 6;
const INHERIT_ONLY_ACE: u8 = 0x08;
const GENERIC_WRITE_MASK: u32 = 0x4000_0000;
const DENY_ACCESS: i32 = 3;

// 写入允许掩码（包含所有写入相关权限）
const WRITE_ALLOW_MASK: u32 = FILE_GENERIC_READ
    | FILE_GENERIC_WRITE
    | FILE_GENERIC_EXECUTE
    | DELETE
    | FILE_DELETE_CHILD;

// 写入拒绝掩码（全面阻止写入操作）
const deny_write_mask = FILE_GENERIC_WRITE
    | FILE_WRITE_DATA
    | FILE_APPEND_DATA
    | FILE_WRITE_EA
    | FILE_WRITE_ATTRIBUTES
    | GENERIC_WRITE_MASK
    | DELETE
    | FILE_DELETE_CHILD;
```

### 关键流程

#### DACL 权限检查流程
```
path_mask_allows(path, psids, desired_mask, require_all_bits)
  └─> fetch_dacl_handle(path)
  │     └─> CreateFileW(READ_CONTROL, FILE_FLAG_BACKUP_SEMANTICS)
  │     └─> GetSecurityInfo(DACL_SECURITY_INFORMATION)
  └─> dacl_mask_allows(p_dacl, psids, desired_mask, require_all_bits)
        └─> GetAclInformation(AclSizeInformation)
        └─> 遍历每个 ACE:
              - 跳过非 ACCESS_ALLOWED 类型
              - 跳过 INHERIT_ONLY_ACE
              - 检查 SID 匹配 (EqualSid)
              - MapGenericMask 转换掩码
              - 检查掩码位匹配
```

#### ACE 添加流程
```
ensure_allow_mask_aces_with_inheritance(path, sids, allow_mask, inheritance)
  └─> fetch_dacl_handle(path) 获取当前 DACL
  └─> 对每个 SID:
  │     如果已有权限则跳过
  │     构建 EXPLICIT_ACCESS_W (SET_ACCESS 模式)
  └─> SetEntriesInAclW(entries, p_dacl, &mut p_new_dacl)
  └─> SetNamedSecurityInfoW(DACL_SECURITY_INFORMATION)
  └─> LocalFree 清理
```

### Windows API 使用

| API | 用途 |
|-----|------|
| `CreateFileW` | 打开文件/目录获取句柄 |
| `GetSecurityInfo` / `GetNamedSecurityInfoW` | 获取安全描述符和 DACL |
| `SetSecurityInfo` / `SetNamedSecurityInfoW` | 设置安全描述符和 DACL |
| `GetAclInformation` | 获取 ACL 大小信息 |
| `GetAce` | 获取指定索引的 ACE |
| `SetEntriesInAclW` | 构建新 ACL（合并现有和新条目） |
| `EqualSid` | 比较两个 SID 是否相等 |
| `MapGenericMask` | 将通用权限映射到标准/特定权限 |
| `LocalFree` | 释放安全描述符内存 |

## 关键代码路径与文件引用

### 主要调用方

| 调用方 | 调用函数 | 用途 |
|--------|----------|------|
| `lib.rs` (windows_impl) | `add_allow_ace`, `add_deny_write_ace`, `revoke_ace`, `allow_null_device` | 沙箱执行时权限设置 |
| `elevated_impl.rs` | `allow_null_device` | 提升执行路径权限设置 |
| `audit.rs` | `add_deny_write_ace`, `path_mask_allows` | 世界可写目录审计 |
| `workspace_acl.rs` | `add_deny_write_ace` | 保护工作区敏感目录 |

### 被调用方

| 被调用模块 | 函数 | 用途 |
|------------|------|------|
| `winutil.rs` | `to_wide` | 字符串转宽字符 |

### 代码引用路径

```
codex-rs/windows-sandbox-rs/src/acl.rs
  ├─> 依赖: winutil.rs (to_wide)
  ├─> 被 lib.rs 公开导出:
  │     add_deny_write_ace, allow_null_device, ensure_allow_mask_aces,
  │     ensure_allow_mask_aces_with_inheritance, ensure_allow_write_aces,
  │     fetch_dacl_handle, path_mask_allows
  └─> Windows API: windows-sys (Win32::Security, Win32::Storage::FileSystem)
```

## 依赖与外部交互

### 内部依赖
- **`winutil.rs`**: `to_wide` 函数用于字符串编码转换

### 外部依赖
- **windows-sys**: Windows API 绑定
  - `Win32::Security::*`: ACL/SID/安全描述符操作
  - `Win32::Storage::FileSystem::*`: 文件权限常量
  - `Win32::Foundation::*`: 错误处理和内存管理

### 配置与数据
- 无直接配置文件依赖
- 通过参数接收路径和 SID 指针

## 风险、边界与改进建议

### 安全风险

1. **内存安全**
   - 大量使用 `unsafe` 块操作原始指针（SID、ACL、安全描述符）
   - 必须确保 `LocalFree` 正确调用，否则内存泄漏
   - SID 指针生命周期管理依赖调用方保证

2. **权限提升风险**
   - `add_allow_ace` 授予 `FILE_GENERIC_READ | FILE_GENERIC_WRITE | FILE_GENERIC_EXECUTE`
   - 若错误应用到系统目录可能导致安全漏洞

3. **竞争条件**
   - 检查-修改 ACL 的操作非原子性
   - 多进程同时修改同一文件 ACL 可能产生不一致状态

### 边界条件

| 边界 | 处理 |
|------|------|
| NULL DACL | `dacl_mask_allows` 返回 `false`（拒绝访问） |
| `GetAclInformation` 失败 | 返回 `false`（保守策略） |
| `GetAce` 失败 | 跳过该 ACE，继续处理 |
| 路径不存在 | `fetch_dacl_handle` 返回错误 |
| 继承标志 | 支持 `CONTAINER_INHERIT_ACE | OBJECT_INHERIT_ACE` |

### 改进建议

1. **错误处理增强**
   ```rust
   // 当前: 返回 bool，信息不足
   // 建议: 返回 Result<bool, AclError> 以区分不同失败原因
   ```

2. **批量操作优化**
   - 当前 `ensure_allow_mask_aces` 对每个 SID 单独调用 `SetEntriesInAclW` 和 `SetNamedSecurityInfoW`
   - 建议合并多个 SID 的条目一次性应用

3. **事务性 ACL 修改**
   - 考虑使用 Windows 事务性 NTFS（TxF）或至少提供回滚机制

4. **缓存机制**
   - DACL 获取操作较昂贵，可考虑在批量检查时缓存结果

5. **审计日志**
   - 当前仅通过返回值告知调用方是否添加了 ACE
   - 建议增加结构化日志记录权限变更

6. **类型安全**
   - 使用 `NonNull<c_void>` 替代裸指针表示 SID
   - 考虑实现 RAII 包装器自动管理 `LocalFree`

### 测试覆盖

模块包含基础测试，但以下场景建议补充：
- 大型 ACL（>1000 条目）的性能测试
- 并发 ACL 修改的竞争条件测试
- 特殊路径（长路径、UNC 路径、符号链接）测试
- 内存不足情况下的错误处理测试
