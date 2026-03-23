# test-specifying-userns.sh 研究文档

## 场景与职责

`test-specifying-userns.sh` 是 bubblewrap 的用户命名空间指定功能测试，验证 `--userns` 选项允许外部进程加入已存在的用户命名空间。该测试确保：
- bwrap 可以加入由另一个 bwrap 实例创建的用户命名空间
- 加入同一用户命名空间的进程具有相同的 UID/GID 映射
- 用户命名空间共享是容器嵌套和协作的基础机制

该测试与 `test-specifying-pidns.sh` 结构类似，但专注于用户命名空间。

## 功能点目的

### 1. 测试目标
验证 `--userns <fd>` 选项功能，允许新 bwrap 实例加入已存在的用户命名空间。

### 2. 测试场景
- 创建第一个 bwrap 沙箱，创建新的用户命名空间
- 从外部通过 `--userns` 加入相同的用户命名空间
- 验证两个进程在同一个用户命名空间中

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
   $RUN --info-fd 42 --unshare-user sh -c \
       'readlink /proc/self/ns/user > sandbox-userns; cat < donepipe' \
       >/dev/null 42>info.json &
   ```
   - `--info-fd 42`: 输出沙箱信息到 FD 42
   - `--unshare-user`: 创建新的用户命名空间
   - 后台运行，通过 FIFO 保持存活

5. **等待沙箱就绪**:
   ```bash
   while ! test -f sandbox-userns; do sleep 1; done
   ```
   轮询等待命名空间信息文件创建

6. **提取子进程 PID**:
   ```bash
   SANDBOX1PID=$(extract_child_pid info.json)
   ```
   从 info.json 解析第一个沙箱的真实 PID

7. **第二个沙箱加入命名空间**:
   ```bash
   $RUN --userns 11 readlink /proc/self/ns/user > sandbox2-userns \
       11< /proc/$SANDBOX1PID/ns/user
   ```
   - `--userns 11`: 从 FD 11 读取用户命名空间
   - FD 11 绑定到第一个沙箱的 `/proc/$PID/ns/user`

8. **验证命名空间相同**:
   ```bash
   assert_files_equal sandbox-userns sandbox2-userns
   ```

9. **清理**:
   ```bash
   echo foo > donepipe  # 释放第一个沙箱
   rm donepipe info.json sandbox-userns
   ```

### 数据结构

| 文件/变量 | 用途 |
|-----------|------|
| `donepipe` | FIFO 用于进程协调 |
| `info.json` | 第一个沙箱的信息输出 |
| `sandbox-userns` | 第一个沙箱的用户命名空间 ID |
| `sandbox2-userns` | 第二个沙箱的用户命名空间 ID |
| `SANDBOX1PID` | 第一个沙箱的子进程 PID |

### 关键代码路径

| 代码 | 行号 | 说明 |
|------|------|------|
| 库加载 | 5-6 | source libtest.sh |
| setuid 检查 | 11-13 | 条件跳过 |
| FIFO 创建 | 14 | 进程协调 |
| 第一个沙箱 | 16 | 创建命名空间 |
| 等待就绪 | 17 | 轮询同步 |
| PID 提取 | 18 | 解析 info.json |
| 第二个沙箱 | 20 | 加入命名空间 |
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
- `/proc/$PID/ns/user`: 用户命名空间入口

### 调用关系
- **调用**: `libtest.sh` 提供的函数（`extract_child_pid`, `assert_files_equal`, `$RUN`）
- **被调用**: Meson 测试框架

## 与 test-specifying-pidns.sh 的差异

| 方面 | test-specifying-userns.sh | test-specifying-pidns.sh |
|------|---------------------------|--------------------------|
| 测试目标 | `--userns` | `--pidns` |
| 命名空间类型 | 用户命名空间 | PID 命名空间 |
| 第一个沙箱选项 | `--unshare-user` | `--unshare-user --unshare-pid` |
| 第二个沙箱选项 | `--userns 11` | `--userns 11 --pidns 12` |
| 读取文件 | `/proc/self/ns/user` | `/proc/self/ns/pid` |
| ASan/LSan 禁用 | 否 | 是 |

### ASan/LSan 差异说明
`test-specifying-pidns.sh` 禁用了 AddressSanitizer 和 LeakSanitizer，而 `test-specifying-userns.sh` 没有。这可能是因为：
- PID 命名空间测试涉及更复杂的进程关系
- PID 命名空间测试可能触发更多的 fork/clone 路径
- 或者是历史遗留的不一致

建议统一两个测试的处理方式。

## 风险、边界与改进建议

### 风险点
1. **轮询等待**: 使用 `sleep 1` 轮询，可能延迟测试或丢失事件
2. **僵尸进程**: 如果测试中断，后台进程可能成为僵尸
3. **命名空间泄漏**: 异常退出时命名空间可能未清理

### 边界情况
1. **setuid 模式**: 整个测试被跳过
2. **命名空间不可用**: 内核不支持时测试失败
3. **/proc 访问**: 需要访问 `/proc/$PID/ns/user`
4. **权限**: 需要足够的权限创建用户命名空间
5. **用户命名空间限制**: `/proc/sys/user/max_user_namespaces` 可能限制创建

### 改进建议
1. **超时机制**: 添加最大等待时间防止无限阻塞
   ```bash
   timeout=30
   while ! test -f sandbox-userns && [ $timeout -gt 0 ]; do
       sleep 1
       timeout=$((timeout - 1))
   done
   ```

2. **信号处理**: 添加 trap 确保清理
   ```bash
   cleanup() {
       [ -f donepipe ] && echo > donepipe 2>/dev/null || true
       rm -f donepipe info.json sandbox-userns sandbox2-userns
   }
   trap cleanup EXIT
   ```

3. **统一 ASan 处理**: 与 test-specifying-pidns.sh 保持一致

4. **更精确同步**: 使用文件锁或 socket 替代轮询

5. **调试输出**: 添加 `set -x` 或条件调试输出

6. **并行安全**: 使用随机文件名避免并行测试冲突
   ```bash
   suffix=$$
   donepipe=donepipe.$suffix
   ```

7. **命名空间限制检查**: 测试前检查 `max_user_namespaces`
   ```bash
   if [ -f /proc/sys/user/max_user_namespaces ]; then
       max=$(cat /proc/sys/user/max_user_namespaces)
       [ "$max" -eq 0 ] && skip "user namespaces disabled"
   fi
   ```
