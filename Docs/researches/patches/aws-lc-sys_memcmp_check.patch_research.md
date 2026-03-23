# patches/aws-lc-sys_memcmp_check.patch 研究文档

## 场景与职责

### 目标 Crate

**`aws-lc-sys`** 是 AWS Libcrypto（AWS 的 OpenSSL 分支）的 Rust FFI 绑定 crate。它负责：
- 提供加密原语的 Rust 接口
- 在构建时编译底层的 C/C++ 加密库
- 执行各种编译器特性检测

### 问题场景

该补丁解决 `aws-lc-sys` 在 **Bazel 沙箱/隔离构建环境** 中的两个核心问题：

#### 问题 1：外部调试工具依赖

`aws-lc-sys` 的构建脚本会编译并运行一个测试程序来检测 `memcmp` 行为。默认情况下，编译器可能生成调试信息并调用 `dsymutil`（macOS 上的调试符号工具）。在 hermetic（封闭）构建沙箱中，这些外部工具不可用，导致构建失败。

#### 问题 2：Bazel 路径相对性问题

Bazel 构建使用 **execroot**（执行根目录）概念：
- 构建脚本在沙箱中运行，工作目录可能不是 execroot
- 编译器参数可能包含相对于 execroot 的路径（如 `bazel-out/...`）
- 当构建脚本尝试链接测试程序时，这些相对路径无法解析

### 补丁核心职责

| 职责 | 说明 |
|------|------|
| **移除调试工具依赖** | 过滤 `-g*` 参数，添加 `-g0` 禁用调试信息生成 |
| **路径规范化** | 将 Bazel 相对路径重写为绝对路径 |
| **沙箱兼容性** | 确保编译器检查在隔离环境中可执行 |

## 功能点目的

### 功能 1：调试参数清理

```rust
// 移除所有 -g 开头的参数（调试相关）
memcmp_compile_args.retain(|arg| {
    let Some(arg_str) = arg.to_str() else {
        return true;  // 非 UTF-8 参数保留
    };
    !arg_str.starts_with("-g")  // 过滤 -g, -g0, -g1, -gdwarf 等
});
// 显式禁用调试信息
memcmp_compile_args.push("-g0".into());
```

**目的**：
- 防止编译器生成调试符号
- 避免调用 `dsymutil` 等外部工具
- 减少沙箱依赖，加快编译速度

### 功能 2：Bazel 路径重写

```rust
// 检测是否在 Bazel 环境中
if let Some(execroot) = Self::bazel_execroot(self.manifest_dir.as_path()) {
    // 规范化所有编译参数中的路径
    for arg in &mut memcmp_compile_args {
        Self::rewrite_bazel_execroot_arg(execroot.as_path(), arg);
    }
}
```

**目的**：
- 将 `bazel-out/...` 相对路径转换为绝对路径
- 确保链接器能找到所需的库文件
- 使编译器检查在沙箱外也能正确链接

### 功能 3：路径重写逻辑

```rust
fn rewrite_bazel_execroot_arg(execroot: &Path, arg: &mut std::ffi::OsString) {
    let Some(arg_str) = arg.to_str() else { return };

    // 情况 1：纯路径以 bazel-out/ 开头
    if arg_str.starts_with("bazel-out/") {
        *arg = execroot.join(arg_str).into_os_string();
        return;
    }

    // 情况 2：-B 和 -L 标志后跟 bazel-out/ 路径
    for flag_prefix in ["-B", "-L"] {
        if let Some(path) = arg_str.strip_prefix(flag_prefix) {
            if path.starts_with("bazel-out/") {
                *arg = format!("{flag_prefix}{}", execroot.join(path).display()).into();
                return;
            }
        }
    }
}
```

### 功能 4：Execroot 检测

```rust
fn bazel_execroot(path: &Path) -> Option<PathBuf> {
    let mut prefix = PathBuf::new();
    for component in path.components() {
        // 查找 bazel-out 组件，其前面的路径就是 execroot
        if component.as_os_str() == "bazel-out" {
            return Some(prefix);
        }
        prefix.push(component.as_os_str());
    }
    None
}
```

**算法**：
- 遍历路径组件
- 找到 `bazel-out` 时，返回其前面的所有组件作为 execroot
- 示例：`/home/user/project/bazel-out/...` → execroot 是 `/home/user/project`

## 具体技术实现

### 补丁修改的文件

**原文件**：`aws-lc-sys` crate 的 `builder/cc_builder.rs`

**修改位置**：
1. 导入语句：添加 `Path` 到 `std::path` 的导入
2. `run_memcmp_check` 方法：在编译参数处理逻辑中插入新代码
3. 新增两个辅助方法：`rewrite_bazel_execroot_arg` 和 `bazel_execroot`

### 完整补丁结构

