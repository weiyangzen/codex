# workspace_acl.rs 研究文档

## 场景与职责

`workspace_acl.rs` 是 Codex Windows Sandbox 的**工作区 ACL 保护模块**，专门负责保护工作区内的敏感元数据目录（`.codex` 和 `.agents`）免受沙箱内进程的篡改。该模块通过添加拒绝写入的访问控制项（Deny ACE）来实现保护。

该模块的设计特点：
- **单一职责**：专注于工作区元数据保护
- **轻量级**：仅 30 行代码，功能聚焦
- **安全优先**：使用拒绝 ACE（Deny ACE）确保即使其他允许规则存在，写入操作仍被阻止

## 功能点目的

### 1. 工作区元数据保护
- **`.codex` 目录保护**：防止沙箱进程修改 Codex 配置和状态
- **`.agents` 目录保护**：防止沙箱进程修改代理相关数据

### 2. 工作区隔离
- 使用工作区特定的 Capability SID 作为拒绝主体
- 确保不同工作区的沙箱相互隔离

### 3. 条件保护
- 仅当目录存在时才应用保护
- 避免在目录未创建时出错

## 具体技术实现

### 关键函数

#### 检查是否为命令 CWD (`is_command_cwd_root`)

```rust
pub fn is_command_cwd_root(root: &Path, canonical_command_cwd: &Path) -> bool {
    canonicalize_path(root) == canonical_command_cwd
}
```

- 比较规范化后的路径
- 用于确定某个根目录是否是命令执行的工作目录
- 在 `setup_main_win.rs` 中用于决定使用哪个 Capability SID

#### 保护 .codex 目录 (`protect_workspace_codex_dir`)

```rust
/// # Safety
/// Caller must ensure `psid` is a valid SID pointer.
pub unsafe fn protect_workspace_codex_dir(cwd: &Path, psid: *mut c_void) -> Result<bool> {
    protect_workspace_subdir(cwd, psid, ".codex")
}
```

#### 保护 .agents 目录 (`protect_workspace_agents_dir`)

```rust
/// # Safety
/// Caller must ensure `psid` is a valid SID pointer.
pub unsafe fn protect_workspace_agents_dir(cwd: &Path, psid: *mut c_void) -> Result<bool> {
    protect_workspace_subdir(cwd, psid, ".agents")
}
```

#### 内部保护实现 (`protect_workspace_subdir`)

```rust
unsafe fn protect_workspace_subdir(cwd: &Path, psid: *mut c_void, subdir: &str) -> Result<bool> {
    let path = cwd.join(subdir);
    if path.is_dir() {
        add_deny_write_ace(&path, psid)
    } else {
        Ok(false)
    }
}
```

流程：
1. 构建子目录路径（`cwd.join(subdir)`）
2. 检查目录是否存在（`path.is_dir()`）
3. 如果存在，调用 `add_deny_write_ace` 添加拒绝写入 ACE
4. 返回 `true`（已应用保护）或 `false`（目录不存在，跳过）

### 依赖的 ACL 操作

`add_deny_write_ace` 函数（来自 `acl.rs`）执行以下操作：

```rust
// 伪代码示意
fn add_deny_write_ace(path: &Path, psid: *mut c_void) -> Result<bool> {
    // 1. 获取当前 DACL
    // 2. 检查是否已存在拒绝写入 ACE（避免重复）
    // 3. 创建新的拒绝写入 EXPLICIT_ACCESS_W：
    //    - grfAccessPermissions: FILE_GENERIC_WRITE | DELETE | ...
    //    - grfAccessMode: DENY_ACCESS (3)
    //    - grfInheritance: CONTAINER_INHERIT_ACE | OBJECT_INHERIT_ACE
    // 4. 使用 SetEntriesInAclW 合并到现有 DACL
    // 5. 使用 SetNamedSecurityInfoW 应用新 DACL
}
```

拒绝权限掩码：
```rust
const DENY_WRITE_MASK: u32 = FILE_GENERIC_WRITE
    | FILE_WRITE_DATA
    | FILE_APPEND_DATA
    | FILE_WRITE_EA
    | FILE_WRITE_ATTRIBUTES
    | GENERIC_WRITE_MASK
    | DELETE
    | FILE_DELETE_CHILD;
```

### Windows API 使用

| 功能 | API 函数 |
|------|----------|
| ACL 操作 | `add_deny_write_ace`（来自 acl.rs） |
| 路径检查 | `std::path::Path::is_dir` |
| 路径规范化 | `canonicalize_path`（来自 path_normalization） |

## 关键代码路径与文件引用

### 本文件内部函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `is_command_cwd_root` | 7-9 | 检查路径是否为命令 CWD |
| `protect_workspace_codex_dir` | 13-15 | 保护 .codex 目录 |
| `protect_workspace_agents_dir` | 19-21 | 保护 .agents 目录 |
| `protect_workspace_subdir` | 23-30 | 内部保护实现 |

### 调用的外部模块

| 模块 | 函数 | 用途 |
|------|------|------|
| `acl` | `add_deny_write_ace` | 添加拒绝写入 ACE |
| `path_normalization` | `canonicalize_path` | 路径规范化 |

### 调用方

