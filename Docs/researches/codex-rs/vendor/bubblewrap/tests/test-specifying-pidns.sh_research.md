# test-specifying-pidns.sh 研究文档

## 场景与职责

`test-specifying-pidns.sh` 是 bubblewrap 的 PID 命名空间指定功能测试，验证 `--pidns` 选项允许外部进程加入已存在的 PID 命名空间。该测试确保：
- bwrap 可以加入由另一个 bwrap 实例创建的 PID 命名空间
- 加入同一 PID 命名空间的进程能看到相同的进程 ID 空间
- 用户命名空间（`--userns`）与 PID 命名空间正确配合

该测试与 `test-specifying-userns.sh` 结构类似，共同验证命名空间共享功能。

## 功能点目的

### 1. 测试目标
验证 `--pidns <fd>` 选项功能，允许新 bwrap 实例加入已存在的 PID 命名空间。

### 2. 测试场景
- 创建第一个 bwrap 沙箱，创建新的用户和 PID 命名空间
- 从外部通过 `--pidns` 和 `--userns` 加入相同的命名空间
- 验证两个进程在同一个 PID 命名空间中

### 3. setuid 兼容性
- 该测试需要用户命名空间（`--unshare-user`）
- setuid 模式下不支持用户命名空间，测试自动跳过

## 具体技术实现

### 关键流程

1. **环境初始化**:
   ```bash
   srcd=$(cd $(dirname "$0") && pwd)
   . "${srcd}/libtest.sh"
   ```

2. **setuid 检查**:
   ```bash
   if test -n "${bwrap_is_suid:-}"; then
       echo "ok - # SKIP no setuid support for --unshare-user"
   ```

3. **FIFO 创建**:
   ```bash
   mkfifo donepipe
   ```
   用于协调父子进程生命周期

4. **第一个沙箱启动**:
   ```bash
   $RUN --info-fd 42 --unshare-user --unshare-pid sh -c \
       'readlink /proc/self/ns/pid > sandbox-pidns; cat < donepipe' \
       >/dev/null 42>info.json &
   ```
   - `--info-fd 42`: 输出沙箱信息到 FD 42
   - `--unshare-user --unshare-pid`: 创建新的用户和 PID 命名空间
   - 后台运行，通过 FIFO 保持存活

5. **等待沙箱就绪**:
   ```bash
   while ! test -f sandbox-pidns; do sleep 1; done
   ```
   轮询等待命名空间信息文件创建

6. **提取子进程 PID**:
   ```bash
   SANDBOX1PID=$(extract_child_pid info.json)
   ```
   从 info.json 解析第一个沙箱的真实 PID

7. **第二个沙箱加入命名空间**:
   ```bash
   ASAN_OPTIONS=detect_leaks=0 LSAN_OPTIONS=detect_leaks=0 \
   $RUN --userns 11 --pidns 12 readlink /proc/self/ns/pid > sandbox2-pidns \
       11< /proc/$SANDBOX1PID/ns/user \
       12< /proc/$SANDBOX1PID/ns/pid
   ```
   - `--userns 11`: 从 FD 11 读取用户命名空间
   - `--pidns 12`: 从 FD 12 读取 PID 命名空间
   - FD 11/12 绑定到第一个沙箱的 `/proc/$PID/ns/*`

8. **验证命名空间相同**:
   ```bash
   assert_files_equal sandbox-pidns sandbox2-pidns
   ```

9. **清理**:
   ```bash
   echo foo > donepipe  # 释放第一个沙箱
   rm donepipe info.json sandbox-pidns
   ```

### 数据结构

| 文件/变量 | 用途 |
|-----------|------|
| `donepipe` | FIFO 用于进程协调 |
| `info.json` | 第一个沙箱的信息输出 |
| `sandbox-pidns` | 第一个沙箱的 PID 命名空间 ID |
| `sandbox2-pidns` | 第二个沙箱的 PID 命名空间 ID |
| `SANDBOX1PID` | 第一个沙箱的子进程 PID |

### 关键代码路径

| 代码 | 行号 | 说明 |
|------|------|------|
| 库加载 | 5-6 | source libtest.sh |
| setuid 检查 | 11-13 | 条件跳过 |
| FIFO 创建 | 14 | 进程协调 |
| 第一个沙箱 | 15 | 创建命名空间 |
| 等待就绪 | 16 | 轮询同步 |
| PID 提取 | 17 | 解析 info.json |
| 第二个沙箱 | 19-20 | 加入命名空间 |
| 验证 | 23 | 比较命名空间 ID |
| 清理 | 25 | 资源释放 |

## 依赖与外部交互

### 外部命令
| 命令 | 用途 |
|------|------|
| `bwrap` | 被测程序 |
| `mkfifo` | 创建 FIFO |
| `readlink` | 读取命名空间 ID |
| `sleep` | 轮询等待 |
| `cat` | FIFO 读取/写入 |

### 库依赖
- `libtest.sh`: 测试基础设施
- `libtest-core.sh`: 断言库（通过 libtest.sh）

### 系统文件
- `/proc/$PID/ns/pid`: PID 命名空间入口
- `/proc/$PID/ns/user`: 用户命名空间入口

### 特殊环境变量
| 变量 | 用途 |
|------|------|
| `ASAN_OPTIONS=detect_leaks=0` | 禁用 AddressSanitizer 泄漏检测 |
| `LSAN_OPTIONS=detect_leaks=0` | 禁用 LeakSanitizer |

使用这些变量是因为测试涉及进程 fork 和复杂的生命周期管理，可能触发误报的泄漏检测。

### 调用关系
- **调用**: `libtest.sh` 提供的函数（`extract_child_pid`, `assert_files_equal`, `$RUN`）
- **被调用**: Meson 测试框架

## 风险、边界与改进建议

### 风险点
1. **轮询等待**: 使用 `sleep 1` 轮询，可能延迟测试或丢失事件
2. **僵尸进程**: 如果测试中断，后台进程可能成为僵尸
3. **命名空间泄漏**: 异常退出时命名空间可能未清理
4. **ASan/LSan 禁用**: 可能掩盖真实的内存问题

### 边界情况
1. **setuid 模式**: 整个测试被跳过
2. **命名空间不可用**: 内核不支持时测试失败
3. **/proc 访问**: 需要访问 `/proc/$PID/ns/*`
4. **权限**: 需要足够的权限创建用户命名空间

### 改进建议
1. **超时机制**: 添加最大等待时间防止无限阻塞
   ```bash
   timeout=30
   while ! test -f sandbox-pidns && [ $timeout -gt 0 ]; do
       sleep 1
       timeout=$((timeout - 1))
   done
   ```

2. **信号处理**: 添加 trap 确保清理
   ```bash
   cleanup() {
       [ -f donepipe ] && echo > donepipe 2>/dev/null || true
       rm -f donepipe info.json sandbox-pidns sandbox2-pidns
   }
   trap cleanup EXIT
   ```

3. **更精确同步**: 使用文件锁或 socket 替代轮询

4. **调试输出**: 添加 `set -x` 或条件调试输出

5. **并行安全**: 使用随机文件名避免并行测试冲突
   ```bash
   suffix=$$
   donepipe=donepipe.$suffix
   ```
