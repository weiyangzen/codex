# MODULE.bazel 研究文档

## 场景与职责

`MODULE.bazel` 是 Bazel 构建系统的模块配置文件，使用 bzlmod（Bazel 的新模块系统）定义项目的依赖、工具链和扩展。该文件位于项目根目录，是现代 Bazel 项目的核心配置文件，替代了旧的 `WORKSPACE` 文件。

Codex 项目使用 Bazel 9.0 的 bzlmod 系统，`MODULE.bazel` 定义了 Rust 工具链、LLVM 工具链、外部依赖和 crate 注解。

## 功能点目的

### 1. 模块声明

```python
module(name = "codex")
```

**目的**：声明模块名称为 "codex"。

**技术背景**：
- bzlmod 使用模块名称来解析依赖
- 模块名称在 Bazel 生态系统中唯一标识项目
- 其他模块可以通过此名称引用 Codex

### 2. 基础依赖

```python
bazel_dep(name = "platforms", version = "1.0.0")
bazel_dep(name = "llvm", version = "0.6.7")

register_toolchains("@llvm//toolchain:all")
```

**目的**：
- `platforms`：Bazel 官方平台约束库
- `llvm`：LLVM 工具链，提供 C/C++ 编译器
- 注册 LLVM 工具链供构建使用

### 3. macOS SDK 框架

```python
osx = use_extension("@llvm//extensions:osx.bzl", "osx")
osx.framework(name = "ApplicationServices")
osx.framework(name = "AppKit")
...
use_repo(osx, "macos_sdk")
```

**目的**：声明 macOS 开发所需的系统框架。

**框架列表**：
- `ApplicationServices`：应用服务
- `AppKit`：macOS UI 框架
- `ColorSync`：颜色管理
- `CoreFoundation`：基础系统服务
- `CoreGraphics`：2D 图形
- `CoreServices`：系统服务
- `CoreText`：文本布局和字体处理
- `AudioToolbox`：音频处理
- `CFNetwork`：网络服务
- `FontServices`：字体服务
- `AudioUnit`：音频单元
- `CoreAudio`：核心音频
- `CoreAudioTypes`：音频类型定义
- `Foundation`：基础框架
- `ImageIO`：图像 I/O
- `IOKit`：硬件访问
- `Kernel`：内核接口
- `OSLog`：日志系统
- `Security`：安全服务
- `SystemConfiguration`：系统配置

**用途**：
- Rust 的 `coreaudio-sys` 等 crate 需要这些框架
- 在 macOS 上构建音频相关功能

### 4. Apple 支持和规则依赖

```python
bazel_dep(name = "apple_support", version = "2.1.0")
bazel_dep(name = "rules_cc", version = "0.2.16")
bazel_dep(name = "rules_platform", version = "0.1.0")
bazel_dep(name = "rules_rs", version = "0.0.43")
```

**目的**：
- `apple_support`：Apple 平台支持（用于禁用 Xcode）
- `rules_cc`：C/C++ 构建规则
- `rules_platform`：平台数据规则
- `rules_rs`：Rust 构建规则（版本 0.0.43）

### 5. Rust 工具链配置

```python
rules_rust = use_extension("@rules_rs//rs/experimental:rules_rust.bzl", "rules_rust")
use_repo(rules_rust, "rules_rust")

toolchains = use_extension("@rules_rs//rs/experimental/toolchains:module_extension.bzl", "toolchains")
toolchains.toolchain(
    edition = "2024",
    version = "1.93.0",
)
use_repo(toolchains, "default_rust_toolchains")

register_toolchains("@default_rust_toolchains//:all")
```

**目的**：配置 Rust 工具链。

**配置详情**：
- **Edition**：2024（最新版）
- **Version**：1.93.0
- 注册默认 Rust 工具链

**与 Cargo.toml 的对应**：
```toml
# codex-rs/Cargo.toml
[workspace.package]
edition = "2024"
```

### 6. Crate 依赖导入

```python
crate = use_extension("@rules_rs//rs:extensions.bzl", "crate")
crate.from_cargo(
    cargo_lock = "//codex-rs:Cargo.lock",
    cargo_toml = "//codex-rs:Cargo.toml",
    platform_triples = [
        "aarch64-unknown-linux-gnu",
        "aarch64-unknown-linux-musl",
        "aarch64-apple-darwin",
        "aarch64-pc-windows-gnullvm",
        "x86_64-unknown-linux-gnu",
        "x86_64-unknown-linux-musl",
        "x86_64-apple-darwin",
        "x86_64-pc-windows-gnullvm",
    ],
    use_experimental_platforms = True,
)
```

**目的**：从 Cargo 配置导入 Rust crate 依赖。

**目标平台**：
- Linux (ARM64/x86_64, glibc/musl)
- macOS (ARM64/x86_64)
- Windows (ARM64/x86_64, gnullvm ABI)

