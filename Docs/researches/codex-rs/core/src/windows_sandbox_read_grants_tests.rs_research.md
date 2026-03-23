# windows_sandbox_read_grants_tests.rs 研究文档

## 场景与职责

`windows_sandbox_read_grants_tests.rs` 是 `windows_sandbox_read_grants.rs` 的配套测试模块，负责验证非提升模式读取权限授予功能的输入验证逻辑。测试覆盖：

1. **路径验证**：验证相对路径、不存在路径、文件路径都被拒绝
2. **错误消息**：验证错误消息包含预期内容

注意：这些测试只验证输入验证逻辑，不涉及实际的沙盒配置刷新（需要 Windows 环境）。

## 功能点目的

### 测试用例设计意图

| 测试函数 | 目的 |
|----------|------|
| `rejects_relative_path` | 验证相对路径被拒绝 |
| `rejects_missing_path` | 验证不存在的路径被拒绝 |
| `rejects_file_path` | 验证文件路径被拒绝（要求是目录） |

## 具体技术实现

### 测试基础设施

```rust
fn policy() -> SandboxPolicy {
    SandboxPolicy::new_workspace_write_policy()
}
```

使用工作区写入策略作为测试策略。

### 测试 1：拒绝相对路径

```rust
#[test]
fn rejects_relative_path()
```

**流程**：
1. 创建临时目录
2. 尝试授予相对路径 `"relative"`
3. 验证返回错误
4. 验证错误消息包含 `"path must be absolute"`

**关键技术点**：
- 使用 `tempfile::TempDir` 创建隔离环境
- 使用 `Path::new("relative")` 构造相对路径
- 使用 `assert!` 验证错误消息

### 测试 2：拒绝不存在路径

```rust
#[test]
fn rejects_missing_path()
```

**流程**：
1. 创建临时目录
2. 构造不存在的路径 `tmp.path().join("does-not-exist")`
3. 尝试授予该路径
4. 验证返回错误
5. 验证错误消息包含 `"path does not exist"`

**关键技术点**：
- 路径构造但不创建文件/目录
- 验证存在性检查

### 测试 3：拒绝文件路径

```rust
#[test]
fn rejects_file_path()
```

**流程**：
1. 创建临时目录
2. 创建文件 `file.txt`
3. 尝试授予该文件路径
4. 验证返回错误
5. 验证错误消息包含 `"path must be a directory"`

**关键技术点**：
- 使用 `std::fs::write` 创建测试文件
- 验证目录类型检查

## 关键代码路径与文件引用

### 被测试代码

| 被测试项 | 定义位置 |
|----------|----------|
| `grant_read_root_non_elevated` | `windows_sandbox_read_grants.rs:8` |

### 测试依赖

| 依赖 | 用途 |
|------|------|
| `tempfile::TempDir` | 创建临时测试目录 |
| `SandboxPolicy` | 构造测试策略 |
| `HashMap` | 构造空环境变量映射 |

## 依赖与外部交互

### 文件系统操作

测试执行以下文件系统操作：
- 创建临时目录
- 创建测试文件
- 检查路径存在性（在 `grant_read_root_non_elevated` 内部）

### 模拟 vs 真实

这些测试使用真实的文件系统操作，但：
- 不调用实际的沙盒配置刷新
- 在验证失败后就返回，不会执行到刷新逻辑

## 风险、边界与改进建议

### 当前测试覆盖的不足

1. **缺少成功场景测试**
   - 未测试有效目录路径
   - 需要 Windows 环境才能完整测试

2. **缺少边界测试**
   - 空字符串路径
   - 根路径 `/`
   - 非常长路径
   - 包含特殊字符的路径

3. **缺少并发测试**
   - 未测试多线程同时授予

4. **缺少符号链接测试**
   - 未测试符号链接处理
   - `dunce::canonicalize` 的行为

5. **缺少 UNC 路径测试**
   - 未测试 Windows UNC 路径

### 改进建议

1. **添加成功测试（条件编译）**
```rust
#[test]
#[cfg(target_os = "windows")]
fn accepts_valid_directory() {
    let tmp = TempDir::new().expect("tempdir");
    let result = grant_read_root_non_elevated(
        &policy(),
        tmp.path(),
        tmp.path(),
        &HashMap::new(),
        tmp.path(),
        tmp.path(),
    );
    assert!(result.is_ok());
}
```

2. **添加边界测试**
```rust
#[test]
fn rejects_empty_path() {
    let tmp = TempDir::new().expect("tempdir");
    let err = grant_read_root_non_elevated(
        &policy(),
        tmp.path(),
        tmp.path(),
        &HashMap::new(),
        tmp.path(),
        Path::new(""),
    ).expect_err("empty path should fail");
    // 验证错误
}
```

3. **添加符号链接测试**
```rust
#[test]
fn handles_symlink_to_directory() {
    // 创建符号链接指向目录
    // 验证行为（应该跟随链接）
}

#[test]
fn handles_symlink_to_file() {
    // 创建符号链接指向文件
    // 验证被拒绝
}
```

4. **添加并发测试**
```rust
#[test]
fn concurrent_grants_do_not_panic() {
    // 多线程同时授予同一目录
    // 验证不 panic
}
```

### 潜在风险

1. **平台差异**
   - 测试在非 Windows 平台也能运行
   - 但部分行为可能有差异

2. **临时目录清理**
   - `TempDir` 在 Drop 时清理
   - 如果测试 panic，可能留下残留

3. **路径分隔符**
   - 测试使用 `/` 构造路径
   - Windows 也能处理，但最好使用 `PathBuf`

### 测试质量评估

| 维度 | 评分 | 说明 |
|------|------|------|
| 覆盖率 | 低 | 只覆盖验证逻辑 |
| 可读性 | 高 | 测试意图清晰 |
| 维护性 | 高 | 结构简单 |
| 可靠性 | 高 | 不依赖外部系统 |
| 平台兼容性 | 高 | 跨平台运行 |