```diff
--- a/builder/cc_builder.rs
+++ b/builder/cc_builder.rs
@@ -26,7 +26,7 @@
 };
 use std::cell::Cell;
 use std::collections::HashMap;
-use std::path::PathBuf;
+use std::path::{Path, PathBuf};  // 添加 Path 导入
 
 #[non_exhaustive]
 #[derive(PartialEq, Eq)]
@@ -661,6 +661,16 @@
         }
         let mut memcmp_compile_args = Vec::from(memcmp_compiler.args());
 
+        // [插入] 调试参数清理
+        memcmp_compile_args.retain(|arg| {
+            let Some(arg_str) = arg.to_str() else {
+                return true;
+            };
+            !arg_str.starts_with("-g")
+        });
+        memcmp_compile_args.push("-g0".into());
+
         // This check invokes the compiled executable...
@@ -672,6 +682,15 @@
             }
         }
 
+        // [插入] Bazel 路径重写
+        if let Some(execroot) = Self::bazel_execroot(self.manifest_dir.as_path()) {
+            for arg in &mut memcmp_compile_args {
+                Self::rewrite_bazel_execroot_arg(execroot.as_path(), arg);
+            }
+        }
+
         memcmp_compile_args.push(...);
@@ -725,6 +744,40 @@
         }
         let _ = fs::remove_file(exec_path);
     }
+
+    // [新增] 路径重写辅助方法
+    fn rewrite_bazel_execroot_arg(execroot: &Path, arg: &mut std::ffi::OsString) {
+        // ... 实现 ...
+    }
+
+    // [新增] Execroot 检测方法
+    fn bazel_execroot(path: &Path) -> Option<PathBuf> {
+        // ... 实现 ...
+    }
+
     fn run_compiler_checks(&self, cc_build: &mut cc::Build) {
```

### 关键数据结构

#### 编译参数类型

```rust
// 来自 cc crate 的编译器参数
memcmp_compiler: cc::Build
memcmp_compile_args: Vec<std::ffi::OsString>  // 平台兼容的字符串类型
```

#### 路径类型

```rust
execroot: PathBuf      // Bazel 执行根目录
manifest_dir: PathBuf  // Cargo 的 manifest 目录（包含 Cargo.toml）
```

### 控制流程

```
run_memcmp_check()
    │
    ├── 获取编译器参数
    │
    ├── [补丁] 清理调试参数
    │   ├── 移除所有 -g* 参数
    │   └── 添加 -g0
    │
    ├── [补丁] 检测 Bazel 环境
    │   └── bazel_execroot() → Option<PathBuf>
    │
    ├── [补丁] 重写路径参数
    │   └── rewrite_bazel_execroot_arg()
    │       ├── 处理 bazel-out/ 裸路径
    │       ├── 处理 -B 标志
    │       └── 处理 -L 标志
    │
    ├── 添加源文件路径
    │
    └── 编译并运行测试
```

## 关键代码路径与文件引用

### 补丁源文件

| 文件 | 路径 | 说明 |
|------|------|------|
| 补丁文件 | `/home/sansha/Github/codex/patches/aws-lc-sys_memcmp_check.patch` | 本研究对象 |
| BUILD.bazel | `/home/sansha/Github/codex/patches/BUILD.bazel` | 使补丁可被 Bazel 引用 |

### 补丁消费者

| 文件 | 代码位置 | 相关代码 |
|------|----------|----------|
| MODULE.bazel | 第 73-82 行 | `crate.annotation` 配置 |

```starlark
crate.annotation(
    build_script_env = {
        "AWS_LC_SYS_NO_JITTER_ENTROPY": "1",
    },
    crate = "aws-lc-sys",
    patch_args = ["-p1"],
    patches = [
        "//patches:aws-lc-sys_memcmp_check.patch",
    ],
)
```

### 被修改的原始代码

| 文件 | Crate | 说明 |
|------|-------|------|
| `builder/cc_builder.rs` | `aws-lc-sys` | AWS Libcrypto 的构建脚本 |

### 相关项目文件

| 文件 | 关系 | 说明 |
|------|------|------|
| `codex-rs/deny.toml` | 依赖声明 | 包含 `aws-lc-sys` 的许可例外 |
| `codex-rs/Cargo.lock` | 依赖锁定 | 记录 `aws-lc-sys` 版本 |

## 依赖与外部交互

### 构建时依赖

```
aws-lc-sys_memcmp_check.patch
    ├── 依赖：Bazel 构建系统
    ├── 依赖：rules_rs (crate.annotation)
    ├── 依赖：aws-lc-sys crate
    └── 依赖：cc crate (Rust C++ 构建工具)
```

### 运行时依赖

该补丁仅在**构建时**生效，运行时无依赖。

### 与 Bazel 的交互

```
┌─────────────────┐
│  MODULE.bazel   │ 定义 patch_args = ["-p1"]
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  rules_rs       │ 下载 aws-lc-sys
│  (crate_ext)    │ 应用补丁：patch -p1 < *.patch
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  aws-lc-sys     │ 执行 build.rs
│  (已打补丁)      │ 调用 CcBuilder::run_memcmp_check()
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Bazel 沙箱     │ 编译并运行 memcmp 检查
└─────────────────┘
```

### 与 Cargo 的交互