**技术细节**：
- 读取 `codex-rs/Cargo.lock` 解析依赖版本
- 读取 `codex-rs/Cargo.toml` 获取工作区配置
- 生成 Bazel 可用的 crate 定义

### 7. 压缩库依赖

#### zstd
```python
bazel_dep(name = "zstd", version = "1.5.7")

crate.annotation(
    crate = "zstd-sys",
    gen_build_script = "off",
    deps = ["@zstd"],
)
```

#### bzip2
```python
bazel_dep(name = "bzip2", version = "1.0.8.bcr.3")

crate.annotation(
    crate = "bzip2-sys",
    gen_build_script = "off",
    deps = ["@bzip2//:bz2"],
)
```

#### zlib
```python
bazel_dep(name = "zlib", version = "1.3.1.bcr.8")

crate.annotation(
    crate = "libz-sys",
    gen_build_script = "off",
    deps = ["@zlib"],
)
```

**目的**：使用 Bazel 管理的系统库替代 crate 自带的构建脚本。

**优势**：
- 更好的缓存
- 与 Bazel 的依赖跟踪集成
- 避免重复构建

### 8. AWS-LC 配置

```python
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

**目的**：配置 AWS Libcrypto 的构建设置。

**配置**：
- `AWS_LC_SYS_NO_JITTER_ENTROPY=1`：禁用抖动熵（可能用于确定性构建）
- 应用补丁修复 `memcmp` 检查问题

### 9. OpenSSL 配置

```python
bazel_dep(name = "openssl", version = "3.5.4.bcr.0")

crate.annotation(
    build_script_data = ["@openssl//:gen_dir"],
    build_script_env = {
        "OPENSSL_DIR": "$(execpath @openssl//:gen_dir)",
        "OPENSSL_NO_VENDOR": "1",
        "OPENSSL_STATIC": "1",
    },
    crate = "openssl-sys",
    data = ["@openssl//:gen_dir"],
    gen_build_script = "on",
)
```

**目的**：使用 Bazel 管理的 OpenSSL 替代系统 OpenSSL。

**配置**：
- `OPENSSL_NO_VENDOR=1`：不使用 vendored OpenSSL
- `OPENSSL_STATIC=1`：静态链接

### 10. CoreAudio 配置

```python
crate.annotation(
    build_script_data = ["@macos_sdk//sysroot"],
    build_script_env = {
        "BINDGEN_EXTRA_CLANG_ARGS": "...",
        "COREAUDIO_SDK_PATH": "$(location @macos_sdk//sysroot)",
        "LIBCLANG_PATH": "...",
    },
    build_script_tools = [
        "@llvm-project//clang:libclang_interface_output",
        "@llvm//:builtin_resource_dir",
    ],
    crate = "coreaudio-sys",
    gen_build_script = "on",
)
```

**目的**：配置 macOS CoreAudio 的 bindgen 构建。

### 11. 其他注解

#### runfiles
```python
crate.annotation(
    crate = "runfiles",
    workspace_cargo_toml = "rust/runfiles/Cargo.toml",
)
```

#### windows-link
```python
crate.annotation(
    crate = "windows-link",
    patch_args = ["-p1"],
    patches = ["//patches:windows-link.patch"],
)
```

### 12. ALSA 配置

```python
bazel_dep(name = "alsa_lib", version = "1.2.9.bcr.4")

crate.annotation(
    crate = "alsa-sys",
    gen_build_script = "off",
    deps = ["@alsa_lib"],
)
```

**目的**：Linux 音频支持。

### 13. 远程执行平台

```python
bazel_dep(name = "libcap", version = "2.27.bcr.1")

rbe_platform_repository = use_repo_rule("//:rbe.bzl", "rbe_platform_repository")

rbe_platform_repository(
    name = "rbe_platform",
)
```

**目的**：配置远程构建执行（RBE）平台。

## 具体技术实现

### bzlmod 概念

```
Module
├── bazel_dep (依赖其他模块)
├── use_extension (使用扩展)
├── use_repo (使用生成的仓库)
└── register_toolchains (注册工具链)
```

### 锁定文件

`MODULE.bazel.lock`：
- 自动生成的锁定文件
- 记录所有依赖的确切版本
- 确保可重现构建

**更新命令**：
```bash
just bazel-lock-update
# 或
bazel mod deps --lockfile_mode=update
```

### 与 Cargo 的集成

```
MODULE.bazel          Cargo.toml/Cargo.lock
     │                        │
     └── crate.from_cargo() ──┘
              │
              ▼
         @crates 仓库
              │
              ▼
     Bazel 构建图
