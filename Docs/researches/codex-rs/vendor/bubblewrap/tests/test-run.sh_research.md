# test-run.sh 研究文档

## 场景与职责

`test-run.sh` 是 bubblewrap 的核心功能测试套件，包含 100+ 个测试用例，全面验证 bwrap 的各种功能。该脚本使用 TAP（Test Anything Protocol）格式输出测试结果，涵盖：
- 基础功能（help、bind mount、命名空间隔离）
- 安全特性（权限检查、不可读文件访问控制）
- 设备管理（/dev 创建、设备节点）
- 进程管理（--as-pid-1、--die-with-parent）
- 信息输出（--info-fd、--json-status-fd）
- 文件系统操作（tmpfs、overlay、权限设置）
- 环境控制（环境变量、argv0）

## 功能点目的

### 1. 基础功能测试（行 23-77）
- **Help 测试**: 验证 `--help` 输出包含 usage 信息
- **FUSE bind 测试**: 测试 FUSE 目录作为 bind mount 源
- **Proc 挂载测试**: 验证 /proc 挂载功能
- **网络隔离测试**: 验证 `--unshare-net` 功能
- **安全访问测试**: 验证无法通过 bind mount 读取 /etc/shadow 等敏感文件
- **符号链接 bind 测试**: 验证 bind 目标可以是符号链接

### 2. 符号链接测试（行 79-92）
- 验证 `--symlink` 创建符号链接
- 验证符号链接创建的幂等性
- 验证冲突符号链接检测

### 3. 设备管理测试（行 94-96）
- 验证标准设备节点创建（stdin, stdout, stderr, null, random, urandom, fd, core）

### 4. 进程管理测试（行 98-130）
- **--as-pid-1**: 验证进程可作为 PID 1 运行
- **--info-fd / --json-status-fd**: 验证状态信息输出
- **命名空间信息**: 验证 IPC、MNT、NET、PID、UTS 命名空间 ID 输出
- **故障注入测试**: 使用 strace 故障注入测试 pre-exec 失败处理
- **exec 失败测试**: 验证不可执行文件的错误处理

### 5. 用户命名空间测试（行 136-170）
- **递归 bwrap**: 在非 setuid 模式下测试嵌套 bwrap
- **--disable-userns**: 验证用户命名空间禁用功能
- **嵌套限制**: 验证通过 procfs 限制嵌套命名空间创建

### 6. 错误处理测试（行 172-177）
- 验证错误消息前缀格式

### 7. 权限测试（行 179-213）
- **非 root 模式**: 验证无权限保留
- **root 模式**: 验证权限正确传递和 `--cap-drop` 功能

### 8. --die-with-parent 测试（行 215-260）
- 使用文件锁和 Python 脚本协调父子进程
- 验证父进程终止时子进程被正确清理

### 9. 参数解析测试（行 262-282）
- **--args**: 验证从文件描述符读取参数
- **-- 分隔符**: 验证 `--` 正确分隔选项和命令

### 10. Bind Mount 测试（行 283-354）
- 验证 /tmp 绑定行为
- 验证 oldroot/newroot 不可见
- 验证挂载点权限（文件 444，目录 755）

### 11. 目录权限测试（行 356-438）
- 验证 `--dir` 创建的目录权限
- 验证 `--perms` 和 `--chmod` 选项
- 验证父目录自动创建的权限继承

### 12. Tmpfs 测试（行 440-486）
- 验证 tmpfs 挂载和权限设置
- 验证 `--size` 选项限制大小
- 验证无效大小参数被拒绝

### 13. 文件创建测试（行 488-512）
- 验证 `--file`、`--bind-data`、`--ro-bind-data` 创建的文件权限

### 14. 环境控制测试（行 548-566）
- 验证 `--setenv`、`--unsetenv`、`--clearenv`
- 验证 `--argv0` 修改

### 15. 其他功能测试（行 568-580）
- `--bind-fd`: 通过文件描述符绑定
- `--chdir`: 目录切换和警告
- `--level-prefix`: 日志级别前缀

