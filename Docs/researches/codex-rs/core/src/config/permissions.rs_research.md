# Permissions 研究文档

## 场景与职责

`permissions.rs` 是 Codex 核心配置模块中的权限配置解析器，负责将 TOML 格式的权限配置转换为内部使用的结构化策略。它处理两大权限领域：

1. **文件系统权限**：控制 AI 代理可以访问哪些文件和目录
2. **网络权限**：控制 AI 代理可以访问哪些网络资源

主要使用场景：
- **用户配置解析**：从 `config.toml` 的 `[permissions]` 部分读取配置
- **项目级权限**：从 `.codex/permissions.toml` 加载项目特定权限
- **企业策略执行**：解析托管策略中的权限配置
- **沙箱初始化**：为不同沙箱模式准备权限策略

## 功能点目的

### 1. TOML 配置结构定义
定义权限配置的序列化/反序列化结构：
- `PermissionsToml`：权限配置集合（多 profile）
- `PermissionProfileToml`：单个权限 profile
- `FilesystemPermissionsToml`：文件系统权限集合
- `FilesystemPermissionToml`：单个文件系统权限（支持简化或作用域格式）
- `NetworkToml`：网络权限配置

### 2. 文件系统权限编译 (`compile_permission_profile`)
将 TOML 配置转换为内部 `FileSystemSandboxPolicy`：
- 解析特殊路径（`:root`, `:minimal`, `:project_roots`, `:tmpdir`）
- 处理绝对路径和相对子路径
- 支持 Windows 路径规范化（处理 `\\?\` 前缀）

### 3. 网络权限编译 (`compile_network_sandbox_policy`)
将网络配置转换为 `NetworkSandboxPolicy`：
- `enabled = true` → `NetworkSandboxPolicy::Enabled`
- 其他情况 → `NetworkSandboxPolicy::Restricted`

### 4. 配置应用 (`apply_to_network_proxy_config`)
将 `NetworkToml` 配置应用到 `NetworkProxyConfig`

## 具体技术实现

### 关键数据结构

```rust
// 多 profile 权限配置集合
#[derive(Serialize, Deserialize, Debug, Clone, Default, PartialEq, Eq, JsonSchema)]
pub struct PermissionsToml {
    #[serde(flatten)]
    pub entries: BTreeMap<String, PermissionProfileToml>,
}

// 单个权限 profile
#[derive(Serialize, Deserialize, Debug, Clone, Default, PartialEq, Eq, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct PermissionProfileToml {
    pub filesystem: Option<FilesystemPermissionsToml>,
    pub network: Option<NetworkToml>,
}

// 文件系统权限（支持两种格式）
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema)]
#[serde(untagged)]
pub enum FilesystemPermissionToml {
    // 简化格式: "/path" = "read"
    Access(FileSystemAccessMode),
    // 作用域格式: "/base" = { "subdir" = "read" }
    Scoped(BTreeMap<String, FileSystemAccessMode>),
}

// 网络权限配置
#[derive(Serialize, Deserialize, Debug, Clone, Default, PartialEq, Eq, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct NetworkToml {
    pub enabled: Option<bool>,
    pub proxy_url: Option<String>,
    pub enable_socks5: Option<bool>,
    pub socks_url: Option<String>,
    pub mode: Option<NetworkMode>,
    pub allowed_domains: Option<Vec<String>>,
    pub denied_domains: Option<Vec<String>>,
    // ... 其他字段
}
```

### 特殊路径解析

```rust
// 前向兼容的特殊路径解析器
fn parse_special_path(path: &str) -> Option<FileSystemSpecialPath> {
    match path {
        ":root" => Some(FileSystemSpecialPath::Root),
        ":minimal" => Some(FileSystemSpecialPath::Minimal),
        ":project_roots" => Some(FileSystemSpecialPath::project_roots(/*subpath*/ None)),
        ":tmpdir" => Some(FileSystemSpecialPath::Tmpdir),
        _ if path.starts_with(':') => {
            // 未知特殊路径：包装为 Unknown，不报错
            Some(FileSystemSpecialPath::unknown(path, /*subpath*/ None))
        }
        _ => None,
    }
}
```

### 路径解析流程

```
路径字符串
    ↓