```

## 关键代码路径与文件引用

### 相关文件

1. **MODULE.bazel.lock**
   - 依赖锁定文件
   - 由 `bazel mod deps` 生成

2. **codex-rs/Cargo.toml**
   - Rust 工作区配置
   - 被 `crate.from_cargo()` 读取

3. **codex-rs/Cargo.lock**
   - Rust 依赖锁定
   - 被 `crate.from_cargo()` 读取

4. **rbe.bzl**
   - 远程执行平台定义
   - 被 `rbe_platform_repository` 使用

5. **patches/** 目录
   - 包含 crate 补丁文件
   - `aws-lc-sys_memcmp_check.patch`
   - `windows-link.patch`

6. **.bazelrc**
   - 引用 MODULE.bazel 定义的仓库
   - 配置远程缓存和执行

### 构建流程

```
1. Bazel 读取 MODULE.bazel
2. 解析 bazel_dep，下载依赖模块
3. 执行 use_extension，生成仓库
4. 注册工具链
5. 从 Cargo 配置生成 @crates
6. 构建目标
```

## 依赖与外部交互

### Bazel Central Registry (BCR)

**依赖来源**：
- `platforms`, `llvm`, `apple_support` 等来自 BCR
- https://registry.bazel.build/

**版本解析**：
- Bazel 自动从 BCR 解析版本
- `MODULE.bazel.lock` 锁定确切版本

### GitHub 依赖

**rules_rs**：
```python
# 来自 GitHub 的 rules_rust 分支
# 版本 0.0.43
```

### 与 Cargo 的关系

| 特性 | Bazel (MODULE.bazel) | Cargo (Cargo.toml) |
|------|---------------------|-------------------|
| 依赖声明 | bazel_dep | [dependencies] |
| 版本锁定 | MODULE.bazel.lock | Cargo.lock |
| 工具链 | register_toolchains | rust-toolchain.toml |
| 构建脚本 | crate.annotation | build.rs |

### 与 CI/CD 的集成

```yaml
# .github/workflows/bazel.yml
- name: Check MODULE.bazel.lock is up to date
  run: ./scripts/check-module-bazel-lock.sh
```

## 风险、边界与改进建议

### 潜在风险

1. **锁定文件漂移**
   - `MODULE.bazel.lock` 可能过期
   - 需要定期更新

2. **依赖版本冲突**
   - 多个模块可能依赖同一库的不同版本
   - bzlmod 使用 MVS (Minimal Version Selection) 解决

3. **平台支持**
   - 某些 crate 注解可能特定于特定平台
   - 跨平台构建可能需要调整

4. **补丁维护**
   - `patches/` 中的补丁需要随上游更新
   - 可能在新版本 crate 中失效

### 边界情况

1. **离线构建**
   - 需要缓存所有外部依赖
   - `--repository_cache` 配置

2. **私有依赖**
   - 如果需要私有 Bazel 模块
   - 需要配置认证

3. **循环依赖**
   - bzlmod 禁止模块间的循环依赖
   - 需要仔细设计模块结构

### 改进建议

1. **添加模块注释**
   ```python
   # Codex monorepo Bazel module configuration
   # See: https://bazel.build/external/module
   
   module(name = "codex")
   
   # === Core Dependencies ===
   bazel_dep(name = "platforms", version = "1.0.0")
   ...
   ```

2. **分组相关配置**
   ```python
   # === Compression Libraries ===
   bazel_dep(name = "zstd", version = "1.5.7")
   bazel_dep(name = "bzip2", version = "1.0.8.bcr.3")
   bazel_dep(name = "zlib", version = "1.3.1.bcr.8")
   ```

3. **定期更新依赖**
   - 每季度检查 BCR 更新
   - 更新 `rules_rs` 到最新版本
   - 更新 LLVM 工具链

4. **优化 crate 注解**
   - 考虑使用循环或函数减少重复
   - 添加注释说明每个注解的目的

5. **添加验证脚本**
   ```bash
   # 验证 MODULE.bazel 配置
   bazel mod deps --lockfile_mode=error
   ```

### 使用示例

```bash
# 查看模块依赖图
bazel mod graph

# 查看外部依赖
bazel mod list_repo

# 更新锁定文件
bazel mod deps --lockfile_mode=update

# 验证锁定文件
./scripts/check-module-bazel-lock.sh

# 查看 crate 定义
bazel query '@crates//:all' | head
```

### 配置对比

| 配置项 | MODULE.bazel | WORKSPACE (旧) |
|--------|--------------|----------------|
| 语法 | bzlmod | Starlark |
| 依赖管理 | 声明式 | 命令式 |
| 版本解析 | MVS | 最新版本 |
| 锁定文件 | MODULE.bazel.lock | 无原生支持 |
| 可维护性 | 高 | 低 |

**bzlmod 的优势**：
- 声明式配置
- 自动版本解析
- 原生锁定支持
- 更好的可重现性