| 文件 | 函数 | 场景 |
|------|------|------|
| `lib.rs` | `is_command_cwd_root` | 导出供外部使用 |
| `lib.rs` | `protect_workspace_codex_dir` | 导出供外部使用 |
| `lib.rs` | `protect_workspace_agents_dir` | 导出供外部使用 |
| `lib.rs` (windows_impl) | `protect_workspace_codex_dir` | 运行沙箱时保护 |
| `lib.rs` (windows_impl) | `protect_workspace_agents_dir` | 运行沙箱时保护 |
| `setup_main_win.rs` | `protect_workspace_codex_dir` | 设置时保护 |
| `setup_main_win.rs` | `protect_workspace_agents_dir` | 设置时保护 |

### 调用流程

```
setup_main_win.rs::run_setup_full
    |
    |-- 1. 获取 workspace_psid（工作区特定 Capability SID）
    |
    |-- 2. protect_workspace_codex_dir(cwd, workspace_psid)
    |       |
    |       |-- add_deny_write_ace(cwd/.codex, workspace_psid)
    |               |
    |               |-- GetNamedSecurityInfoW (获取当前 DACL)
    |               |-- SetEntriesInAclW (添加拒绝 ACE)
    |               |-- SetNamedSecurityInfoW (应用新 DACL)
    |
    |-- 3. protect_workspace_agents_dir(cwd, workspace_psid)
            |
            |-- add_deny_write_ace(cwd/.agents, workspace_psid)
```

## 依赖与外部交互

### 输入依赖

1. **工作区路径**：当前命令执行的工作目录（`command_cwd`）
2. **Capability SID**：工作区特定的 Capability SID 指针
3. **目录存在性**：`.codex` 和 `.agents` 目录必须已存在才会应用保护

### 输出产物

1. **ACL 修改**：目标目录的 DACL 添加拒绝写入 ACE
2. **返回状态**：
   - `Ok(true)`：成功应用保护
   - `Ok(false)`：目录不存在，跳过
   - `Err(...)`：操作失败

### 与沙箱安全模型的关系

```
沙箱安全层次：

1. 受限令牌（token.rs）
   └─ 移除管理员权限
   
2. Capability SID（cap.rs）
   └─ 为沙箱进程添加特定 Capability
   
3. 文件系统 ACL（acl.rs）
   └─ 为 Capability SID 授予允许权限
   
4. 工作区保护（workspace_acl.rs）
   └─ 为 Capability SID 添加拒绝权限（.codex/.agents）
```

## 风险、边界与改进建议

### 安全风险

1. **竞态条件**：检查目录存在性和应用 ACL 之间有时间窗口
   - 风险：恶意进程在检查后立即创建目录并写入
   - 缓解：在设置阶段尽早应用保护
   - 建议：考虑使用原子操作或文件系统监控

2. **SID 有效性**：依赖调用者提供有效的 SID 指针
   - 风险：无效指针可能导致崩溃或安全漏洞
   - 缓解：函数标记为 `unsafe`，文档明确要求调用者保证有效性
   - 建议：添加调试版本的断言检查

3. **权限继承**：拒绝 ACE 设置了继承标志
   - 风险：子目录和文件继承拒绝规则，可能影响正常操作
   - 缓解：这是预期行为，确保元数据完整性
   - 建议：明确文档化继承行为

### 边界情况

1. **目录不存在**：返回 `Ok(false)`，不报错
   - 设计意图：允许延迟创建，下次设置时会再次尝试
   
2. **已存在拒绝 ACE**：`add_deny_write_ace` 会检查避免重复添加
   - 实现：通过 `dacl_has_write_deny_for_sid` 检查
   
3. **路径规范化**：`is_command_cwd_root` 使用规范化路径比较
   - 处理：不同表示形式的相同路径（如大小写、分隔符）

4. **符号链接**：未明确处理符号链接
   - 风险：可能跟随符号链接到意外位置
   - 建议：添加 `std::fs::metadata` 检查文件类型

### 改进建议

1. **功能扩展**：
   - 支持保护其他元数据目录（如 `.git`）
   - 添加配置选项允许用户自定义保护列表
   - 支持递归保护子目录

2. **错误处理**：
   - 区分"目录不存在"和"权限不足"错误
   - 添加更详细的错误上下文（哪个目录、哪个 SID）

3. **性能优化**：
   - 批量处理多个目录的 ACL 操作
   - 缓存目录存在性检查结果

4. **安全加固**：
   - 验证目标路径在工作区内（防止路径遍历）
   - 添加审计日志记录保护操作
   - 考虑使用完整性级别（Integrity Level）替代或补充 DACL

5. **代码结构**：
   - 当前文件较小（30 行），保持现状即可
   - 如功能扩展，可考虑拆分为 `workspace_protection` 模块

6. **测试覆盖**：
   - 添加单元测试：模拟目录存在/不存在场景
   - 添加集成测试：验证 ACL 实际应用效果
   - 测试不同文件系统（NTFS、ReFS）的兼容性

7. **文档完善**：
   - 添加关于保护机制的架构图
   - 解释为什么使用 Deny ACE 而非移除 Allow ACE
   - 说明与 Windows 继承模型的交互
