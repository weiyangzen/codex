# path_normalization.rs 深度研究文档

## 场景与职责

`path_normalization.rs` 是 Windows Sandbox 模块中的**路径规范化工具**，提供跨平台一致的路径处理能力。该模块解决了 Windows 路径比较和键值化的常见问题，如路径分隔符差异、大小写不敏感等。

### 核心职责
1. **路径规范化**：将相对路径转换为绝对规范路径
2. **路径键值化**：生成可用于哈希表键的统一格式路径字符串
3. **跨平台兼容**：在 Windows 上处理大小写不敏感和反斜杠问题

## 功能点目的

### 1. `canonicalize_path` - 路径规范化
```rust
pub fn canonicalize_path(path: &Path) -> PathBuf
```
- **用途**：将任意路径转换为规范化的绝对路径
- **实现**：使用 `dunce::canonicalize`，失败时返回原路径的副本
- **特点**：
  - 解析符号链接
  - 处理 `.` 和 `..` 组件
  - 转换为绝对路径

### 2. `canonical_path_key` - 路径键值化
```rust
pub fn canonical_path_key(path: &Path) -> String
```
- **用途**：生成用于比较和哈希的标准化路径键
- **转换步骤**：
  1. 规范化路径（`canonicalize_path`）
  2. 转换为字符串（使用 `to_string_lossy`）
  3. 反斜杠替换为正斜杠（`replace('\\', "/")`）
  4. 转换为小写（`to_ascii_lowercase`）

**示例转换**：
```
C:\Users\Dev\Repo  →  c:/users/dev/repo
C:/Users/DEV/Repo  →  c:/users/dev/repo
```

## 具体技术实现

### dunce 库的使用
```rust
use dunce::canonicalize;
```
- `dunce` 是 `std::fs::canonicalize` 的改进版本
- 在 Windows 上避免返回 `\\?\` 前缀的 UNC 路径
- 保持路径的可读性和可用性

### 错误处理策略
```rust
dunce::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
```
- 规范化失败时不返回错误
- 回退到原路径的副本
- 确保函数始终返回有效的 `PathBuf`

### 字符串转换
```rust
.canonicalize_path(path)
.to_string_lossy()           // PathBuf → String（处理无效 UTF-8）
.replace('\\', "/")         // 统一分隔符
.to_ascii_lowercase()       // 统一大小写
```

## 关键代码路径与文件引用

### 内部依赖
| 依赖 | 类型 | 用途 |
|------|------|------|
| `dunce` | crate | 改进的路径规范化 |
| `std::path::{Path, PathBuf}` | 标准库 | 路径类型 |

### 被调用方
| 调用方 | 函数 | 场景 |
|--------|------|------|
| `cap.rs` | `canonical_path_key` | 工作区 SID 键值化 |
| `setup_orchestrator.rs` | `canonical_path_key` | 路径去重和过滤 |
| `workspace_acl.rs` | `canonicalize_path` | 工作区路径比较 |

### 导出接口
```rust
#[cfg(target_os = "windows")]
pub use path_normalization::canonicalize_path;
#[cfg(target_os = "windows")]
pub use path_normalization::canonical_path_key;
```

## 依赖与外部交互

### 外部 Crate
- `dunce`：改进的 `canonicalize` 实现

### 标准库
- `std::path::Path`：路径引用类型
- `std::path::PathBuf`：拥有的路径类型

## 风险、边界与改进建议

### 已知风险

1. **规范化失败回退**
   - 问题：不存在的路径规范化会失败
   - 缓解：回退到原路径
   - 风险：键值可能不一致（某些路径规范化，某些不规范化）

2. **大小写不敏感假设**
   - 问题：`to_ascii_lowercase` 假设 ASCII 大小写映射
   - 风险：非 ASCII 字符（如某些 Unicode 字符）的大小写处理可能不正确
   - 缓解：Windows 路径通常使用 ASCII 字符

3. **UNC 路径**
   - 问题：网络路径（`\\server\share`）的处理
   - 缓解：`dunce` 库处理大部分情况

### 边界条件

1. **空路径**：返回空字符串
2. **相对路径**：尝试转换为绝对路径，失败则保留相对形式
3. **不存在的路径**：规范化失败，返回原路径
4. **非 UTF-8 路径**：`to_string_lossy` 使用替换字符（�）
5. **末尾分隔符**：规范化后通常去除末尾分隔符

### 改进建议

1. **Unicode 大小写**
   - 当前：仅处理 ASCII 大小写
   - 建议：考虑使用 `to_lowercase()` 处理完整 Unicode
   - 注意：可能影响性能

2. **路径验证**
   - 当前：静默处理规范化失败
   - 建议：添加可选的验证模式，返回错误而非回退

3. **缓存机制**
   - 当前：每次调用都执行规范化
   - 建议：添加 LRU 缓存，提高重复路径处理性能

4. **符号链接处理选项**
   - 当前：始终解析符号链接
   - 建议：提供选项控制是否解析符号链接

5. **平台特定优化**
   - 当前：使用 `dunce` 统一处理
   - 建议：在 Unix 平台上使用更轻量的实现

### 测试覆盖

模块包含以下单元测试：
- `canonical_path_key_normalizes_case_and_separators`：验证大小写和分隔符规范化

### 使用模式

```rust
// 路径去重
let mut seen: HashSet<String> = HashSet::new();
for path in paths {
    let key = canonical_path_key(path);
    if seen.insert(key) {
        unique_paths.push(path);
    }
}

// 工作区 SID 键
let workspace_key = canonical_path_key(cwd);
let sid = caps.workspace_by_cwd.get(&workspace_key);
```

### 性能特征

1. **文件系统访问**
   - `canonicalize` 需要访问文件系统
   - 可能涉及符号链接解析
   - 相对较慢，避免在热路径频繁调用

2. **字符串操作**
   - `replace` 和 `to_ascii_lowercase` 分配新字符串
   - 对于长路径有一定开销

3. **建议**
   - 缓存规范化结果
   - 批量处理路径时预分配容量
