# windows_sandbox_read_grants.rs 研究文档

## 场景与职责

`windows_sandbox_read_grants.rs` 是 Codex Core 中负责 **Windows 沙盒非提升模式读取权限授予** 的模块。其核心职责是：

1. **验证读取根目录**：确保请求的路径符合要求（绝对路径、存在、是目录）
2. **授予读取权限**：为非提升模式的 Windows 沙盒授予额外的目录读取权限
3. **路径规范化**：使用 `dunce::canonicalize` 规范化路径

该模块主要用于在非提升模式下，动态扩展沙盒的读取访问范围。

## 功能点目的

### 1. 读取根目录授予

```rust
pub fn grant_read_root_non_elevated(
    policy: &SandboxPolicy,
    policy_cwd: &Path,
    command_cwd: &Path,
    env_map: &HashMap<String, String>,
    codex_home: &Path,
    read_root: &Path,
) -> Result<PathBuf>
```

**验证条件**：
1. 路径必须是绝对路径
2. 路径必须存在
3. 路径必须是目录

**成功返回**：规范化后的路径

### 2. 权限刷新

通过调用 `run_setup_refresh_with_extra_read_roots` 刷新沙盒配置，添加新的读取根目录。

## 具体技术实现

### 核心流程

```rust
pub fn grant_read_root_non_elevated(
    policy: &SandboxPolicy,
    policy_cwd: &Path,
    command_cwd: &Path,
    env_map: &HashMap<String, String>,
    codex_home: &Path,
    read_root: &Path,
) -> Result<PathBuf> {
    // 1. 验证绝对路径
    if !read_root.is_absolute() {
        anyhow::bail!("path must be absolute: {}", read_root.display());
    }
    
    // 2. 验证存在
    if !read_root.exists() {
        anyhow::bail!("path does not exist: {}", read_root.display());
    }
    
    // 3. 验证是目录
    if !read_root.is_dir() {
        anyhow::bail!("path must be a directory: {}", read_root.display());
    }

    // 4. 规范化路径
    let canonical_root = dunce::canonicalize(read_root)?;
    
    // 5. 刷新沙盒配置
    run_setup_refresh_with_extra_read_roots(
        policy,
        policy_cwd,
        command_cwd,
        env_map,
        codex_home,
        vec![canonical_root.clone()],
    )?;
    
    Ok(canonical_root)
}
```

### 路径规范化

使用 `dunce::canonicalize`：
- 解析所有符号链接
- 规范化路径分隔符
- 处理 Windows UNC 路径
- 比 `std::fs::canonicalize` 更友好（不产生 `\\?\` 前缀）

### 依赖函数

```rust
use crate::windows_sandbox::run_setup_refresh_with_extra_read_roots;
```

该函数定义在 `windows_sandbox.rs` 中，实际调用 `codex_windows_sandbox` crate 的实现。

## 关键代码路径与文件引用

### 本文件关键函数

| 函数 | 行号 | 说明 |
|------|------|------|
| `grant_read_root_non_elevated` | 8-36 | 主入口：授予读取权限 |

### 依赖文件

| 文件 | 依赖内容 |
|------|----------|
| `windows_sandbox.rs` | `run_setup_refresh_with_extra_read_roots` |
| `protocol.rs` | `SandboxPolicy` |
| `dunce` crate | 路径规范化 |

### 调用方

- 文件系统工具：当需要访问沙盒外的目录时
- 用户显式请求：通过 UI 或命令添加读取权限

## 依赖与外部交互

### 外部系统交互

1. **文件系统检查**
   - `read_root.exists()`
   - `read_root.is_dir()`
   - `dunce::canonicalize()`

2. **沙盒配置刷新**
   - 调用 `run_setup_refresh_with_extra_read_roots`
   - 最终调用 Windows 特定 API

### 错误处理

使用 `anyhow` 进行错误处理：
- 验证失败返回描述性错误
- 使用 `?` 传播底层错误

## 风险、边界与改进建议

### 风险点

1. **路径竞争条件**
   - 检查存在性和实际刷新之间有时间窗口
   - 目录可能被删除或修改

2. **符号链接安全**
   - `dunce::canonicalize` 解析符号链接
   - 可能访问到预期外的路径

3. **权限提升**
   - 授予额外读取权限可能降低安全性
   - 需要用户明确授权

### 边界情况

1. **空路径**
   - 未显式检查空路径
   - 会被绝对路径检查捕获

2. **非常长路径**
   - Windows 有路径长度限制
   - `dunce` 可能处理不了超长路径

3. **网络路径**
   - UNC 路径（`\\server\share`）
   - 需要特殊处理

4. **重复授予**
   - 同一目录多次授予
   - 当前实现无去重逻辑

### 改进建议

1. **添加缓存**
   - 记录已授予的目录
   - 避免重复刷新

2. **添加日志**
   - 记录授予操作
   - 便于审计和调试

3. **路径验证增强**
   - 检查路径是否在允许范围内
   - 防止访问敏感目录

4. **并发安全**
   - 考虑多线程同时授予
   - 添加适当的同步

5. **添加测试**
   - 当前无直接测试
   - 依赖 `windows_sandbox_read_grants_tests.rs`

### 相关测试

测试文件：`windows_sandbox_read_grants_tests.rs`

| 测试 | 说明 |
|------|------|
| `rejects_relative_path` | 验证拒绝相对路径 |
| `rejects_missing_path` | 验证拒绝不存在的路径 |
| `rejects_file_path` | 验证拒绝文件路径 |

### 代码质量评估

| 维度 | 评分 | 说明 |
|------|------|------|
| 简洁性 | 高 | 代码简洁，职责单一 |
| 功能性 | 高 | 完成设计目标 |
| 可测试性 | 中 | 依赖外部系统 |
| 文档 | 低 | 无文档注释 |
| 错误处理 | 高 | 清晰的错误信息 |
