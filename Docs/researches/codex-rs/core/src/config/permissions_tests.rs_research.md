# Permissions Tests 研究文档

## 场景与职责

`permissions_tests.rs` 是 `permissions.rs` 的配套单元测试文件。目前该文件非常精简，仅包含一个针对 Windows 路径规范化的测试。这反映了该模块的测试覆盖还有较大提升空间。

## 功能点目的

### 当前测试覆盖

1. **Windows 设备路径规范化测试**
   - 验证 `\\?\` 前缀的 verbatim 路径被正确简化
   - 确保 Windows 长路径支持正常工作

## 具体技术实现

### 唯一测试用例分析

```rust
#[test]
fn normalize_absolute_path_for_platform_simplifies_windows_verbatim_paths() {
    let parsed =
        normalize_absolute_path_for_platform(r"\\?\D:\c\x\worktrees\2508\swift-base", true);
    assert_eq!(parsed, PathBuf::from(r"D:\c\x\worktrees\2508\swift-base"));
}
```

**测试目的**：
- Windows API 允许使用 `\\?\` 前缀表示 verbatim 路径，支持超过 260 字符的长路径
- 这种路径格式在内部处理时需要简化为标准格式 `D:\path`
- 测试验证简化逻辑正确工作

**被测代码路径**：
- `permissions.rs` 第 320-329 行：`normalize_absolute_path_for_platform`
- `permissions.rs` 第 331-349 行：`normalize_windows_device_path`

## 关键代码路径与文件引用

### 本文件内容

| 函数 | 行号 | 描述 |
|------|------|------|
| `normalize_absolute_path_for_platform_simplifies_windows_verbatim_paths` | 5-9 | 唯一测试用例 |

### 被测代码

- `codex-rs/core/src/config/permissions.rs` 第 293-349 行

## 依赖与外部交互

### 测试依赖

```rust
use super::*;  // 导入 permissions.rs 的所有导出
use pretty_assertions::assert_eq;  // 更好的断言 diff
```

### 外部类型

| 类型 | 来源 | 用途 |
|------|------|------|
| `PathBuf` | `std::path` | 验证路径输出 |

## 风险、边界与改进建议

### 当前测试覆盖缺口（严重）

| 功能模块 | 测试覆盖 | 风险等级 |
|---------|---------|---------|
| Windows 路径规范化 | ✅ 1 个测试 | 低 |
| 特殊路径解析 (`parse_special_path`) | ❌ 无测试 | **高** |
| 绝对路径解析 (`parse_absolute_path`) | ❌ 无测试 | **高** |
| 作用域路径编译 (`compile_scoped_filesystem_path`) | ❌ 无测试 | **高** |
| 权限 profile 编译 (`compile_permission_profile`) | ❌ 无测试 | **高** |
| 网络权限编译 (`compile_network_sandbox_policy`) | ❌ 无测试 | **高** |
| 配置应用到代理 (`apply_to_network_proxy_config`) | ❌ 无测试 | **高** |
| 错误处理和警告 | ❌ 无测试 | **中** |

### 建议补充的测试用例

#### 1. 特殊路径解析测试

```rust
#[test]
fn parse_special_path_recognizes_known_paths() {
    assert!(matches!(
        parse_special_path(":root"),
        Some(FileSystemSpecialPath::Root)
    ));
    assert!(matches!(
        parse_special_path(":minimal"),
        Some(FileSystemSpecialPath::Minimal)
    ));
    assert!(matches!(
        parse_special_path(":project_roots"),
        Some(FileSystemSpecialPath::ProjectRoots { .. })
    ));
    assert!(matches!(
        parse_special_path(":tmpdir"),
        Some(FileSystemSpecialPath::Tmpdir)
    ));
}

#[test]
fn parse_special_path_wraps_unknown_paths() {
    let result = parse_special_path(":unknown_future_path");
    assert!(matches!(
        result,
        Some(FileSystemSpecialPath::Unknown { .. })
    ));
}

#[test]
fn parse_special_path_returns_none_for_normal_paths() {
    assert_eq!(parse_special_path("/home/user"), None);
    assert_eq!(parse_special_path("~/projects"), None);
    assert_eq!(parse_special_path("relative/path"), None);
}
```

#### 2. 绝对路径解析测试

```rust
#[test]
fn parse_absolute_path_accepts_unix_absolute_paths() {
    let result = parse_absolute_path("/home/user/projects");
    assert!(result.is_ok());
}

#[test]
fn parse_absolute_path_accepts_tilde_paths() {
    let result = parse_absolute_path("~/projects");
    assert!(result.is_ok());
}

