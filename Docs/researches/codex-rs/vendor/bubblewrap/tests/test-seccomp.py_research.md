# test-seccomp.py 研究文档

## 场景与职责

`test-seccomp.py` 是 bubblewrap 的 seccomp（安全计算模式）过滤测试套件，使用 Python 的 `seccomp` 库和 `unittest` 框架验证 bwrap 的 `--seccomp` 和 `--add-seccomp-fd` 功能。该测试确保：
- bwrap 能正确加载和应用 seccomp BPF 过滤器
- 允许列表（allowlist）和拒绝列表（denylist）模式工作正常
- 多个 seccomp 过滤器可以堆叠使用
- 无效输入被正确拒绝

该测试与 `try-syscall.c` 配合，后者执行具体的系统调用并返回 errno。

## 功能点目的

### 1. 系统调用集合定义
定义多个系统调用集合用于构建过滤器：
- **DEFAULT_SET**: systemd @default 集合（基本进程控制）
- **BASIC_IO_SET**: systemd @basic-io 集合（基本 IO 操作）
- **FILESYSTEM_SET**: systemd @filesystem-io 集合（文件系统操作）
- **ALLOWED**: 合并集合 + 启动所需额外调用（arch_prctl, ioctl, madvise 等）

### 2. 测试系统调用列表
定义要测试的具体系统调用：
- `chmod`: 文件权限修改
- `chroot`: 根目录切换
- `clone3`: 新进程创建（Linux 5.3+）
- `ioctl TIOCNOTTY`: TTY 控制
- `ioctl TIOCSTI`: 终端输入注入（CVE-2019-10063 相关）
- `ioctl TIOCSTI CVE-2019-10063`: 64 位参数测试
- `listen`: 网络监听
- `prctl`: 进程控制

### 3. 测试方法

#### test_no_seccomp
- **目的**: 建立基线，验证系统调用在无 seccomp 时的行为
- **期望**: 系统调用执行并返回 EFAULT/EBADF（无效参数导致的正常失败）
- **特殊处理**: clone3 可能返回 ENOSYS（内核不支持）

#### test_seccomp_allowlist
- **目的**: 测试允许列表模式（默认拒绝，显式允许）
- **过滤器配置**: `seccomp.ERRNO(errno.ENOSYS)` 作为默认动作
- **验证点**:
  - 允许的调用返回 EFAULT/EBADF（执行后失败）
  - 未允许的调用返回 ENOSYS（被 seccomp 阻止）

#### test_seccomp_denylist
- **目的**: 测试拒绝列表模式（默认允许，显式拒绝）
- **过滤器配置**: `seccomp.ALLOW` 作为默认动作
- **拒绝规则**: 使用 ECONNREFUSED 作为拒绝错误码（不太可能自然发生）
- **验证点**:
  - 被拒绝的调用返回 ECONNREFUSED
  - 允许的调用正常执行

#### test_seccomp_stacked / test_seccomp_stacked_allowlist_first
- **目的**: 测试多个 seccomp 过滤器堆叠
- **配置**: 一个 allowlist 和一个 denylist 过滤器
- **关键行为**:
  - 最近添加的过滤器优先
  - 拒绝优先于允许（无论顺序）
  - prctl 必须被除最后一个外的所有过滤器允许（用于加载后续过滤器）

#### test_seccomp_invalid
- **目的**: 测试无效输入处理
- **测试用例**:
  - 无效文件描述符（-1）
  - 非数字 FD 字符串（"0a"）
  - `--seccomp` 和 `--add-seccomp-fd` 混用
  - 重复 FD 参数
  - 非 8 字节对齐的 BPF 数据

## 具体技术实现

### 关键流程

1. **测试环境设置**:
   ```python
   def setUp(self) -> None:
       # 检测 G_TEST_SRCDIR/G_TEST_BUILDDIR
       # 验证 bwrap 可执行
       completed = subprocess.run([self.bwrap, '--ro-bind', '/', '/', 'true'])
       if completed.returncode != 0:
           raise unittest.SkipTest('cannot run bwrap')
   ```

2. **Allowlist 过滤器构建**:
   ```python
   allowlist = seccomp.SyscallFilter(seccomp.ERRNO(errno.ENOSYS))
   if os.uname().machine == 'x86_64':
       allowlist.add_arch(seccomp.Arch.X86)  # 支持 32 位兼容
   for syscall in ALLOWED:
       allowlist.add_rule(seccomp.ALLOW, syscall)
   allowlist.export_bpf(allowlist_temp)
   ```

