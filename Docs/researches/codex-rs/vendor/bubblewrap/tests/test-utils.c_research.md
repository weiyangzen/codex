# test-utils.c 研究文档

## 场景与职责

`test-utils.c` 是 bubblewrap 工具函数的单元测试程序，使用 TAP（Test Anything Protocol）格式输出测试结果。它测试 `utils.c` 中实现的基础工具函数，确保这些底层功能的正确性。这些工具函数是 bwrap 核心功能的基础，包括字符串操作、路径处理、内存管理等。

该测试程序是编译型测试（非脚本），直接链接被测试的代码。

## 功能点目的

### 1. TAP 测试框架实现
由于避免依赖外部库（如 GLib），测试程序内嵌了一个简化的 TAP 实现：
- **ok()**: 输出测试通过，带格式化消息
- **not_ok()**: 测试失败，调用 die() 终止
- **g_test_message()**: 输出诊断信息
- **g_assert_* 宏**: GLib 风格的断言宏

### 2. 测试用例

#### test_n_elements
- **目标**: 测试 `N_ELEMENTS` 宏
- **验证**: 数组元素个数计算正确
- **代码**:
  ```c
  int three[] = { 1, 2, 3 };
  g_assert_cmpuint (N_ELEMENTS (three), ==, 3);
  ```

#### test_strconcat
- **目标**: 测试 `strconcat()` 函数
- **功能**: 连接两个字符串
- **验证**: "aaa" + "bbb" = "aaabbb"

#### test_strconcat3
- **目标**: 测试 `strconcat3()` 函数
- **功能**: 连接三个字符串
- **验证**: "aaa" + "bbb" + "ccc" = "aaabbbccc"

#### test_has_prefix
- **目标**: 测试 `has_prefix()` 函数
- **功能**: 检查字符串前缀
- **测试用例**:
  - "foo" 以 "foo" 开头（true）
  - "foobar" 以 "foo" 开头（true）
  - "foobar" 不以 "fool" 开头（false）
  - 空字符串以 "" 开头（true）
  - "" 不以 "no" 开头（false）

#### test_has_path_prefix
- **目标**: 测试 `has_path_prefix()` 函数
- **功能**: 检查路径前缀（处理多重斜杠）
- **关键特性**:
  - 处理多重斜杠: `////run///host` 匹配 `//run//host`
  - 路径元素边界: `/run/host` 匹配 `/run/host/usr` 但不匹配 `/run/hostage`
  - 前导斜杠可选: `foo/bar` 匹配 `/foo`
- **测试数据**:
  ```c
  { "/run/host/usr", "/run/host", true },
  { "/run/hostage", "/run/host", false },
  { "foo/bar", "/foo", true },
  ```

#### test_string_builder
- **目标**: 测试 `StringBuilder` 及相关函数
- **测试函数**:
  - `strappend()`: 追加字符串
  - `strappendf()`: 格式化追加
  - `strappend_escape_for_mount_options()`: 转义追加（用于 mount 选项）
