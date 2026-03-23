# workspace_root_test_launcher.bat.tpl 研究文档

## 场景与职责

`workspace_root_test_launcher.bat.tpl` 是 Bazel 测试启动器的 **Windows 批处理模板文件**，用于解决在 Bazel 沙箱环境中运行 Rust 测试时的**工作目录定位问题**。该模板与 `defs.bzl` 中的 `workspace_root_test` 规则配合使用。

在 Codex 项目中，此文件服务于以下场景：
- **Insta 快照测试支持**：Insta 快照测试库需要知道仓库根目录以正确定位和管理快照文件
- **Bazel 沙箱兼容性**：Bazel 测试在隔离的 runfiles 目录中执行，需要解析回真实的工作区根目录
- **跨平台测试一致性**：为 Windows 平台提供与 Unix (`workspace_root_test_launcher.sh.tpl`) 等价的功能
- **Cargo/Bazel 双构建系统支持**：统一两种构建系统下的测试行为

## 功能点目的

### 1. Runfile 解析

```batch
:resolve_runfile
setlocal EnableExtensions EnableDelayedExpansion
set "logical_path=%~2"
set "workspace_logical_path=%logical_path%"
if defined TEST_WORKSPACE set "workspace_logical_path=%TEST_WORKSPACE%/%logical_path%"
set "native_logical_path=%logical_path:/=\%"
```

**目的**：
- 将逻辑路径（如 `__WORKSPACE_ROOT_MARKER__`）解析为实际文件系统路径
- 处理 Bazel 的 `TEST_WORKSPACE` 环境变量前缀
- 转换 Unix 路径分隔符为 Windows 反斜杠

### 2. 多源路径查找

```batch
for %%R in ("%RUNFILES_DIR%" "%TEST_SRCDIR%") do (
  set "runfiles_root=%%~R"
  if defined runfiles_root (
    if exist "!runfiles_root!\!native_logical_path!" (
      endlocal & set "%~1=!runfiles_root!\!native_logical_path!" & exit /b 0
    )
    if exist "!runfiles_root!\!native_workspace_logical_path!" (
      endlocal & set "%~1=!runfiles_root!\!native_workspace_logical_path!" & exit /b 0
    )
  )
)
```

**目的**：
- 按优先级检查 `RUNFILES_DIR` 和 `TEST_SRCDIR` 环境变量
- 支持两种路径格式：裸逻辑路径和带 workspace 前缀的路径
- 使用 `EnableDelayedExpansion` 处理循环中的变量扩展

### 3. Manifest 文件回退

```batch
set "manifest=%RUNFILES_MANIFEST_FILE%"
if not defined manifest if exist "%~f0.runfiles_manifest" set "manifest=%~f0.runfiles_manifest"
if not defined manifest if exist "%~dpn0.runfiles_manifest" set "manifest=%~dpn0.runfiles_manifest"
if not defined manifest if exist "%~f0.exe.runfiles_manifest" set "manifest=%~f0.exe.runfiles_manifest"

if defined manifest if exist "%manifest%" (
  for /f "usebackq tokens=1,* delims= " %%A in (`findstr /b /c:"%logical_path% " "%manifest%"`) do (
    endlocal & set "%~1=%%B" & exit /b 0
  )
)
```

**目的**：
- 当 runfiles 目录不可用时，回退到 manifest 文件解析
- 支持多种 manifest 文件命名约定
- 使用 `findstr` 在 manifest 中查找路径映射

### 4. 工作区根目录计算

```batch
call :resolve_runfile workspace_root_marker "__WORKSPACE_ROOT_MARKER__"
if errorlevel 1 exit /b 1

for %%I in ("%workspace_root_marker%") do set "workspace_root_marker_dir=%%~dpI"
for %%I in ("%workspace_root_marker_dir%..\..") do set "workspace_root=%%~fI"
```

**目的**：
- 解析 `repo_root.marker` 文件位置（占位符 `__WORKSPACE_ROOT_MARKER__` 由 Bazel 替换）
- 通过两次 `..\..` 导航计算仓库根目录（marker 位于 `codex-rs/utils/cargo-bin/`）
- 使用 `%~fI` 获取完整绝对路径

### 5. 测试执行环境设置

```batch
set "INSTA_WORKSPACE_ROOT=%workspace_root%"
cd /d "%workspace_root%" || exit /b 1
"%test_bin%" %*
exit /b %ERRORLEVEL%
```

**目的**：
- 设置 `INSTA_WORKSPACE_ROOT` 环境变量，供 Insta 快照测试库使用
- 切换当前目录到仓库根目录
- 执行实际测试二进制文件并传递所有参数
- 保留测试进程的退出码