#[test]
fn parse_absolute_path_rejects_relative_paths() {
    let result = parse_absolute_path("relative/path");
    assert!(result.is_err());
}

#[cfg(windows)]
#[test]
fn parse_absolute_path_accepts_windows_drive_paths() {
    let result = parse_absolute_path(r"C:\Users\test");
    assert!(result.is_ok());
}

#[cfg(windows)]
#[test]
fn parse_absolute_path_accepts_unc_paths() {
    let result = parse_absolute_path(r"\\server\share");
    assert!(result.is_ok());
}
```

#### 3. 作用域路径编译测试

```rust
#[test]
fn compile_scoped_filesystem_path_with_dot_subpath() {
    // 子路径为 "." 时应退化为普通路径
}

#[test]
fn compile_scoped_filesystem_path_with_special_path() {
    // :project_roots + "src" 应正确组合
}

#[test]
fn compile_scoped_filesystem_path_with_absolute_base() {
    // /home/user + "projects" 应解析为 /home/user/projects
}

#[test]
fn compile_scoped_filesystem_path_rejects_invalid_subpath() {
    // "..", ".", "/absolute" 应被拒绝
}

#[test]
fn compile_scoped_filesystem_path_rejects_nonspecial_with_subpath() {
    // :root + "subdir" 应报错（不支持子路径）
}
```

#### 4. 权限 Profile 编译测试

```rust
#[test]
fn compile_permission_profile_with_empty_filesystem_warns() {
    // 空 filesystem 配置应触发警告
}

#[test]
fn compile_permission_profile_with_missing_filesystem_warns() {
    // 缺少 filesystem 字段应触发警告
}

#[test]
fn compile_permission_profile_compiles_simple_access() {
    // "path" = "read" 格式
}

#[test]
fn compile_permission_profile_compiles_scoped_access() {
    // "base" = { "sub" = "read" } 格式
}

#[test]
fn compile_permission_profile_returns_error_for_undefined_profile() {
    // 引用不存在的 profile 应报错
}
```

#### 5. 网络权限编译测试

```rust
#[test]
fn compile_network_sandbox_policy_enabled_when_enabled_true() {
    let network = NetworkToml { enabled: Some(true), ..Default::default() };
    assert_eq!(compile_network_sandbox_policy(Some(&network)), NetworkSandboxPolicy::Enabled);
}

#[test]
fn compile_network_sandbox_policy_restricted_when_enabled_false() {
    let network = NetworkToml { enabled: Some(false), ..Default::default() };
    assert_eq!(compile_network_sandbox_policy(Some(&network)), NetworkSandboxPolicy::Restricted);
}

#[test]
fn compile_network_sandbox_policy_restricted_when_network_none() {
    assert_eq!(compile_network_sandbox_policy(None), NetworkSandboxPolicy::Restricted);
}
```

#### 6. 配置应用测试

```rust
#[test]
fn apply_to_network_proxy_config_updates_all_fields() {
    // 验证每个字段都被正确应用
}

#[test]
fn network_proxy_config_from_profile_network_with_none() {
    // None 输入应返回默认配置
}

#[test]
fn network_proxy_config_from_profile_network_with_some() {
    // Some(network) 应正确转换
}
```

#### 7. 警告生成测试

```rust
#[test]
fn unknown_special_path_generates_warning() {
    // 未知特殊路径应生成警告信息
}

#[test]
fn unknown_special_path_with_subpath_generates_warning() {
    // 带子路径的未知特殊路径应生成包含子路径的警告
}
```

### 测试组织建议

```rust
// 按功能模块组织测试
mod special_path_tests {
    use super::*;
    // ...
}

mod absolute_path_tests {
    use super::*;
    // ...
}

mod scoped_path_tests {
    use super::*;
    // ...
}

mod permission_profile_tests {
    use super::*;
    // ...
}

mod network_permission_tests {
    use super::*;
    // ...
}

#[cfg(windows)]
mod windows_path_tests {
    use super::*;
    // ...
}
```

### 优先级建议

| 优先级 | 测试类别 | 原因 |
|-------|---------|------|
| P0 | 权限 profile 编译 | 核心功能，影响安全策略 |
| P0 | 特殊路径解析 | 核心功能，配置解析基础 |
| P1 | 作用域路径编译 | 复杂逻辑，容易出错 |
| P1 | 绝对路径解析 | 跨平台兼容性关键 |
| P2 | 网络权限编译 | 相对简单，但需验证 |
| P2 | 警告生成 | 用户体验相关 |
| P3 | 边界情况 | 完善测试覆盖 |
