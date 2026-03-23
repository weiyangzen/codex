# libtest.sh 研究文档

## 场景与职责

`libtest.sh` 是 bubblewrap 项目的专用测试库，在 `libtest-core.sh` 基础上提供 bubblewrap 特定的测试基础设施。它负责：
- 设置测试环境（源目录、构建目录、临时目录）
- 检测 bwrap 二进制位置和运行模式（setuid vs 非 setuid）
- 配置测试所需的挂载参数和命名空间选项
- 提供测试清理和错误处理

该文件是所有 bubblewrap shell 测试脚本的入口点。

## 功能点目的

### 1. 测试环境初始化
- **目录设置**: 通过 `G_TEST_SRCDIR` 和 `G_TEST_BUILDDIR` 环境变量或脚本位置确定源目录和构建目录
- **临时目录管理**: 创建 `/var/tmp/tap-test.XXXXXX` 临时目录，设置清理陷阱
- **PATH 扩展**: 添加 `/usr/sbin` 和 `/sbin` 确保非 root 用户能找到 `getpcaps` 等工具

### 2. bwrap 运行模式检测
- **setuid 检测**: 检查 bwrap 是否设置了 setuid 位 (`test -u`)
- **功能降级**: setuid 模式下禁用某些需要用户命名空间的功能
- **基础命令构建**: 定义 `${BWRAP}` 变量，默认值为 `bwrap`

### 3. FUSE 支持检测
- **自动发现**: 扫描 `/proc/self/mounts` 查找当前用户的 FUSE 挂载点
- **测试用途**: 用于测试 FUSE 目录的 bind mount 功能

### 4. 权限检测
- **root 检测**: 通过 `id -u` 判断当前是否以 root 运行
- **不可读文件测试**: 尝试使用 `/root/.bashrc` 作为权限测试目标（仅非 root 时）

### 5. 挂载参数配置
- **merged-/usr 检测**: 检测系统是否使用 merged /usr 布局（/lib 指向 /usr/lib）
- **BWRAP_RO_HOST_ARGS**: 构建只读主机文件系统挂载参数
  - merged-/usr 系统: 使用符号链接绑定
  - 传统系统: 直接绑定 /bin, /lib, /lib64 等

### 6. 基础运行命令
- **RUN 变量**: 定义基础 bwrap 命令，绑定整个主机文件系统并在 /tmp 挂载 tmpfs
- **功能检查**: 验证 bwrap 是否基本可用，否则跳过测试

### 7. 辅助函数
- **extract_child_pid()**: 从 info.json 输出中提取子进程 PID

## 具体技术实现

### 关键流程

1. **目录初始化**:
   ```bash
   if [ -n "${G_TEST_SRCDIR:-}" ]; then
     test_srcdir="${G_TEST_SRCDIR}/tests"
   else
     test_srcdir=$(dirname "$0")
   fi
   ```

2. **setuid 检测**:
   ```bash
   : "${BWRAP:=bwrap}"
   if test -u "$(type -p ${BWRAP})"; then
       bwrap_is_suid=true
   fi
   ```

3. **FUSE 挂载点发现**:
   ```bash
   FUSE_DIR=
   for mp in $(grep " fuse[. ]" /proc/self/mounts | grep "user_id=$(id -u)" | awk '{print $2}'); do
       if test -d "$mp"; then
           FUSE_DIR="$mp"
           break
       fi
   done
   ```

4. **merged-/usr 检测**:
   ```bash
   if [ /lib -ef /usr/lib ]; then
       BWRAP_RO_HOST_ARGS="--ro-bind /usr /usr ..."
   else
       BWRAP_RO_HOST_ARGS="--ro-bind /bin /bin ..."
   fi
   ```

5. **临时目录清理**:
   ```bash
   cleanup() {
       if test -n "${TEST_SKIP_CLEANUP:-}"; then
           echo "Skipping cleanup of ${tempdir}"
       elif test -f "${tempdir}/.testtmp"; then
           rm -rf "${tempdir}"
       fi
   }
   trap cleanup EXIT
   ```