- **验证点**:
  - 基本追加功能
  - 格式化字符串处理
  - 特殊字符转义（`\`, `,`, `:` 前加 `\`）
  - 长字符串处理

## 具体技术实现

### 关键流程

1. **TAP 输出实现**:
   ```c
   static unsigned int test_number = 0;
   
   static void ok (const char *format, ...)
   {
       printf ("ok %u - ", ++test_number);
       // ... 格式化输出
       printf ("\n");
   }
   ```

2. **断言宏实现**:
   ```c
   #define g_assert_cmpstr(left_expr, op, right_expr) \
     do { \
       const char *left = (left_expr); \
       const char *right = (right_expr); \
       if (strcmp0 (left, right) op 0) \
         ok ("%s (\"%s\") %s %s (\"%s\")", #left_expr, left, #op, #right_expr, right); \
       else \
         not_ok ("expected %s (\"%s\") %s %s (\"%s\")", ...); \
     } while (0)
   ```

3. **NULL 安全字符串比较**:
   ```c
   static int strcmp0 (const char *left, const char *right)
   {
       if (left == right) return 0;
       if (left == NULL) return -1;
       if (right == NULL) return 1;
       return strcmp (left, right);
   }
   ```

4. **路径前缀测试循环**:
   ```c
   static const struct { const char *str; const char *prefix; bool expected; } tests[] = { ... };
   for (i = 0; i < N_ELEMENTS (tests); i++) {
       // 执行测试并验证
   }
   ```

5. **StringBuilder 测试**:
   ```c
   StringBuilder sb = {0};  // C99 指定初始化
   strappend (&sb, "aaa");
   g_assert_cmpstr (sb.str, ==, "aaa");
   // ... 更多操作
   free (sb.str);
   ```

### 数据结构

| 类型/变量 | 说明 |
|-----------|------|
| `test_number` | TAP 测试计数器 |
| `StringBuilder` | 来自 utils.h 的动态字符串构建器 |
| `tests[]` | has_path_prefix 测试用例数组 |

### 关键代码路径

| 代码 | 行号 | 说明 |
|------|------|------|
| TAP 框架 | 27-104 | 测试基础设施 |
| strcmp0 | 106-120 | NULL 安全比较 |
| test_n_elements | 122-127 | N_ELEMENTS 宏测试 |
| test_strconcat | 129-137 | 两字符串连接测试 |
| test_strconcat3 | 139-148 | 三字符串连接测试 |
| test_has_prefix | 150-161 | 前缀检查测试 |
| test_has_path_prefix | 163-201 | 路径前缀测试 |
| test_string_builder | 203-232 | StringBuilder 测试 |
| main | 234-247 | 测试执行入口 |

## 依赖与外部交互

### 头文件依赖
| 头文件 | 用途 |
|--------|------|
| `<stdarg.h>` | 可变参数 |
| `<stdint.h>` | 固定宽度整数 |
| `<stdio.h>` | 标准 IO |
| `"utils.h"` | 被测试的函数声明 |

### 被测试的函数（来自 utils.c）
| 函数 | 说明 |
|------|------|
| `N_ELEMENTS` | 数组元素个数宏 |
| `strconcat()` | 两字符串连接 |
| `strconcat3()` | 三字符串连接 |
| `has_prefix()` | 字符串前缀检查 |
| `has_path_prefix()` | 路径前缀检查 |
| `strappend()` | StringBuilder 追加 |
| `strappendf()` | StringBuilder 格式化追加 |
| `strappend_escape_for_mount_options()` | 转义追加 |

### 构建依赖
- `../utils.c` 和 `../utils.h`: 被测试的源代码
- `selinux_dep`: SELinux 支持（通过 meson.build）
- `common_include_directories`: 头文件搜索路径

### 调用关系
- **调用**: utils.c 中的工具函数
- **被调用**: Meson 测试框架直接执行

## 风险、边界与改进建议

### 风险点
1. **内存泄漏**: 测试分配的内存在成功路径未完全释放（虽然进程结束会回收）
2. **有限覆盖**: 仅测试了部分工具函数，大量函数未覆盖
3. **无错误路径测试**: 未测试内存分配失败等错误路径

### 边界情况
1. **NULL 指针**: strcmp0 处理 NULL，但其他函数未测试
2. **空字符串**: has_prefix 和 has_path_prefix 测试了空字符串
3. **长字符串**: StringBuilder 测试了 66 字符的字符串
4. **特殊字符**: 测试了 mount 选项转义

### 未覆盖的功能
以下 utils.c 中的功能未被测试：
- 内存管理: `xmalloc`, `xcalloc`, `xrealloc`, `xstrdup`
- 环境变量: `xclearenv`, `xsetenv`, `xunsetenv`
- 文件操作: `load_file_data`, `write_file_at`, `copy_file`
- 目录操作: `mkdir_with_parents`, `ensure_dir`
- 进程通信: `send_pid_on_socket`, `read_pid_from_socket`
- 系统调用包装: `raw_clone`, `pivot_root`
- SELinux: `label_mount`, `label_exec`

### 改进建议
1. **扩展覆盖**: 添加未测试函数的测试用例
2. **错误路径**: 使用 mock 或注入测试错误处理
3. **内存检查**: 集成 valgrind 或 ASan 检测泄漏
4. **边界测试**: 添加空指针、超长字符串、特殊字符测试
5. **性能测试**: 对频繁使用的函数（如 has_path_prefix）进行基准测试
6. **模糊测试**: 对路径处理函数进行模糊测试
7. **测试分组**: 按功能分组，使用 TAP 子测试（TAP 13+）
8. **覆盖率报告**: 集成 gcov 生成覆盖率报告
