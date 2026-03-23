# build.rs 研究文档

## 场景与职责

`build.rs` 是 Rust 的构建脚本（Build Script），在 crate 编译之前执行，用于执行自定义构建任务。对于 `codex-windows-sandbox` crate，该构建脚本负责将 Windows 应用程序清单（manifest）嵌入到 `codex-windows-sandbox-setup.exe` 可执行文件中。

## 功能点目的

### 核心功能：嵌入 Windows 清单文件
Windows 可执行文件可以包含一个 XML 格式的应用程序清单，用于声明：
- **执行权限级别**（Execution Level）：如 `asInvoker`, `requireAdministrator`, `highestAvailable`
- **UI 访问权限**（UI Access）：是否允许辅助技术访问 UI
- **兼容性设置**（Compatibility）：Windows 版本兼容性声明
- **DPI 感知**（DPI Awareness）：高 DPI 显示支持

对于 `codex-windows-sandbox-setup.exe`，清单文件至关重要，因为它：
1. 控制 UAC（用户账户控制）提权行为
2. 确保在需要时能够请求管理员权限

## 具体技术实现

### 代码实现
```rust
fn main() {
    let mut res = winres::WindowsResource::new();
    res.set_manifest_file("codex-windows-sandbox-setup.manifest");
    let _ = res.compile();
}
```

### 技术细节

| 步骤 | 操作 | 说明 |
|------|------|------|
| 1 | `WindowsResource::new()` | 创建 Windows 资源编译器实例 |
| 2 | `set_manifest_file()` | 指定要嵌入的清单文件路径 |
| 3 | `compile()` | 编译资源并链接到输出二进制文件 |

### 清单文件内容
引用的清单文件 (`codex-windows-sandbox-setup.manifest`) 内容：
```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v2">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="asInvoker" uiAccess="false"/>
      </requestedPrivileges>
    </security>
  </trustInfo>
</assembly>
```

**关键配置解析**：
- `level="asInvoker"`: 以调用者相同的权限级别运行（不强制要求管理员权限）
- `uiAccess="false"`: 不允许 UI 访问（不需要辅助技术权限）

> **注意**: 虽然清单指定 `asInvoker`，但 `codex-windows-sandbox-setup` 实际上需要管理员权限来执行沙箱设置。权限提升通过代码中的 `ShellExecuteExW` 显式请求（`"runas"` verb），而非依赖清单强制。

## 关键代码路径与文件引用

### 输入文件
- `codex-windows-sandbox-setup.manifest` - Windows 应用程序清单文件

### 输出
- 编译后的资源对象文件（`.o` 或 `.res`）
- 链接到最终的可执行文件 `codex-windows-sandbox-setup.exe`

### 构建流程
```
build.rs 执行
    │
    ├── 读取 codex-windows-sandbox-setup.manifest
    │
    ├── winres 编译清单为资源文件
    │       └── 调用 Windows SDK 的 rc.exe 或 llvm-rc
    │
    └── 链接到 codex-windows-sandbox-setup.exe
```

## 依赖与外部交互

### 构建依赖
```toml
[build-dependencies]
winres = "0.1"
```

### winres crate 工作原理
1. **检测工具链**: 自动检测可用的 Windows 资源编译器
   - 优先使用 `llvm-rc`（LLVM 工具链）
   - 回退到 Windows SDK 的 `rc.exe`

2. **生成资源脚本**: 根据配置生成 `.rc` 文件
   ```rc
   #include <windows.h>
   1 RT_MANIFEST "codex-windows-sandbox-setup.manifest"
   ```

3. **编译资源**: 调用资源编译器生成 `.res` 或 `.o` 文件

4. **指示链接**: 通过 `cargo:rustc-link-lib` 输出告诉 Cargo 链接资源

### 环境要求
- **Windows**: 需要 Windows 平台才能实际编译资源
- **Windows SDK 或 LLVM**: 需要资源编译器工具
- **非 Windows 平台**: `winres` 会静默失败（`let _ = res.compile()` 忽略错误）

## 风险、边界与改进建议

### 风险点

1. **错误处理不足**:
   ```rust
   let _ = res.compile();  // 错误被忽略
   ```
   - 如果清单文件不存在或编译失败，构建会继续，但生成的可执行文件可能没有清单
   - **建议**: 显式处理错误
     ```rust
     res.compile().expect("Failed to compile Windows manifest");
     ```

2. **平台检测缺失**:
   - 在非 Windows 平台上，构建脚本仍然会执行，但 `winres` 会失败
   - 虽然错误被忽略，但这可能掩盖配置问题

3. **清单文件路径硬编码**:
   - 使用相对路径 `"codex-windows-sandbox-setup.manifest"`
   - 如果工作目录改变，可能找不到文件

### 边界条件

| 场景 | 行为 |
|------|------|
| Windows + SDK 可用 | 清单正常嵌入 |
| Windows + SDK 不可用 | 静默失败（`let _ =`） |
| 非 Windows 平台 | `winres` 内部处理，通常静默失败 |
| 清单文件缺失 | `compile()` 返回错误，被忽略 |

### 改进建议

1. **增强错误处理**:
   ```rust
   use std::io;
   
   fn main() -> io::Result<()> {
       // 只在 Windows 上编译资源
       #[cfg(target_os = "windows")]
       {
           let manifest_path = concat!(env!("CARGO_MANIFEST_DIR"), "/codex-windows-sandbox-setup.manifest");
           let mut res = winres::WindowsResource::new();
           res.set_manifest_file(manifest_path);
           res.compile()?;
       }
       Ok(())
   }
   ```

2. **添加平台条件编译**:
   ```rust
   fn main() {
       #[cfg(target_os = "windows")]
       compile_windows_resources();
   }
   
   #[cfg(target_os = "windows")]
   fn compile_windows_resources() {
       // ... 实现
   }
   ```

3. **验证清单存在**:
   ```rust
   use std::path::Path;
   
   fn main() {
       let manifest = "codex-windows-sandbox-setup.manifest";
       assert!(Path::new(manifest).exists(), "Manifest file not found: {}", manifest);
       // ... 编译
   }
   ```

4. **构建脚本输出**:
   ```rust
   println!("cargo:rerun-if-changed=codex-windows-sandbox-setup.manifest");
   ```
   - 告诉 Cargo 当清单文件改变时重新运行构建脚本

5. **考虑使用 embed-resource crate**:
   - `embed-resource` 是另一个流行的 Windows 资源嵌入 crate
   - 可能提供更好的跨平台支持和错误处理

### 与 Cargo.toml 的关联

`Cargo.toml` 中的相关配置：
```toml
[package]
build = "build.rs"

[build-dependencies]
winres = "0.1"
```

`BUILD.bazel` 中的相关配置：
```bazel
codex_rust_crate(
    name = "windows-sandbox-rs",
    build_script_data = [
        "Cargo.toml",
        "codex-windows-sandbox-setup.manifest",  # 关键：声明构建脚本依赖
    ],
    # ...
)
```

在 Bazel 构建中，`build_script_data` 确保清单文件对构建脚本可见。