虽然通过 Bazel 构建，但 `aws-lc-sys` 本身是 Cargo-based crate：
- 使用 `cc` crate 进行 C/C++ 编译
- 使用 `std::env::var("CARGO_MANIFEST_DIR")` 获取 `manifest_dir`
- 补丁代码与 Cargo 环境变量交互

## 风险、边界与改进建议

### 当前风险

#### 风险 1：上游更新不兼容

| 风险 | 严重程度 | 说明 |
|------|----------|------|
| 行号漂移 | 中 | `aws-lc-sys` 更新可能导致补丁上下文不匹配 |
| 代码重构 | 高 | 如果 `run_memcmp_check` 被重构，补丁可能失效 |
| API 变更 | 低 | `cc` crate API 变更可能影响编译器参数获取 |

**缓解措施**：
- 补丁使用上下文 diff（`@@ -661,6 +661,16 @@`），有一定容错性
- 监控 `aws-lc-sys` 发布，及时测试补丁

#### 风险 2：平台特异性

| 平台 | 影响 | 说明 |
|------|------|------|
| macOS | 高 | `dsymutil` 问题主要针对 macOS |
| Linux | 中 | `-g0` 有益但非必需 |
| Windows | 低 | Bazel 路径格式可能不同 |

#### 风险 3：功能回退

禁用调试信息（`-g0`）意味着：
- 无法调试 `memcmp` 检查程序（但这是构建时临时程序）
- 如果检查失败，调试信息减少

### 边界情况

#### 边界 1：路径处理局限

```rust
// 当前仅处理这些前缀
for flag_prefix in ["-B", "-L"] { ... }

// 未处理的其他可能包含路径的标志：
// - -I (include path)
// - -include (header file)
// - -isystem
// - -iquote
// - -Wl,-rpath,
```

**影响**：如果 Bazel 在这些标志中使用相对路径，链接可能失败。

#### 边界 2：Execroot 检测

```rust
fn bazel_execroot(path: &Path) -> Option<PathBuf> {
    // 仅通过查找 "bazel-out" 组件检测
}
```

**限制**：
- 假设 `bazel-out` 是标准输出目录名称
- 不适用于自定义 `--output_base` 配置
- 不适用于 Bazel 的 `--symlink_prefix` 选项

#### 边界 3：非 UTF-8 路径

```rust
let Some(arg_str) = arg.to_str() else { return true };
// 非 UTF-8 参数被保留，但不会被重写
```

**影响**：在包含非 UTF-8 字符的路径上，Bazel 路径重写不生效。

### 改进建议

#### 短期改进

1. **添加补丁版本注释**：
   ```diff
   +// Patch for aws-lc-sys v0.26.0
   +// Target commit: aws-lc-rs v1.12.0
   +// Issue: Bazel sandbox compatibility
    diff --git a/builder/cc_builder.rs b/builder/cc_builder.rs
   ```

2. **扩展路径处理**：
   ```rust
   // 建议添加更多标志
   for flag_prefix in ["-B", "-L", "-I", "-isystem"] {
       // ...
   }
   ```

3. **增强诊断**：
   ```rust
   if execroot.is_none() {
       eprintln!("[aws-lc-sys] Bazel execroot not detected, path rewriting skipped");
   }
   ```

#### 中期改进

1. **上游化补丁**：
   - 向 `aws-lc-sys` 提交 PR，添加 `AWS_LC_SYS_BAZEL_BUILD` 环境变量支持
   - 使路径重写成为官方功能

2. **配置化**：
   ```rust
   // 通过环境变量控制
   if env::var("AWS_LC_SYS_BAZEL_COMPAT").is_ok() {
       // 应用 Bazel 兼容性修复
   }
   ```

3. **测试覆盖**：
   - 添加 CI 测试：在 Bazel 沙箱中构建 `aws-lc-sys`
   - 验证补丁可应用性测试

#### 长期改进

1. **替代方案探索**：
   - 使用 `crate.annotation` 的 `build_script_env` 传递配置
   - 探索 `rules_rust` 的原生 Bazel 支持

2. **通用解决方案**：
   - 开发通用的 "Bazel 沙箱兼容" 补丁工具
   - 适用于多个有类似问题的 crate

### 测试建议

```bash
# 1. 验证补丁可应用性
cd /tmp
cargo download aws-lc-sys --version 0.26.0
cd aws-lc-sys-0.26.0
git apply /home/sansha/Github/codex/patches/aws-lc-sys_memcmp_check.patch --check

# 2. Bazel 构建测试
bazel build @crates//:aws-lc-sys

# 3. 验证 memcmp 检查通过
# 查看构建日志，确认没有 "memcmp check failed" 错误
```

### 总结

`aws-lc-sys_memcmp_check.patch` 是一个**关键的基础设施补丁**，解决了 AWS 加密库在 Bazel 沙箱中的构建兼容性问题。它通过：

1. **禁用调试信息**：消除对外部工具（`dsymutil`）的依赖
2. **路径规范化**：解决 Bazel execroot 相对路径问题

该补丁体现了项目在**hermetic 构建**方面的工程投入，但也带来了维护负担。建议监控上游更新，并探索向上游化补丁的长期解决方案。