### 数据结构

| 变量 | 类型 | 用途 |
|------|------|------|
| `test_srcdir` | string | 测试源文件目录 |
| `test_builddir` | string | 测试构建目录 |
| `tempdir` | string | 临时测试目录 |
| `BWRAP` | string | bwrap 可执行文件路径 |
| `bwrap_is_suid` | bool | setuid 模式标记 |
| `FUSE_DIR` | string | FUSE 挂载点路径 |
| `is_uidzero` | bool | root 用户标记 |
| `UNREADABLE` | string | 不可读文件测试路径 |
| `BWRAP_RO_HOST_ARGS` | string | 只读主机挂载参数 |
| `RUN` | string | 基础 bwrap 运行命令 |

### 关键代码路径

| 代码 | 行号 | 说明 |
|------|------|------|
| 目录设置 | 26-37 | 源/构建目录初始化 |
| 核心库加载 | 38 | source libtest-core.sh |
| setuid 检测 | 55-58 | bwrap 运行模式判断 |
| FUSE 检测 | 60-67 | FUSE 挂载点扫描 |
| 权限检测 | 69-79 | root 和不可读文件检测 |
| merged-/usr | 83-104 | 系统布局检测和参数配置 |
| 基础命令 | 107 | RUN 变量定义 |
| 功能检查 | 109-111 | bwrap 可用性验证 |
| PID 提取 | 113-115 | info-fd 输出解析 |

## 依赖与外部交互

### 外部命令依赖
- `type -p`: 查找命令路径
- `mktemp`: 创建临时目录
- `id`: 获取用户 ID
- `grep/awk`: 文本处理
- `readlink -f`: 解析符号链接
- `stat`: 文件状态检查
- `test`: 条件测试

### 文件系统依赖
- `/proc/self/mounts`: FUSE 检测
- `/var/tmp`: 临时目录创建位置
- `/usr/sbin`, `/sbin`: 扩展 PATH

### 环境变量
| 变量 | 说明 |
|------|------|
| `G_TEST_SRCDIR` | GLib 测试源目录 |
| `G_TEST_BUILDDIR` | GLib 测试构建目录 |
| `BWRAP` | bwrap 可执行文件覆盖 |
| `TEST_SKIP_CLEANUP` | 跳过清理（调试） |
| `BWRAP_MUST_WORK` | 强制要求 bwrap 工作 |

### 调用关系
- **source**: `libtest-core.sh`（第38行）
- **被调用**: `test-run.sh`, `test-specifying-pidns.sh`, `test-specifying-userns.sh`

## 风险、边界与改进建议

### 风险点
1. **硬编码路径**: `/var/tmp` 可能在某些系统不存在或不可写
2. **FUSE 检测竞争**: 挂载点可能在检测和使用之间发生变化
3. **setuid 假设**: 依赖文件权限位，可能被 ACL 或其他安全机制绕过
4. **merged-/usr 检测**: 使用 `-ef` 测试，依赖 /proc 挂载

### 边界情况
1. **无 FUSE 环境**: `FUSE_DIR` 为空，相关测试被跳过
2. **root 用户**: `UNREADABLE` 被清空，相关测试被跳过
3. **bwrap 不可用**: 默认跳过测试，除非 `BWRAP_MUST_WORK` 设置
4. **清理失败**: `.testtmp` 标记文件用于检测有效临时目录

### 改进建议
1. **可配置临时目录**: 支持 `TMPDIR` 环境变量
2. **FUSE 检测改进**: 使用 `/proc/filesystems` 检查内核支持
3. **并行测试支持**: 添加测试实例隔离（当前临时目录命名可能冲突）
4. **日志增强**: 添加 `BWRAP_TEST_DEBUG` 输出详细配置信息
5. **容器检测**: 添加对容器环境的检测和适配
6. **bwrap 版本检查**: 添加 `--version` 检查确保功能兼容
