# patches/BUILD.bazel 研究文档

## 场景与职责

`patches/BUILD.bazel` 是一个**空的 Bazel 构建文件**，其唯一职责是将 `patches/` 目录标记为有效的 Bazel package（包）。这是 Bazel 构建系统的基本要求，使得该目录下的补丁文件可以通过 Bazel 标签（label）被其他构建规则引用。

### 在构建系统中的位置

```
项目根目录
├── MODULE.bazel          # Bazel 模块定义，包含 crate.annotation 配置
├── patches/              # 补丁存储目录
│   ├── BUILD.bazel       # 本文件：标记为 Bazel package
│   ├── aws-lc-sys_memcmp_check.patch
│   └── windows-link.patch
└── ...
```

### 为什么需要这个文件

在 Bazel 中，任何需要通过 `//path:target` 语法引用的文件都必须位于一个 package 内。一个目录成为 package 的条件是包含一个名为 `BUILD` 或 `BUILD.bazel` 的文件。`MODULE.bazel` 中引用补丁的方式如下：

```starlark
crate.annotation(
    crate = "aws-lc-sys",
    patch_args = ["-p1"],
    patches = [
        "//patches:aws-lc-sys_memcmp_check.patch",  # 需要 patches 是 package
    ],
)
```

如果没有 `BUILD.bazel` 文件，`//patches:aws-lc-sys_memcmp_check.patch` 这个标签将无法解析，导致构建失败。

## 功能点目的

### 核心功能

| 功能 | 说明 |
|------|------|
| **Package 标记** | 使 `patches/` 成为有效的 Bazel package |
| **文件导出** | 允许目录下的补丁文件被其他 Bazel 目标引用 |
| **命名空间隔离** | 为补丁文件提供独立的 Bazel 命名空间 |

### 为什么是空文件

这个文件**故意保持为空**，原因如下：

1. **无需额外规则**：补丁文件作为静态资源，不需要编译或特殊处理，Bazel 的默认文件处理机制已足够
2. **简化维护**：空文件不会引入额外的构建逻辑或依赖
3. **约定优于配置**：遵循 Bazel 社区惯例，纯资源目录使用空 BUILD 文件

## 具体技术实现

### Bazel Package 机制

Bazel 的 package 系统遵循以下层级结构：

```
Workspace (由 MODULE.bazel 定义)
    └── Package (由 BUILD.bazel 定义)
            └── Targets (文件、规则等)
```

### 文件引用路径解析

当 `MODULE.bazel` 中使用 `"//patches:aws-lc-sys_memcmp_check.patch"` 时：

1. **Workspace 根目录**：包含 `MODULE.bazel` 的目录
2. **Package 路径**：`patches/`（相对于 workspace 根目录）
3. **目标名称**：`aws-lc-sys_memcmp_check.patch`

Bazel 会查找 `patches/BUILD.bazel` 确认这是一个有效的 package，然后定位到具体的补丁文件。

### 与 rules_rs 的集成

```starlark
# MODULE.bazel (简化示意)
crate = use_extension("@rules_rs//rs:extensions.bzl", "crate")

crate.annotation(
    crate = "aws-lc-sys",
    patches = ["//patches:aws-lc-sys_memcmp_check.patch"],
)
```

`rules_rs` 在构建 `aws-lc-sys` crate 时，会：
1. 下载 crate 源码
2. 在构建前应用指定的补丁
3. 使用 `patch -p1 < patches/aws-lc-sys_memcmp_check.patch` 命令

## 关键代码路径与文件引用

### 直接引用

| 引用位置 | 代码片段 | 用途 |
|----------|----------|------|
| `MODULE.bazel:80` | `"//patches:aws-lc-sys_memcmp_check.patch"` | aws-lc-sys 补丁引用 |
| `MODULE.bazel:163` | `"//patches:windows-link.patch"` | windows-link 补丁引用 |

### 相关文件

| 文件路径 | 关系 | 说明 |
|----------|------|------|
| `patches/aws-lc-sys_memcmp_check.patch` | 同目录资源 | 被引用的补丁文件 |
| `patches/windows-link.patch` | 同目录资源 | 被引用的补丁文件 |
| `MODULE.bazel` | 消费者 | 定义补丁应用配置 |

