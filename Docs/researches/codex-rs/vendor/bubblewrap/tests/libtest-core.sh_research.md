# libtest-core.sh 研究文档

## 场景与职责

`libtest-core.sh` 是 bubblewrap 测试框架的核心基础库，源自 ostree 项目的通用测试基础设施。该文件被设计为跨项目共享的基础测试库，在 bubblewrap 项目中作为 `libtest.sh` 的底层依赖。它提供了 shell 测试所需的基础断言、错误处理和本地化支持，确保测试脚本的一致性和可移植性。

## 功能点目的

### 1. 错误处理与测试控制
- **fatal()**: 统一的错误输出和退出机制，将错误信息输出到 stderr 并终止测试
- **assert_not_reached()**: 标记不可达代码路径，用于测试失败分支
- **skip()**: 支持 TAP 协议的测试跳过机制，输出 `1..0 # SKIP` 格式

### 2. 本地化环境设置
- 自动检测并设置 UTF-8 语言环境（优先 C.UTF-8，其次 en_US.UTF-8）
- 设置 `G_DEBUG=fatal-warnings` 确保 GLib 警告被视为致命错误
- 处理 musl 系统（无 locale 命令）的兼容情况

### 3. 字符串断言
- **assert_streq()**: 字符串相等断言
- **assert_not_streq()**: 字符串不等断言
- **assert_str_match()**: 正则表达式匹配断言

### 4. 文件系统断言
- **assert_has_file() / assert_not_has_file()**: 文件存在性检查
- **assert_has_dir() / assert_not_has_dir()**: 目录存在性检查
- **assert_file_has_content()**: 文件内容正则匹配
- **assert_file_has_content_literal()**: 文件内容字面量匹配
- **assert_file_has_content_once()**: 内容唯一出现断言
- **assert_not_file_has_content()**: 内容不应存在断言
- **assert_file_has_mode()**: 文件权限模式检查
- **assert_symlink_has_content()**: 符号链接目标检查
- **assert_file_empty()**: 空文件断言
- **assert_files_equal()**: 文件内容比较

### 5. 错误报告增强
- **_fatal_print_file()**: 失败时输出文件详细信息和内容
- **_fatal_print_files()**: 双文件对比失败时的详细输出
- **report_err()**: 捕获并报告非预期退出状态

## 具体技术实现

### 关键流程

1. **本地化检测流程**:
   ```bash
   if type -p locale >/dev/null; then
       export LC_ALL=$(locale -a | grep -iEe '^(C|en_US)\.(UTF-8|utf8)$' | head -n1)
   else
       export LC_ALL=C.UTF-8  # musl 系统回退
   fi
   ```

2. **错误陷阱设置**:
   ```bash
   trap report_err ERR
   ```
   使用 bash 的 ERR 陷阱捕获非预期错误

3. **TAP 协议支持**:
   ```bash
   skip() {
       echo "1..0 # SKIP" "$@"
       exit 0
   }
   ```

### 数据结构

- 无复杂数据结构，主要使用 shell 字符串和位置参数
- 依赖外部传入的文件路径参数

### 关键代码路径

| 函数 | 行号 | 功能 |
|------|------|------|
| `fatal` | 30-32 | 核心错误处理 |
| `assert_streq` | 56-58 | 字符串相等断言 |
| `assert_file_has_content` | 121-129 | 文件内容匹配 |
| `_fatal_print_file` | 79-85 | 详细错误输出 |
| `skip` | 179-182 | 测试跳过 |
| `report_err` | 184-189 | ERR 陷阱处理 |

## 依赖与外部交互

### 外部命令依赖
- `locale`: 语言环境检测
- `grep`: 正则匹配
- `stat`: 文件权限检查
- `sed`: 内容输出格式化
- `cmp`: 文件比较
- `readlink`: 符号链接读取
- `test`: 基础条件检查

### 上游项目
- 源自: https://github.com/ostreedev/ostree
- 其他使用项目:
  - https://github.com/containers/bubblewrap
  - https://github.com/coreos/rpm-ostree

### 被调用关系
- 被 `libtest.sh` source 引入（第38行）
- 不直接调用 bubblewrap 二进制

## 风险、边界与改进建议

### 风险点
1. **locale 依赖**: 在最小化容器中可能缺少 locale 数据，导致测试失败
2. **UTF-8 假设**: 强制 UTF-8 可能在某些嵌入式环境不适用
3. **Bash 特性依赖**: 使用 `trap ERR` 等 bash 特性，非 POSIX sh 兼容

### 边界情况
1. **大文件处理**: `_fatal_print_file` 会完整输出文件内容，大文件可能导致日志爆炸
2. **特殊字符**: 文件内容包含控制字符时，sed 替换可能产生意外输出
3. **并发安全**: 使用全局变量，不适合并发测试场景

### 改进建议
1. **添加文件大小限制**: `_fatal_print_file` 应限制输出文件的最大字节数
2. **支持非 UTF-8 环境**: 添加 `BWRAP_TEST_LOCALE` 环境变量覆盖
3. **日志级别控制**: 添加 `BWRAP_TEST_VERBOSE` 控制详细输出
4. **性能优化**: 频繁调用的断言（如循环内）可考虑批量检查模式