### 16. Overlay 测试（行 582-690）
- **--overlay**: 可写 overlay 挂载
- **--tmp-overlay**: 临时 overlay（无持久化上层）
- **--ro-overlay**: 只读 overlay
- **--overlay-src**: 源目录指定
- 路径转义测试（特殊字符 `: , \`）

## 具体技术实现

### 关键流程

1. **TAP 输出格式**:
   ```bash
   test_count=0
   ok () {
       test_count=$((test_count + 1))
       echo ok $test_count "$@"
   }
   done_testing () {
       echo "1..$test_count"
   }
   ```

2. **循环测试模式**:
   ```bash
   for ALT in "" "--unshare-user-try" "--unshare-pid" "--unshare-user-try --unshare-pid"; do
       # 测试用例...
   done
   ```
   使用不同命名空间组合运行相同测试

3. **setuid 条件跳过**:
   ```bash
   if test -n "${bwrap_is_suid:-}"; then
       ok_skip "no --cap-add support"
   else
       # 非 setuid 测试...
   fi
   ```

4. **die-with-parent 测试协调**:
   ```bash
   mkfifo donepipe
   $RUN --info-fd 42 ... &
   # 等待锁...
   kill -9 ${childshellpid}
   # 验证锁释放
   ```

5. **Overlay 测试准备**:
   ```bash
   mkdir lower1 lower2 upper work
   printf 1 > lower1/a
   printf 2 > lower1/b
   printf 3 > lower2/b
   printf 4 > upper/a
   ```

### 数据结构

| 变量/文件 | 用途 |
|-----------|------|
| `test_count` | TAP 测试计数器 |
| `help.txt` | --help 输出捕获 |
| `target.txt` | 符号链接目标验证 |
| `err.txt` | 错误输出捕获 |
| `as_pid_1.txt` | PID 1 测试输出 |
| `info.json` | --info-fd JSON 输出 |
| `json-status.json` | --json-status-fd 输出 |
| `caps.test` | 权限测试输出 |
| `lockf-n.py` | Python 锁脚本 |
| `donepipe` | FIFO 协调进程 |
| `lower1/lower2/upper/work` | Overlay 测试目录 |

### 关键代码路径

| 功能 | 行号范围 | 说明 |
|------|----------|------|
| Help 测试 | 23-26 | 基础功能验证 |
| FUSE/bind 循环 | 28-77 | 多配置组合测试 |
| 符号链接测试 | 79-92 | symlink 行为验证 |
| 设备测试 | 94-96 | /dev 节点创建 |
| PID 1 测试 | 98-101 | --as-pid-1 |
| 信息 FD 测试 | 103-129 | info/json-status |
| 嵌套 bwrap | 136-170 | --disable-userns |
| 错误前缀 | 172-177 | 错误格式 |
| 权限测试 | 179-213 | cap 管理 |
| die-with-parent | 215-260 | 父子进程生命周期 |
| 参数解析 | 262-282 | --args, -- |
| Bind mount | 283-354 | /tmp 行为 |
| 目录权限 | 356-438 | --dir, --perms |
| Tmpfs | 440-486 | --tmpfs, --size |
| 文件权限 | 488-512 | --file, --bind-data |
| 环境控制 | 548-566 | env, argv0 |
| bind-fd | 568-572 | FD 绑定 |
| chdir/level-prefix | 574-580 | 警告和日志 |
| Overlay | 582-690 | overlayfs 测试 |

## 依赖与外部交互

### 外部命令
| 命令 | 用途 |
|------|------|
| `bwrap` | 被测程序 |
| `true/false` | 占位命令 |
| `ls/stat/readlink` | 文件系统检查 |
| `cat/grep/sed/awk` | 文本处理 |
| `strace` | 故障注入（可选） |
| `capsh/getpcaps` | 权限检查 |
| `python3` | lockf-n.py 执行 |
| `findmnt` | 挂载信息 |
| `df` | 文件系统大小 |
| `diff` | 文件比较 |
| `chmod/mkdir/rm/touch` | 文件操作 |
| `mkfifo` | FIFO 创建 |
| `kill` | 信号发送 |

### 库依赖
- `libtest.sh`: 测试基础设施
- `libtest-core.sh`: 断言库

### 系统文件
- `/etc/shadow`: 权限测试目标
- `/proc/self/ns/*`: 命名空间信息
- `/proc/sys/user/max_user_namespaces`: 命名空间限制

### Python 脚本（lockf-n.py）
```python
import struct,fcntl,sys
# 实现文件锁等待/非阻塞获取
```

## 风险、边界与改进建议

### 风险点
1. **strace 依赖**: 故障注入测试依赖 strace 特定版本功能
2. **时序敏感**: die-with-parent 测试使用 sleep 循环等待，可能不稳定
3. **系统依赖**: /etc/shadow 权限测试依赖特定系统配置
4. **Overlay 测试**: 需要内核支持 unprivileged overlayfs

### 边界情况
1. **无 FUSE**: FUSE 相关测试自动跳过
2. **setuid 模式**: 大量测试被跳过（用户命名空间相关）
3. **无 strace**: 故障注入测试跳过
4. **旧内核**: Overlay 测试跳过
5. **非 root**: 权限测试使用不同代码路径

### 改进建议
1. **超时机制**: 为 die-with-parent 测试添加明确超时
2. **重试逻辑**: 对时序敏感测试添加有限重试
3. **并行安全**: 使用 `$$` 或随机数隔离临时文件
4. **测试分组**: 按功能分组，支持选择性执行
5. **日志增强**: 失败时输出更多诊断信息
6. **容器适配**: 检测容器环境并调整测试期望
7. **覆盖率报告**: 集成覆盖率收集
