# BUILD.bazel 研究文档

## 场景与职责

`BUILD.bazel` 是 Bazel 构建系统的核心构建文件，位于项目根目录，定义了工作区级别的构建目标、平台配置和工具链设置。该文件与 `MODULE.bazel` 配合使用，前者定义目标，后者定义依赖和模块。

Codex 项目使用 Bazel 作为主要的构建系统之一（与 Cargo 并行），`BUILD.bazel` 配置了跨平台支持、远程执行平台别名和文件导出。

## 功能点目的

### 1. Xcode 配置禁用

```python
load("@apple_support//xcode:xcode_config.bzl", "xcode_config")

xcode_config(name = "disable_xcode")
```

**目的**：创建一个空的 Xcode 配置，避免在 macOS 上依赖 Xcode 工具链。

**技术背景**：
- Bazel 在 macOS 上默认尝试检测和使用 Xcode
- 这需要安装 Xcode 和命令行工具
- 通过创建空的 `xcode_config`，可以绕过这一要求

**使用方式**：
```
# .bazelrc
common --xcode_version_config=//:disable_xcode
```

### 2. 本地 Linux 平台配置

```python
platform(
    name = "local_linux",
    constraint_values = [
        "@llvm//constraints/libc:gnu.2.28",
    ],
    parents = ["@platforms//host"],
)
```

**目的**：定义本地 Linux 构建平台，标记为 glibc 2.28 兼容。

**技术细节**：
- `constraint_values`：平台约束，指定 glibc 版本
- `parents`：继承主机平台的基本属性
- `@llvm//constraints/libc:gnu.2.28`：LLVM 工具链的 libc 约束

**背景**：
- musl 构建的 Rust 无法动态加载 proc macros
- 标记为 glibc 兼容确保使用正确的工具链
- 仅在 Linux 上启用，避免影响远程执行

### 3. 本地 Windows 平台配置

```python
platform(
    name = "local_windows",
    constraint_values = [
        "@rules_rs//rs/experimental/platforms/constraints:windows_gnullvm",
    ],
    parents = ["@platforms//host"],
)
```

**目的**：定义本地 Windows 构建平台。

**技术细节**：
- 使用 `windows_gnullvm` ABI
- 这是 LLVM/Clang 工具链的 Windows 目标

### 4. 远程执行平台别名

```python
alias(
    name = "rbe",
    actual = "@rbe_platform",
)
```

**目的**：创建远程执行平台的别名。

**技术细节**：
- `rbe` = Remote Build Execution
- 指向 `@rbe_platform`，由 `rbe.bzl` 定义
- 在 `.bazelrc` 中使用：`--extra_execution_platforms=//:rbe`

### 5. 文件导出

```python
exports_files([
    "AGENTS.md",
    "workspace_root_test_launcher.bat.tpl",
    "workspace_root_test_launcher.sh.tpl",
])
```

**目的**：导出文件供其他 Bazel 包引用。

**导出的文件**：
- `AGENTS.md`：开发指南文档
- `workspace_root_test_launcher.bat.tpl`：Windows 测试启动器模板
- `workspace_root_test_launcher.sh.tpl`：Unix 测试启动器模板

**用途**：
- 测试启动器模板用于 `defs.bzl` 中的 `workspace_root_test` 规则
- `AGENTS.md` 可能被文档生成工具引用

## 具体技术实现

### Bazel 构建规则

**platform 规则**：
```python
platform(
    name = "<name>",
    constraint_values = [<约束列表>],
    parents = [<父平台>],
)
```

**alias 规则**：
```python
alias(
    name = "<别名>",
    actual = "<实际目标>",
)
```

**exports_files 规则**：
```python
exports_files(["<文件1>", "<文件2>"])
```

### 平台约束系统

Bazel 的平台机制：
```
Platform
├── constraint_values (约束值)
│   ├── @platforms//cpu:*
│   ├── @platforms//os:*
│   └── @llvm//constraints/libc:*
└── parents (继承)
    └── @platforms//host
```

### 与 .bazelrc 的协作

```
.bazelrc                    BUILD.bazel
    │                            │
    ├── --host_platform=//:local_linux ──┤
    │                            │
    ├── --host_platform=//:local_windows ┤
    │                            │
    └── --extra_execution_platforms=//:rbe ────┘
```

## 关键代码路径与文件引用

### 相关文件

1. **MODULE.bazel**
   - 定义外部依赖（`bazel_dep`）
   - 注册工具链
   - 定义 `rules_rust` 和 `llvm` 扩展

2. **rbe.bzl**
   - 定义 `rbe_platform_repository` 规则
   - 配置远程执行容器镜像
   - 生成 `@rbe_platform` 仓库

3. **defs.bzl**
   - 定义 `codex_rust_crate` 宏
   - 定义 `workspace_root_test` 规则
   - 使用导出的启动器模板

4. **.bazelrc**
   - 引用 `//:local_linux`, `//:local_windows`, `//:rbe`
   - 引用 `//:disable_xcode`