### 构建流程中的位置

```
构建流程：
┌─────────────────┐
│  MODULE.bazel   │ 定义 crate.annotation
└────────┬────────┘
         │ 引用 //patches:*.patch
         ▼
┌─────────────────┐
│ patches/BUILD.bazel │ 验证 package 有效性
└────────┬────────┘
         │ 导出补丁文件
         ▼
┌─────────────────┐
│ patches/*.patch │ 实际补丁内容
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   rules_rs      │ 应用补丁到 crate
└─────────────────┘
```

## 依赖与外部交互

### 无外部依赖

`BUILD.bazel` 本身是一个**零依赖**的文件：

- 不依赖其他 Bazel 规则
- 不依赖外部工具
- 不依赖特定平台

### 被依赖关系

```
patches/BUILD.bazel
    └── 被引用者：
        ├── MODULE.bazel (通过 //patches: 标签)
        └── Bazel 构建系统 (package 验证)
```

### 隐式交互

虽然文件为空，但 Bazel 会隐式处理：

1. **Glob 扫描**：Bazel 会扫描目录下的所有文件作为潜在目标
2. **可见性控制**：默认情况下，package 内的目标对 workspace 可见
3. **缓存失效**：如果此文件被修改，会触发依赖它的构建目标重新分析

## 风险、边界与改进建议

### 当前风险

| 风险 | 严重程度 | 说明 |
|------|----------|------|
| **误删除风险** | 低 | 空文件容易被误认为无用而删除，导致构建失败 |
| **命名冲突** | 极低 | 如果添加与补丁文件同名的 Bazel 规则，会产生冲突 |

### 边界情况

1. **文件权限**：需要确保文件有读权限，否则 Bazel 无法解析
2. **文件名大小写**：在大小写不敏感的文件系统（如 macOS）上，`build.bazel` 和 `BUILD.bazel` 被视为相同

### 改进建议

#### 短期（可选）

1. **添加文件头注释**（虽然 Bazel 支持，但非必需）：
   ```starlark
   # patches/BUILD.bazel
   # 此文件标记 patches/ 为 Bazel package，使补丁文件可被引用
   # 参见 MODULE.bazel 中的 crate.annotation 配置
   ```

2. **显式导出文件**（如果需要更严格的控制）：
   ```starlark
   exports_files([
       "aws-lc-sys_memcmp_check.patch",
       "windows-link.patch",
   ])
   ```

#### 中期

1. **添加 package 级文档**：
   ```starlark
   package(
       default_visibility = ["//visibility:public"],
       licenses = ["notice"],  # 与项目 LICENSE 一致
   )
   ```

2. **考虑文件组织**：如果补丁数量增长，可以按 crate 组织子目录：
   ```
   patches/
   ├── BUILD.bazel
   ├── aws-lc-sys/
   │   ├── BUILD.bazel
   │   └── memcmp_check.patch
   └── windows-link/
       ├── BUILD.bazel
       └── readme_fix.patch
   ```

#### 长期

1. **补丁管理工具**：如果补丁数量显著增加，考虑：
   - 使用 Bazel 的 `http_file` 规则从外部获取补丁
   - 建立补丁版本管理机制
   - 添加补丁应用验证测试

### 测试建议

验证此文件正确性的简单方法：

```bash
# 1. 验证 Bazel 能识别 patches 为 package
bazel query //patches:all

# 2. 验证补丁文件可被引用
bazel build //patches:aws-lc-sys_memcmp_check.patch
bazel build //patches:windows-link.patch

# 3. 验证 crate 构建（间接测试）
bazel build @crates//:aws-lc-sys
```

### 总结

`patches/BUILD.bazel` 是一个**基础设施文件**，虽然内容为空，但在 Bazel 构建系统中扮演关键角色。它使 `patches/` 目录成为有效的 package，从而让 `MODULE.bazel` 中的 `crate.annotation` 能够引用补丁文件。保持此文件存在且为空是最简单、最符合 Bazel 惯例的做法。
