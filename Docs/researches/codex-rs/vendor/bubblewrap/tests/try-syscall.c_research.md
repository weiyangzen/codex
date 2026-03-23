# try-syscall.c 研究文档

## 场景与职责

`try-syscall.c` 是 seccomp 测试的辅助程序，被 `test-seccomp.py` 调用执行具体的系统调用并返回 errno。该程序设计为在 bwrap 创建的沙箱中运行，测试 seccomp 过滤器是否正确阻止或允许特定的系统调用。

该程序的设计原则是：**使用无效参数调用系统调用，使其在未被 seccomp 阻止时快速失败，从而区分 seccomp 阻止和系统调用正常执行**。

## 功能点目的

### 1. 系统调用测试执行器
提供统一的接口执行各种系统调用，返回最后一次失败的 errno。支持：
- 单系统调用测试
- 多系统调用链式测试（返回最后一个 errno）
- 错误码值打印（用于调试）

### 2. 安全失败设计
所有系统调用都使用无效参数，确保：
- **无副作用**: 不会因测试修改系统状态
- **快速失败**: 不等待 I/O 或网络
- **可区分错误**: seccomp 阻止（ENOSYS/ECONNREFUSED）vs 正常执行失败（EFAULT/EBADF）

### 3. 支持的系统调用

| 系统调用 | 测试参数 | 未阻止时期望错误 |
|----------|----------|------------------|
| `chmod` | 无效指针路径 | EFAULT |
| `chroot` | 无效指针路径 | EFAULT |
| `clone3` | 无效指针 + 有效大小 | EFAULT/ENOSYS |
| `ioctl TIOCNOTTY` | 无效 FD (-1) | EBADF |
| `ioctl TIOCSTI` | 无效 FD + 无效指针 | EBADF |
| `ioctl TIOCSTI CVE-2019-10063` | 64 位参数攻击 | EBADF |
| `listen` | 无效 FD (-1) | EBADF |
| `prctl` | 无效指针参数 | EFAULT |

### 4. 架构兼容性
支持多种 CPU 架构的系统调用号差异：
- **MIPS** (O32/N32/64): 4000/6000/5000 基址
- **IA-64**: 1024 基址
- **Alpha**: 110 基址
- **x32 ABI**: 0x40000000 基址

### 5. CVE-2019-10063 测试
专门测试 TIOCSTI ioctl 的 64 位参数绕过攻击：
- 构造高位被设置的 64 位 request 码
- 验证 seccomp 的 MASKED_EQ 是否能正确匹配

## 具体技术实现

### 关键流程

1. **clone3 系统调用号处理**:
   ```c
   #if defined(_MIPS_SIM)
   # if _MIPS_SIM == _ABIO32
   #   define MISSING_SYSCALL_BASE 4000
   # elif _MIPS_SIM == _ABI64
   #   define MISSING_SYSCALL_BASE 5000
   # elif _MIPS_SIM == _ABIN32
   #   define MISSING_SYSCALL_BASE 6000
   # endif
   #endif
   
   #ifndef __NR_clone3
   # define __NR_clone3 (MISSING_SYSCALL_BASE + 435)
   #endif
   ```

2. **无效指针定义**:
   ```c
   #define WRONG_POINTER ((char *) 1)
   ```
   使用地址 1，保证触发 EFAULT

3. **命令行解析循环**:
   ```c
   for (i = 1; i < argc; i++) {
       const char *arg = argv[i];
       if (strcmp (arg, "chmod") == 0) { ... }
       else if (strcmp (arg, "chroot") == 0) { ... }
       // ...
   }
   return errsv;
   ```

4. **chmod 测试实现**:
   ```c
   if (chmod (WRONG_POINTER, 0700) != 0) {
       errsv = errno;
       perror (arg);
   }
   ```

5. **CVE-2019-10063 测试**:
   ```c
   #ifdef __LP64__
   else if (strcmp (arg, "ioctl TIOCSTI CVE-2019-10063") == 0) {
       unsigned long not_TIOCSTI = (0x123UL << 32) | (unsigned long) TIOCSTI;
       if (syscall (__NR_ioctl, -1, not_TIOCSTI, WRONG_POINTER) != 0) {
           errsv = errno;
           perror (arg);
       }
   }
   #endif
   ```
   仅在 64 位平台测试，32 位平台返回 ENOENT

6. **错误码打印模式**:
   ```c
   if (strcmp (arg, "print-errno-values") == 0) {
       printf ("EBADF=%d\n", EBADF);
       printf ("EFAULT=%d\n", EFAULT);
       // ...
   }
   ```

### 数据结构