5. **workspace_root_test_launcher.sh.tpl**
   - Bash 测试启动器模板
   - 用于在正确的目录运行测试

6. **workspace_root_test_launcher.bat.tpl**
   - Windows 批处理测试启动器模板

### 构建流程

```
1. Bazel 读取 MODULE.bazel，加载外部依赖
2. Bazel 读取 BUILD.bazel，定义本地平台
3. .bazelrc 指定使用哪个平台
4. 构建时根据目标平台选择工具链
5. 远程执行时使用 rbe 平台
```

## 依赖与外部交互

### 外部依赖

1. **@apple_support**
   - 提供 `xcode_config` 规则
   - 用于禁用 Xcode 依赖

2. **@platforms**
   - Bazel 官方平台约束库
   - 提供 `//host`, `//cpu:*`, `//os:*`

3. **@llvm**
   - LLVM 工具链
   - 提供 `//constraints/libc:gnu.2.28`

4. **@rules_rs**
   - Rust 规则集
   - 提供 `//rs/experimental/platforms/constraints:windows_gnullvm`

5. **@rbe_platform**
   - 由 `rbe.bzl` 生成
   - 远程执行平台定义

### 工具链注册

```python
# MODULE.bazel
register_toolchains("@llvm//toolchain:all")
register_toolchains("@default_rust_toolchains//:all")
```

工具链选择：
- 根据 `platform` 的 `constraint_values`
- Bazel 选择匹配的工具链

### 与 Cargo 的关系

| 特性 | Bazel | Cargo |
|------|-------|-------|
| 构建文件 | BUILD.bazel | Cargo.toml |
| 平台定义 | `platform` 规则 | 目标三元组 |
| 工具链 | 外部仓库 | rustup |
| 远程执行 | 原生支持 | 不支持 |

## 风险、边界与改进建议

### 潜在风险

1. **平台配置复杂性**
   - 多平台支持增加了配置复杂度
   - 需要维护 Linux、macOS、Windows 的配置

2. **远程执行依赖**
   - `@rbe_platform` 依赖外部容器镜像
   - 镜像更新可能需要同步更新 `rbe.bzl`

3. **Xcode 禁用副作用**
   - 某些 macOS 特定功能可能无法使用
   - 需要确保 LLVM 工具链覆盖所有需求

4. **glibc 版本约束**
   - `gnu.2.28` 是特定版本
   - 在更新的系统上可能需要更新

### 边界情况

1. **交叉编译**
   - 当前配置主要针对本地构建
   - 交叉编译可能需要额外配置

2. **ARM64 支持**
   - `rbe.bzl` 支持 x86_64 和 aarch64
   - 但某些平台配置可能需要调整

3. **Windows 支持**
   - Windows 配置相对简单
   - 可能需要更多测试和优化

### 改进建议

1. **添加注释说明**
   ```python
   # Disable Xcode dependency on macOS
   # Uses LLVM toolchain instead
   xcode_config(name = "disable_xcode")
   
   # Linux platform with glibc 2.28 compatibility
   # Required for proc macro loading with musl-built Rust
   platform(
       name = "local_linux",
       ...
   )
   ```

2. **添加更多平台配置**
   ```python
   # macOS 平台（如果需要区分 Intel 和 Apple Silicon）
   platform(
       name = "local_macos_arm64",
       constraint_values = [
           "@platforms//cpu:aarch64",
           "@platforms//os:macos",
       ],
       parents = ["@platforms//host"],
   )
   ```

3. **导出更多常用文件**
   ```python
   exports_files([
       "AGENTS.md",
       "README.md",
       "LICENSE",
       "workspace_root_test_launcher.bat.tpl",
       "workspace_root_test_launcher.sh.tpl",
   ])
   ```

4. **添加平台文档**
   ```python
   # 添加文件组用于文档生成
   filegroup(
       name = "docs",
       srcs = glob(["docs/**/*.md"]),
   )
   ```

5. **定期审查工具链版本**
   - glibc 2.28 是 2018 年发布的
   - 考虑是否需要更新到更新的版本
   - 评估 LLVM 和 Rust 工具链更新

### 使用示例

```bash
# 查看可用的平台目标
bazel query '//:all' | grep -E '(local_|rbe)'

# 查看平台详细信息
bazel query --output=build '//:local_linux'

# 使用特定平台构建
bazel build --platforms=//:local_linux //codex-rs/cli:codex

# 查看导出的文件
bazel query 'exports(//:AGENTS.md)'

# 构建所有目标
bazel build //...
```

### 配置对比

| 配置项 | BUILD.bazel | MODULE.bazel |
|--------|-------------|--------------|
| 用途 | 定义构建目标 | 定义模块依赖 |
| 内容 | platform, alias, exports_files | bazel_dep, use_extension |
| 执行 | 构建时 | 加载时 |
| 频率 | 每次构建 | 模块变更时 |

**协作关系**：
- `MODULE.bazel` 定义外部依赖和工具链
- `BUILD.bazel` 使用这些依赖定义本地目标
- `.bazelrc` 配置如何使用这些目标