parse_special_path() ──是特殊路径？──→ FileSystemPath::Special
    ↓ 否
parse_absolute_path()
    ↓
normalize_absolute_path_for_platform() ──Windows？──→ 处理 \\?\ 前缀
    ↓
验证绝对路径（或 ~/ 开头）
    ↓
FileSystemPath::Path { path: AbsolutePathBuf }
```

### Windows 路径规范化

```rust
fn normalize_windows_device_path(path: &str) -> Option<String> {
    // \\?\UNC\server\share → \\server\share
    if let Some(unc) = path.strip_prefix(r"\\?\UNC\") {
        return Some(format!(r"\\{unc}"));
    }
    // \\?\C:\path → C:\path
    if let Some(path) = path.strip_prefix(r"\\?\")
        && is_windows_drive_absolute_path(path)
    {
        return Some(path.to_string());
    }
    None
}
```

### 作用域路径编译

```rust
fn compile_scoped_filesystem_path(
    path: &str,      // 基础路径，如 ":project_roots" 或 "/home/user"
    subpath: &str,   // 子路径，如 "src" 或 "projects/myapp"
    startup_warnings: &mut Vec<String>,
) -> io::Result<FileSystemPath> {
    if subpath == "." {
        // 子路径为 "." 时，退化为普通路径
        return compile_filesystem_path(path, startup_warnings);
    }

    if let Some(special) = parse_special_path(path) {
        // 特殊路径 + 子路径
        let subpath = parse_relative_subpath(subpath)?;
        match special {
            FileSystemSpecialPath::ProjectRoots { .. } => {
                Ok(FileSystemPath::Special {
                    value: FileSystemSpecialPath::project_roots(Some(subpath)),
                })
            }
            // 不支持子路径的特殊路径报错
            _ => Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                format!("filesystem path `{path}` does not support nested entries"),
            )),
        }
    } else {
        // 绝对路径 + 子路径
        let subpath = parse_relative_subpath(subpath)?;
        let base = parse_absolute_path(path)?;
        let path = AbsolutePathBuf::resolve_path_against_base(&subpath, base.as_path())?;
        Ok(FileSystemPath::Path { path })
    }
}
```

## 关键代码路径与文件引用

### 本文件核心函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `compile_permission_profile` | 159-191 | 主入口：编译权限 profile |
| `compile_network_sandbox_policy` | 193-202 | 编译网络沙箱策略 |
| `compile_filesystem_permission` | 204-225 | 编译单个文件系统权限 |
| `compile_filesystem_path` | 227-238 | 编译文件系统路径 |
| `compile_scoped_filesystem_path` | 240-273 | 编译作用域路径 |
| `parse_special_path` | 280-291 | 解析特殊路径 |
| `parse_absolute_path` | 293-309 | 解析绝对路径 |
| `normalize_windows_device_path` | 331-349 | Windows 路径规范化 |
| `apply_to_network_proxy_config` | 86-129 | 应用网络配置 |
| `network_proxy_config_from_profile_network` | 138-145 | 从 profile 网络配置创建代理配置 |
| `resolve_permission_profile` | 147-157 | 解析权限 profile |

### 调用方

| 文件 | 调用点 | 用途 |
|------|--------|------|
| `codex-rs/core/src/config/mod.rs` | `ConfigBuilder` | 构建配置时编译权限 |
| `codex-rs/core/src/network_proxy_loader.rs` | 网络配置加载 | 转换网络配置 |

### 被调用方/依赖

| 模块 | 来源 | 用途 |
|------|------|------|
| `codex_protocol::permissions::*` | 协议 crate | 文件系统和网络沙箱策略类型 |
| `codex_network_proxy::NetworkMode` | 网络代理 crate | 网络模式枚举 |
| `codex_utils_absolute_path::AbsolutePathBuf` | 工具 crate | 绝对路径处理 |

## 依赖与外部交互

### 配置层交互

```
┌─────────────────────────────────────────────────────────────────┐
│                     配置来源                                      │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────────┐ │
│  │ config.toml  │ │ .codex/      │ │ managed_config.toml      │ │
│  │ [permissions]│ │ permissions.toml │ │ [permissions]          │ │
│  └──────────────┘ └──────────────┘ └──────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              PermissionsToml::deserialize()                      │
│                      (serde)                                     │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              compile_permission_profile()                        │
│                    (本文件核心逻辑)                              │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              FileSystemSandboxPolicy                             │
│              NetworkSandboxPolicy                                │
│                    (codex_protocol)                              │
└─────────────────────────────────────────────────────────────────┘
```

### 特殊路径语义

| 特殊路径 | 含义 | 支持子路径 |
|---------|------|-----------|
| `:root` | 文件系统根目录 | ❌ |
| `:minimal` | 最小权限集 | ❌ |
| `:project_roots` | 项目根目录列表 | ✅ |
| `:tmpdir` | 临时目录 | ❌ |
| `:unknown` | 未知特殊路径（前向兼容） | 视情况而定 |

## 风险、边界与改进建议

### 已知风险

1. **路径遍历风险**
   - `parse_relative_subpath` 严格检查 `..` 和 `.` 组件
   - 但依赖调用方正确使用 `resolve_path_against_base`
   - 代码位置：第 363-380 行

2. **Windows 路径处理复杂性**
   - 多种设备路径前缀（`\\?\`, `\\.\`, `\\?\UNC\`）
   - 容易遗漏边界情况
   - 代码位置：第 331-349 行

3. **前向兼容性风险**
   - 未知特殊路径被包装为 `Unknown` 并忽略
   - 可能导致用户配置意外失效而不报错
   - 代码位置：第 280-291 行

### 边界情况

1. **空权限配置**
   - 触发 `missing_filesystem_entries_warning`
   - 文件系统访问保持受限

2. **大小写敏感**
   - Windows 路径不区分大小写，但比较时未统一处理
   - 可能导致重复路径或权限绕过

3. **符号链接**
   - 路径解析不跟随符号链接
   - 依赖上层调用方处理

### 改进建议

1. **增强路径验证**
   ```rust
   // 建议：添加路径规范化后的重复检测
   fn detect_duplicate_paths(entries: &[FileSystemSandboxEntry]) -> Vec<String> {
       // 检测重叠或重复的权限配置
   }
   ```

2. **改进错误信息**
   ```rust
   // 建议：包含配置来源信息
   Err(io::Error::new(
       io::ErrorKind::InvalidInput,
       format!("in profile `{profile_name}`: filesystem path `{path}` ..."),
   ))
   ```

3. **支持更多特殊路径**
   - `:home` - 用户主目录
   - `:workspace` - 当前工作区
   - `:codex_home` - Codex 配置目录

4. **通配符支持**
   ```toml
   [permissions.default.filesystem]
   "/home/user/projects/*" = "read"  # 通配符匹配
   "*.log" = "read"                   # 文件模式匹配
   ```

5. **权限继承**
   ```toml
   [permissions.base]
   filesystem = { ":project_roots" = "read" }
   
   [permissions.extended]
   extends = "base"  # 继承 base 权限
   filesystem = { ":project_roots" = { "src" = "write" } }  # 扩展
   ```

### 测试覆盖

当前测试文件 `permissions_tests.rs` 仅包含 1 个测试（Windows 路径规范化）。建议补充：

1. 特殊路径解析测试
2. 作用域路径编译测试
3. 网络权限编译测试
4. 错误处理测试
5. 跨平台路径测试
