# build.rs 研究文档

## 场景与职责

`build.rs` 是 `codex-execpolicy-legacy` crate 的构建脚本（build script）。它的唯一职责是告诉 Cargo 在 `src/default.policy` 文件变更时重新编译 crate。这是确保策略文件修改能及时生效的关键机制。

## 功能点目的

### 1. 变更检测声明
通过输出 `cargo:rerun-if-changed` 指令，告诉 Cargo 构建系统监控特定文件的变更。

### 2. 编译触发
当监控的文件发生变更时，Cargo 会自动重新运行构建脚本并重新编译依赖该文件的代码。

## 具体技术实现

### 代码分析

```rust
fn main() {
    println!("cargo:rerun-if-changed=src/default.policy");
}
```

这行代码输出一个 Cargo 构建脚本指令：
- `cargo:` 前缀表示这是给 Cargo 的指令
- `rerun-if-changed=<path>` 表示当指定路径的文件变更时，重新运行构建脚本

### 与代码的关联

在 `src/lib.rs` 中：

```rust
const DEFAULT_POLICY: &str = include_str!("default.policy");

pub fn get_default_policy() -> starlark::Result<Policy> {
    let parser = PolicyParser::new("#default", DEFAULT_POLICY);
    parser.parse()
}
```

`include_str!` 宏在编译时将 `default.policy` 文件内容嵌入二进制。`build.rs` 确保当策略文件修改时，这个嵌入的内容会被更新。

## 关键代码路径与文件引用

- **监控文件**: `src/default.policy` - 默认执行策略定义
- **使用位置**: `src/lib.rs` - 通过 `include_str!` 嵌入策略内容
- **构建配置**: `Cargo.toml` - 定义了 crate 的构建方式

## 依赖与外部交互

### Cargo 构建系统
```
build.rs 输出
    │
    └──► Cargo 解析指令
            │
            └──► 监控 src/default.policy
                    │
                    └──► 文件变更时触发重新编译
```

### Bazel 构建的交互
- Bazel 使用不同的变更检测机制（通过 `BUILD.bazel` 中的 `compile_data`）
- `build.rs` 的 `rerun-if-changed` 对 Bazel 构建无效
- 两种构建系统需要分别维护变更检测配置

## 风险、边界与改进建议

### 风险

1. **构建系统不一致**
   - Cargo 依赖 `build.rs` 的 `rerun-if-changed`
   - Bazel 依赖 `BUILD.bazel` 的 `compile_data`
   - 两者需要手动同步，容易遗漏

2. **路径硬编码**
   - 路径 `src/default.policy` 是硬编码的
   - 移动文件时需要同步修改 `build.rs` 和 `lib.rs`

### 边界

1. **功能单一**
   - 该构建脚本仅做变更检测，不做代码生成
   - 不处理环境变量检测
   - 不处理平台特定配置

2. **Cargo 专用**
   - 指令仅对 Cargo 构建有效
   - 其他构建系统（如 Bazel、Ninja）忽略此文件

### 改进建议

1. **统一变更检测**
   - 考虑在 `defs.bzl` 中添加检查，确保 `compile_data` 和 `build.rs` 同步
   - 或添加 CI 检查验证两者一致性

2. **路径常量化**
   ```rust
   const POLICY_FILE: &str = "src/default.policy";
   
   fn main() {
       println!("cargo:rerun-if-changed={}", POLICY_FILE);
   }
   ```
   虽然改进有限，但为后续扩展预留空间。

3. **添加验证**
   ```rust
   use std::path::Path;
   
   fn main() {
       let policy_path = "src/default.policy";
       println!("cargo:rerun-if-changed={}", policy_path);
       
       // 可选：构建时验证文件存在
       if !Path::new(policy_path).exists() {
           panic!("Policy file not found: {}", policy_path);
       }
   }
   ```

4. **考虑移除**
   - 如果项目主要使用 Bazel 构建，可以考虑移除 `build.rs`
   - 但需要确保 Cargo 用户仍能正确获得变更检测

5. **文档同步**
   - 在 `build.rs` 顶部添加注释，说明对应的 Bazel 配置位置
   - 在 `BUILD.bazel` 中添加注释，指向 `build.rs`