## 具体技术实现

### 模板替换变量

| 占位符 | 替换来源 | 说明 |
|--------|----------|------|
| `__WORKSPACE_ROOT_MARKER__` | `defs.bzl` 中的 `workspace_root_marker.short_path` | `repo_root.marker` 文件的 runfile 路径 |
| `__TEST_BIN__` | `defs.bzl` 中的 `test_bin.short_path` | 实际测试二进制文件的 runfile 路径 |

### 关键批处理技术

| 技术 | 用途 |
|------|------|
| `setlocal EnableExtensions EnableDelayedExpansion` | 启用高级批处理功能和延迟变量扩展 |
| `%~f0`, `%~dpn0` | 提取脚本的完整路径、目录、基本名 |
| `for %%I in ("path") do set "var=%%~dpI"` | 提取路径的目录部分 |
| `for /f "usebackq tokens=1,* delims= "` | 解析 manifest 文件的键值对 |
| `findstr /b /c:"pattern"` | 在文件中查找以特定字符串开头的行 |
| `exit /b %ERRORLEVEL%` | 传递子进程退出码 |

### 路径解析优先级

```
1. RUNFILES_DIR/<logical_path>
2. RUNFILES_DIR/<workspace_logical_path>
3. TEST_SRCDIR/<logical_path>
4. TEST_SRCDIR/<workspace_logical_path>
5. RUNFILES_MANIFEST_FILE 查找
6. <script>.runfiles_manifest 查找
7. <script>.exe.runfiles_manifest 查找
```

### 目录结构关系

```
<workspace_root>/                    # 计算得到的仓库根目录
├── codex-rs/
│   └── utils/
│       └── cargo-bin/
│           └── repo_root.marker     # __WORKSPACE_ROOT_MARKER__ 指向此处
├── bazel-out/...
│   └── .../test.exe                 # 测试启动器脚本
│   └── .../test.exe.runfiles/       # RUNFILES_DIR
│       ├── __WORKSPACE_ROOT_MARKER__ -> .../repo_root.marker
│       └── __TEST_BIN__ -> .../unit-tests-bin
└── ...
```

## 关键代码路径与文件引用

### 调用方（生成者）

| 文件 | 代码 | 说明 |
|------|------|------|
| `/home/sansha/Github/codex/defs.bzl` | `ctx.actions.expand_template(...)` | 使用此模板生成测试启动器 |
| `/home/sansha/Github/codex/defs.bzl` | `_workspace_root_test_impl` | 实现规则，填充模板变量 |
| `/home/sansha/Github/codex/BUILD.bazel` | `exports_files([...])` | 导出模板文件供规则使用 |

### 配套文件

| 文件 | 关系 | 说明 |
|------|------|------|
| `/home/sansha/Github/codex/workspace_root_test_launcher.sh.tpl` | Unix 对应版本 | 功能等价的 Bash 脚本模板 |
| `/home/sansha/Github/codex/defs.bzl` | 规则定义 | 定义 `workspace_root_test` 规则 |
| `/home/sansha/Github/codex/codex-rs/utils/cargo-bin/repo_root.marker` | 标记文件 | 用于定位仓库根的空标记文件 |
| `/home/sansha/Github/codex/codex-rs/utils/cargo-bin/src/lib.rs` | 库实现 | 提供 `repo_root()` 函数，逻辑与此模板一致 |

### 使用方（测试目标）

所有使用 `codex_rust_crate` 宏的 crate 都会间接使用此模板：

```
codex-rs/tui/BUILD.bazel → codex_rust_crate → workspace_root_test → 此模板
codex-rs/core/BUILD.bazel → codex_rust_crate → workspace_root_test → 此模板
codex-rs/cli/BUILD.bazel → codex_rust_crate → workspace_root_test → 此模板
... (所有 77 个 BUILD.bazel 文件)
```

## 依赖与外部交互

### Bazel 环境变量依赖

| 环境变量 | 来源 | 用途 |
|----------|------|------|
| `RUNFILES_DIR` | Bazel 测试运行器 | Runfiles 树的根目录 |
| `TEST_SRCDIR` | Bazel 测试运行器 | 测试源文件目录（通常与 RUNFILES_DIR 相同） |
| `TEST_WORKSPACE` | Bazel 测试运行器 | 当前测试的工作区名称 |
| `RUNFILES_MANIFEST_FILE` | Bazel 测试运行器 | Runfiles 清单文件路径 |

### 外部工具依赖