3. **Denylist ioctl 参数匹配**:
   ```python
   denylist.add_rule(
       seccomp.ERRNO(errno.ECONNREFUSED), 'ioctl',
       seccomp.Arg(1, seccomp.MASKED_EQ, 0xffffffff, termios.TIOCSTI),
   )
   ```
   使用 MASKED_EQ 匹配 ioctl 的第二个参数（request 码）

4. **堆叠过滤器执行**:
   ```python
   completed = subprocess.run(
       [
           self.bwrap,
           '--ro-bind', '/', '/',
           '--add-seccomp-fd', str(fds[0]),
           '--add-seccomp-fd', str(fds[1]),
           self.try_syscall, syscall,
       ],
       pass_fds=fds,  # 关键：保持 FD 打开
       ...
   )
   ```

5. **TAP 输出适配**:
   ```python
   def main():
       try:
           from tap.runner import TAPTestRunner
           runner = TAPTestRunner()
           runner.set_stream(True)
           unittest.main(testRunner=runner)
       except ImportError:
           # 简单 TAP 输出回退
   ```

### 数据结构

| 集合/变量 | 内容 |
|-----------|------|
| DEFAULT_SET | 约 40 个基本系统调用 |
| BASIC_IO_SET | 11 个 IO 相关调用 |
| FILESYSTEM_SET | 76 个文件系统调用 |
| ALLOWED | 上述合并 + 额外调用 |
| TRY_SYSCALLS | 8 个测试目标调用 |

### 关键代码路径

| 代码 | 行号 | 说明 |
|------|------|------|
| 系统调用集合 | 21-194 | 集合定义 |
| TRY_SYSCALLS | 197-207 | 测试目标列表 |
| setUp | 210-240 | 环境初始化 |
| test_no_seccomp | 245-277 | 基线测试 |
| test_seccomp_allowlist | 279-331 | 允许列表测试 |
| test_seccomp_denylist | 333-391 | 拒绝列表测试 |
| test_seccomp_stacked | 393-497 | 堆叠测试 |
| test_seccomp_invalid | 501-609 | 无效输入测试 |
| main | 612-635 | TAP 适配 |

## 依赖与外部交互

### Python 依赖
| 模块 | 用途 |
|------|------|
| `seccomp` | BPF 过滤器构建（必需，缺失则跳过） |
| `unittest` | 测试框架 |
| `errno` | 错误码常量 |
| `os/subprocess/tempfile` | 系统交互 |
| `termios` | TIOCSTI 常量 |
| `tap.runner` | TAP 输出（可选） |

### 外部程序
| 程序 | 用途 |
|------|------|
| `bwrap` | 被测程序 |
| `try-syscall` | 系统调用执行辅助 |

### 环境变量
| 变量 | 说明 |
|------|------|
| `G_TEST_SRCDIR` | 测试源目录 |
| `G_TEST_BUILDDIR` | 测试构建目录 |
| `BWRAP` | bwrap 可执行文件路径 |

### 调用关系
- **调用**: `try-syscall` 执行具体系统调用
- **被调用**: Meson 测试框架通过 Python 解释器执行

## 风险、边界与改进建议

### 风险点
1. **seccomp 模块依赖**: 未安装时整个测试被跳过
2. **架构特定代码**: x86_64 特殊处理 32 位兼容，其他架构未测试
3. **内核版本依赖**: clone3 测试需要 Linux 5.3+
4. **TIOCSTI 64 位测试**: 仅在 `__LP64__` 环境测试 CVE-2019-10063

### 边界情况
1. **ENOENT 处理**: TIOCSTI CVE 测试在 32 位系统返回 ENOENT（64 位参数不支持）
2. **ENOSYS 歧义**: clone3 可能因 seccomp 或内核不支持返回 ENOSYS
3. **EBADF vs EFAULT**: 不同系统调用因参数类型返回不同错误

### 改进建议
1. **架构扩展**: 添加 ARM、RISC-V 等架构的 multi-arch 支持
2. **内核版本检测**: 显式检查内核版本，区分不支持和阻止
3. **覆盖率**: 添加 BPF 程序覆盖率分析
4. **性能测试**: 测量 seccomp 对系统调用延迟的影响
5. **模糊测试**: 对 BPF 数据解析进行模糊测试
6. **文档**: 添加更多注释说明每个测试的系统调用选择理由
7. **错误消息**: 失败时输出 seccomp 日志（如可用）
