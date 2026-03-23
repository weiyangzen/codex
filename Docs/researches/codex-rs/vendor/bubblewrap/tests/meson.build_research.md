# meson.build (tests) 研究文档

## 场景与职责

`tests/meson.build` 是 bubblewrap 测试套件的 Meson 构建配置，定义了测试程序、测试脚本、依赖关系和测试执行环境。它负责：
- 编译测试辅助程序（test-utils, try-syscall）
- 配置测试脚本执行环境
- 设置测试发现和执行规则
- 管理测试依赖（SELinux、Python seccomp 模块等）

该文件与根目录 `meson.build` 配合，构成完整的测试构建系统。

## 功能点目的

### 1. 测试程序定义
- **test-utils**: 单元测试程序，测试 utils.c 中的工具函数
  - 源文件: `test-utils.c`, `../utils.c`, `../utils.h`
  - 依赖: `selinux_dep`
  - 包含目录: `common_include_directories`

- **try-syscall**: seccomp 测试辅助程序
  - 源文件: `try-syscall.c`
  - 特殊选项: 禁用 sanitize（`b_sanitize=none`）
  - 用途: 被 `test-seccomp.py` 调用测试系统调用过滤

### 2. 测试脚本列表
定义需要执行的测试脚本：
- `test-run.sh`: 主功能测试套件
- `test-seccomp.py`: seccomp 过滤测试
- `test-specifying-pidns.sh`: PID 命名空间指定测试
- `test-specifying-userns.sh`: 用户命名空间指定测试

### 3. 测试环境配置
设置测试执行环境变量：
- `BWRAP`: bwrap 可执行文件的完整路径
- `G_TEST_BUILDDIR`: 构建目录
- `G_TEST_SRCDIR`: 源目录

### 4. 测试协议支持
- Meson >= 0.50.0: 使用 TAP 协议（`protocol : 'tap'`）
- Meson < 0.50.0: 不使用特定协议

### 5. 解释器选择
根据脚本扩展名选择执行解释器：
- `.py` 文件: 使用 `python` 解释器
- 其他: 使用 `bash` 解释器

## 具体技术实现

### 关键流程

1. **测试程序编译**:
   ```meson
   test_programs = [
     ['test-utils', executable(
       'test-utils',
       'test-utils.c',
       '../utils.c',
       '../utils.h',
       dependencies : [selinux_dep],
       include_directories : common_include_directories,
     )],
   ]
   ```

2. **try-syscall 特殊配置**:
   ```meson
   executable(
     'try-syscall',
     'try-syscall.c',
     override_options: ['b_sanitize=none'],
   )
   ```
   禁用 sanitize 避免干扰系统调用测试

3. **测试环境设置**:
   ```meson
   test_env = environment()
   test_env.set('BWRAP', bwrap.full_path())
   test_env.set('G_TEST_BUILDDIR', meson.current_build_dir() / '..')
   test_env.set('G_TEST_SRCDIR', meson.current_source_dir() / '..')
   ```

4. **测试程序循环注册**:
   ```meson
   foreach pair : test_programs
     name = pair[0]
     test_program = pair[1]
     if meson.version().version_compare('>=0.50.0')
       test(name, test_program, env : test_env, protocol : 'tap')
     else
       test(name, test_program, env : test_env)
     endif
   endforeach
   ```

5. **测试脚本循环注册**:
   ```meson
   foreach test_script : test_scripts
     if test_script.endswith('.py')
       interpreter = python
     else
       interpreter = bash
     endif
     # ... test registration
   endforeach
   ```

### 数据结构

| 变量 | 类型 | 说明 |
|------|------|------|
| `test_programs` | list | 测试程序定义列表 [name, executable] |
| `test_scripts` | list | 测试脚本文件名列表 |
| `test_env` | environment | 测试环境变量对象 |
| `bwrap` | executable | 从根 meson.build 传入的 bwrap 目标 |
| `python` | external_program | Python 解释器 |
| `bash` | external_program | Bash 解释器 |

### 关键代码路径

| 代码 | 行号 | 说明 |
|------|------|------|
| test-utils 定义 | 1-10 | 单元测试可执行文件 |
| try-syscall 定义 | 12-16 | seccomp 测试辅助程序 |
| 测试脚本列表 | 18-23 | 脚本测试定义 |
| 环境变量设置 | 25-28 | 测试环境配置 |
| 测试程序循环 | 30-47 | 注册编译型测试 |
| 测试脚本循环 | 49-72 | 注册脚本型测试 |

## 依赖与外部交互

### 外部依赖
| 依赖 | 来源 | 用途 |
|------|------|------|
| `selinux_dep` | 根 meson.build | test-utils 的 SELinux 支持 |
| `common_include_directories` | 根 meson.build | 头文件搜索路径 |
| `bwrap` | 根 meson.build | bwrap 可执行文件目标 |
| `python` | 根 meson.build | Python 脚本解释器 |
| `bash` | 系统 | Shell 脚本解释器 |

### 源文件依赖
- `test-utils.c`: 单元测试代码
- `../utils.c`, `../utils.h`: 被测试的工具函数
- `try-syscall.c`: 系统调用测试辅助程序

### 测试脚本依赖
- `test-run.sh`: 依赖 `libtest.sh`, `libtest-core.sh`
- `test-seccomp.py`: 依赖 `try-syscall`, Python `seccomp` 模块
- `test-specifying-*.sh`: 依赖 `libtest.sh`

### 被调用关系
- 被根 `meson.build` 通过 `subdir('tests')` 包含
- 依赖根目录定义的变量和目标

## 风险、边界与改进建议

### 风险点
1. **Meson 版本兼容**: 条件逻辑处理 TAP 协议，但其他功能可能也有版本要求
2. **硬编码解释器**: `python` 和 `bash` 变量假设在根目录已正确定义
3. **路径假设**: `..` 相对路径假设 tests 是一级子目录
4. **sanitize 禁用**: `try-syscall` 禁用 sanitize 可能掩盖真实问题

### 边界情况
1. **SELinux 不可用**: `selinux_dep` 可能为空，但 test-utils 仍尝试链接
2. **Python 不可用**: 未处理 python 变量未定义的情况
3. **TAP 协议回退**: 旧版 Meson 缺少协议规范，测试输出解析可能不一致

### 改进建议
1. **依赖检查增强**:
   ```meson
   if not python.found()
     warning('Python not found, skipping test-seccomp.py')
   endif
   ```

2. **可选 SELinux**: 将 SELinux 依赖设为可选
   ```meson
   dependencies : [selinux_dep, libselinux_optional]
   ```

3. **测试分组**: 添加测试套件分组（unit, integration, seccomp）
   ```meson
   test(..., suite : 'seccomp')
   ```

4. **超时设置**: 为长时间运行的测试添加超时
   ```meson
   test(..., timeout : 60)
   ```

5. **并行控制**: 为相互依赖的测试添加 `is_parallel : false`

6. **环境变量验证**: 添加运行时检查确保必要变量已设置
