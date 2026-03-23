# vendored_bwrap.rs 研究文档

## 场景与职责

`vendored_bwrap.rs` 提供了对**内嵌编译的 bubblewrap** 的 FFI 调用封装。这是 Linux 沙箱的**备选执行路径**，当系统未安装 bubblewrap 时作为回退方案。核心场景：

1. **系统 bwrap 不可用**：目标系统缺少 `/usr/bin/bwrap`
2. **静态链接需求**：需要自包含的可执行文件，不依赖外部工具
3. **版本一致性**：确保使用与开发测试一致的 bubblewrap 版本

## 功能点目的

### 1. 条件编译支持

通过 `vendored_bwrap_available` cfg 标志实现双路径编译：
- **可用时**：调用内嵌的 C 语言 `bwrap_main` 函数
- **不可用时**：提供清晰的编译时错误信息

### 2. FFI 安全封装

将 Rust 的 `Vec<String>` 参数转换为 C 语言兼容的 `argc/argv` 格式：
- 处理字符串到 `CString` 的转换（含 null 字节检查）
- 构建 null 结尾的指针数组
- 确保指针生命周期安全

### 3. 文件描述符保留

支持 `preserved_files` 参数，允许在 exec 边界保持文件打开：
- 系统 bwrap 路径需要（跨 exec 边界）
- 内嵌路径当前实现为接受但忽略（注释说明）

## 具体技术实现

### 模块结构

```rust
#[cfg(vendored_bwrap_available)]
mod imp {
    // 实际 FFI 实现
}

#[cfg(not(vendored_bwrap_available))]
mod imp {
    // 占位实现，panic 并提供诊断信息
}

pub(crate) use imp::exec_vendored_bwrap;
```

### FFI 声明

```rust
unsafe extern "C" {
    fn bwrap_main(argc: libc::c_int, argv: *const *const c_char) -> libc::c_int;
}
```

### 参数转换流程

```rust
fn argv_to_cstrings(argv: &[String]) -> Vec<CString> {
    argv.iter()
        .map(|arg| CString::new(arg.as_str()).expect("..."))
        .collect()
}

pub(crate) fn run_vendored_bwrap_main(
    argv: &[String],
    _preserved_files: &[File],
) -> libc::c_int {
    let cstrings = argv_to_cstrings(argv);
    
    // 构建 null 结尾的指针数组
    let mut argv_ptrs: Vec<*const c_char> = 
        cstrings.iter().map(|arg| arg.as_ptr()).collect();
    argv_ptrs.push(std::ptr::null());
    
    // SAFETY: 指针在调用期间有效
    unsafe { bwrap_main(cstrings.len() as libc::c_int, argv_ptrs.as_ptr()) }
}
```

### 不可用时的错误信息

```rust
pub(crate) fn run_vendored_bwrap_main(...) -> libc::c_int {
    panic!(
        r#"build-time bubblewrap is not available in this build.
codex-linux-sandbox should always compile vendored bubblewrap on Linux targets.
Notes:
- ensure the target OS is Linux
- libcap headers must be available via pkg-config
- bubblewrap sources expected at codex-rs/vendor/bubblewrap (default)"#
    );
}
```

## 关键代码路径与文件引用

### 调用链

```
linux_run_main.rs
    ↓
launcher.rs::exec_bwrap()
    ↓ 检测 /usr/bin/bwrap 不存在
vendored_bwrap.rs::exec_vendored_bwrap()
    ↓
[内嵌 C 代码] bwrap_main()
    ↓
执行实际的沙箱操作
```

### 相关文件

| 文件 | 关系 |
|------|------|
| `launcher.rs` | 调用方，负责选择系统 bwrap 或内嵌 bwrap |
| `build.rs` | 定义 `vendored_bwrap_available` cfg 标志，编译 C 代码 |
| `codex-rs/vendor/bubblewrap` | 内嵌 bubblewrap C 源码位置（默认） |

### Cargo.toml 配置

```toml
[build-dependencies]
cc = "1"
pkg-config = "0.3"
```

### 构建脚本逻辑（推断）

```rust
// build.rs（未直接查看，根据代码推断）
fn main() {
    if cfg!(target_os = "linux") {
        // 检查 libcap 可用性
        if pkg_config::probe_library("libcap").is_ok() {
            // 编译 vendor/bubblewrap/*.c
            cc::Build::new()
                .files(glob("vendor/bubblewrap/*.c"))
                .define(...)
                .compile("bwrap");
            
            println!("cargo:rustc-cfg=vendored_bwrap_available");
        }
    }
}
```

## 依赖与外部交互

### 编译时依赖

| 依赖 | 用途 |
|------|------|
| `libcap` | bubblewrap 需要 capabilities 支持 |
| `pkg-config` | 检测 libcap 安装 |
| `cc` | 编译 C 源码 |

### 运行时依赖

- **无额外依赖**：内嵌 bwrap 静态链接
- **系统调用**：依赖 Linux 特定的 namespace、mount 等系统调用

### FFI 边界

| Rust 侧 | C 侧 |
|--------|------|
| `Vec<String>` | `int argc, char **argv` |
| `libc::c_int` | `int` 返回码 |
| `*const c_char` | `char *` |

## 风险、边界与改进建议

### 当前风险

1. **panic 而非错误返回**：
   - 内嵌 bwrap 不可用时直接 panic
   - 无法优雅降级或提供运行时备选

2. **CString 转换失败**：
   - 如果参数包含 null 字节，`CString::new` 会 panic
   - 虽然罕见，但属于潜在 DoS 向量

3. **preserved_files 未实现**：
   - 参数被接受但忽略（`_preserved_files`）
   - 如果内嵌路径需要保留 FD，会出问题

### 边界情况

1. **参数长度限制**：
   - `argc` 转换为 `libc::c_int`，在极端参数数量下可能溢出
   - 实际中不太可能成为问题（shell 有更小限制）

2. **内存安全**：
   - `argv_ptrs` 在栈上分配，大参数列表可能溢出栈
   - 依赖 `bwrap_main` 不修改 argv 内容

3. **信号处理**：
   - `bwrap_main` 可能设置信号处理程序
   - 与 Rust 运行时信号处理可能冲突

### 改进建议

1. **错误处理改进**：
   ```rust
   pub(crate) fn exec_vendored_bwrap(argv: Vec<String>, preserved_files: Vec<File>) 
       -> Result<!, VendoredBwrapError> 
   {
       // 返回 Result 而非直接 panic
   }
   ```

2. **参数验证**：
   ```rust
   fn argv_to_cstrings(argv: &[String]) -> Result<Vec<CString>, NulError> {
       argv.iter()
           .map(|arg| CString::new(arg.as_str()))
           .collect()
   }
   ```

3. **preserved_files 实现**：
   - 如果需要，在内嵌路径中实现 FD 保留
   - 或明确标记为系统路径专用，内嵌路径 panic

4. **文档增强**：
   - 添加关于内嵌 bwrap 版本信息的文档
   - 说明与系统 bwrap 的行为差异（如果有）

5. **安全审计**：
   - 审查内嵌 bubblewrap C 代码的安全性
   - 确保与上游 bubblewrap 安全更新同步

6. **测试覆盖**：
   - 添加内嵌路径的集成测试
   - 测试参数边界情况（空参数、超长参数等）

7. **功能对等**：
   - 确保内嵌 bwrap 支持系统 bwrap 的所有必要功能
   - 定期对比功能差异