| 工具 | 用途 |
|------|------|
| `findstr` | Windows 内置，用于在 manifest 文件中搜索 |
| `cmd.exe` | Windows 命令解释器 |

### 与 Insta 的交互

```batch
set "INSTA_WORKSPACE_ROOT=%workspace_root%"
```

- **库**: [Insta](https://insta.rs/) - Rust 快照测试库
- **环境变量**: `INSTA_WORKSPACE_ROOT` 告诉 Insta 在哪里查找和更新 `.snap` 文件
- **行为**: 测试在仓库根目录执行，快照路径相对于根目录解析

### 执行流程

```
Bazel 测试触发
    ↓
生成 workspace_root_test 目标
    ↓
expand_template 填充 .bat.tpl → .bat
    ↓
执行生成的 .bat 文件
    ↓
解析 __WORKSPACE_ROOT_MARKER__ → repo_root.marker 路径
    ↓
解析 __TEST_BIN__ → 测试二进制路径
    ↓
计算 workspace_root = marker/../../../
    ↓
设置 INSTA_WORKSPACE_ROOT
    ↓
cd %workspace_root%
    ↓
执行测试二进制
    ↓
返回测试结果
```

## 风险、边界与改进建议

### 风险点

1. **Windows 批处理限制**
   - 批处理对特殊字符和长路径的处理能力有限
   - 路径中包含空格或特殊字符可能导致解析失败
   - **缓解**: 使用引号包裹路径变量

2. **目录深度硬编码**
   ```batch
   for %%I in ("%workspace_root_marker_dir%..\..") do set "workspace_root=%%~fI"
   ```
   - 假设 marker 文件位于 `codex-rs/utils/cargo-bin/repo_root.marker`
   - 若目录结构变更，计算将出错
   - **缓解**: 文档化目录结构约定，添加变更检查

3. **Manifest 解析可靠性**
   - `findstr` 的搜索模式可能匹配到错误行
   - Manifest 文件格式变化可能导致解析失败

4. **错误处理不完整**
   - 部分错误情况仅输出到 stderr，未提供详细的诊断信息
   - 缺少对 `cd` 失败的具体原因说明

### 边界情况

1. **路径分隔符混合**
   ```batch
   set "native_logical_path=%logical_path:/=\%"
   ```
   - 仅转换正斜杠为反斜杠，不处理其他分隔符变体
   - 网络路径（`\\server\share`）可能处理不当

2. **环境变量缺失**
   - 若 `RUNFILES_DIR` 和 `TEST_SRCDIR` 都未定义，直接回退到 manifest
   - 若 manifest 也不存在，将报错但信息可能不够清晰

3. **并发执行**
   - 模板生成的脚本可能在同一目录并发执行
   - 但脚本本身无状态，无并发冲突风险

4. **长路径支持**
   - Windows 传统路径长度限制为 260 字符
   - 深嵌套的 Bazel 输出目录可能超出此限制
   - **缓解**: 使用 `\\?\` 前缀或启用 Windows 长路径支持

### 改进建议

1. **添加详细日志**
   ```batch
   @echo off
   if defined RBE_DEBUG (
       echo [DEBUG] Resolving runfile: %logical_path%
       echo [DEBUG] RUNFILES_DIR=%RUNFILES_DIR%
       echo [DEBUG] TEST_SRCDIR=%TEST_SRCDIR%
   )
   ```

2. **动态目录深度计算**
   ```batch
   :: 替代硬编码的 ..\..
   set "workspace_root=%workspace_root_marker%"
   for %%d in (
       "codex-rs" "utils" "cargo-bin"
   ) do (
       for %%I in ("%workspace_root%\..") do set "workspace_root=%%~fI"
   )
   ```

3. **增强错误信息**
   ```batch
   >&2 echo ERROR: Failed to resolve runfile: %logical_path%
   >&2 echo   Checked RUNFILES_DIR: %RUNFILES_DIR%
   >&2 echo   Checked TEST_SRCDIR: %TEST_SRCDIR%
   >&2 echo   Checked manifest: %manifest%
   ```

4. **PowerShell 迁移**
   - 考虑迁移到 PowerShell 脚本以获得更好的错误处理和路径操作
   - 但需确保目标 Windows 环境支持 PowerShell

5. **与 Unix 模板对齐**
   - 确保 `.bat.tpl` 和 `.sh.tpl` 的行为完全一致
   - 建立测试矩阵验证跨平台等价性

6. **单元测试**
   - 为 runfile 解析逻辑添加独立测试
   - 使用 mock 环境变量验证各种场景