| 常量/宏 | 值 | 说明 |
|---------|-----|------|
| `MISSING_SYSCALL_BASE` | 架构相关 | 新系统调用基址偏移 |
| `SIZEOF_STRUCT_CLONE_ARGS` | 88 | clone3 参数结构大小 |
| `WRONG_POINTER` | (char *)1 | 无效指针 |
| `__NR_clone3` | MISSING_SYSCALL_BASE + 435 | clone3 系统调用号 |
| `PR_GET_CHILD_SUBREAPER` | 37 | prctl 命令（如未定义） |

### 关键代码路径

| 代码 | 行号 | 说明 |
|------|------|------|
| 架构基址定义 | 26-58 | MISSING_SYSCALL_BASE |
| clone3 定义 | 60-67 | 系统调用号 |
| 常量定义 | 67-76 | 结构大小、无效指针 |
| errno 打印 | 88-95 | 调试模式 |
| chmod | 96-104 | 权限修改测试 |
| chroot | 105-113 | 根切换测试 |
| clone3 | 114-122 | 进程创建测试 |
| ioctl TIOCNOTTY | 123-131 | TTY 分离测试 |
| ioctl TIOCSTI | 132-140 | 终端注入测试 |
| CVE-2019-10063 | 141-153 | 64 位绕过测试 |
| listen | 154-162 | 监听测试 |
| prctl | 163-171 | 进程控制测试 |

## 依赖与外部交互

### 头文件依赖
| 头文件 | 用途 |
|--------|------|
| `<errno.h>` | 错误码常量 |
| `<stdio.h>` | 标准 IO |
| `<string.h>` | 字符串操作 |
| `<unistd.h>` | 标准系统调用 |
| `<sys/ioctl.h>` | ioctl 定义 |
| `<sys/prctl.h>` | prctl 定义 |
| `<sys/socket.h>` | listen 定义 |
| `<sys/syscall.h>` | syscall() 包装 |
| `<sys/stat.h>` | chmod 定义 |
| `<sys/types.h>` | 类型定义 |

### 系统调用使用
| 调用 | 用途 |
|------|------|
| `chmod()` | 文件权限 |
| `chroot()` | 根目录切换 |
| `syscall(__NR_clone3, ...)` | 进程创建 |
| `ioctl()` | 设备控制 |
| `listen()` | 网络监听 |
| `prctl()` | 进程控制 |

### 调用关系
- **被调用**: `test-seccomp.py` 通过 bwrap 调用
- **调用方式**:
  ```python
  subprocess.run(
      [self.bwrap, '--ro-bind', '/', '/', self.try_syscall, 'chmod'],
      ...
  )
  ```

### 构建配置
- **特殊选项**: `override_options: ['b_sanitize=none']`
- **原因**: sanitize 可能干扰系统调用行为或错误码

## 风险、边界与改进建议

### 风险点
1. **架构支持不完整**: 仅支持列出的架构，新架构需要更新
2. **clone3 结构大小**: 硬编码 88 字节，未来内核可能改变
3. **64 位假设**: CVE-2019-10063 测试仅在 `__LP64__` 定义时编译
4. **错误码依赖**: 依赖 EFAULT/EBADF 行为，不同内核可能不同

### 边界情况
1. **内核不支持 clone3**: 返回 ENOSYS，需要与 seccomp 阻止区分
2. **32 位系统**: 64 位参数测试被跳过（返回 ENOENT）
3. **多系统调用**: 支持链式调用，但只返回最后一个 errno
4. **无效参数**: 未识别的系统调用名返回 ENOENT

### 改进建议
1. **运行时内核版本检测**: 检测 clone3 支持，避免 ENOSYS 歧义
   ```c
   #include <linux/version.h>
   #if LINUX_VERSION_CODE >= KERNEL_VERSION(5,3,0)
   ```

2. **动态结构大小**: 使用 sizeof 而非硬编码
   ```c
   struct clone_args args;
   syscall(__NR_clone3, WRONG_POINTER, sizeof(args));
   ```

3. **更多架构支持**: 添加 ARM、RISC-V、LoongArch 等

4. **错误码验证**: 添加模式验证返回的错误码是否在预期集合中

5. **详细输出**: 添加 verbose 模式输出每个系统调用的详细结果

6. **信号测试**: 添加信号相关系统调用测试（如 kill, sigaction）

7. **网络测试扩展**: 添加更多网络相关调用（socket, connect, bind）

8. **文件系统测试**: 添加 openat, mkdirat 等新 API 测试

9. **时间测试**: 添加 clock_settime 等时间相关调用

10. **同步机制**: 添加 futex 等同步原语测试
