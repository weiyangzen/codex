# network.h 研究文档

## 场景与职责

`network.h` 是 Bubblewrap 项目中网络相关功能的头文件，定义了网络模块的公共接口。作为 `network.c` 的配套头文件，它遵循 C 语言模块化编程的最佳实践，将接口声明与实现分离。

### 核心职责

1. **接口声明**：声明 `loopback_setup()` 函数，供其他模块调用
2. **防止重复包含**：使用 `#pragma once` 确保头文件只被包含一次
3. **模块边界定义**：明确网络模块对外暴露的功能范围

## 功能点目的

### 1. 函数声明

```c
void loopback_setup (void);
```

**功能**：在新的网络命名空间中配置 loopback 接口

**调用约定**：
- 返回类型：`void`（失败时通过 `die_with_error` 退出）
- 参数：无（使用全局状态）
- 副作用：配置网络接口，可能退出进程

### 2. 头文件保护

```c
#pragma once
```

**作用**：防止头文件被多次包含导致的重复定义错误

**替代方案**（传统方式）：
```c
#ifndef NETWORK_H
#define NETWORK_H
// ... 内容
#endif
```

`#pragma once` 更简洁，且被所有主流编译器支持。

## 具体技术实现

### 文件结构

```c
/* bubblewrap
 * Copyright (C) 2016 Alexander Larsson
 * SPDX-License-Identifier: LGPL-2.0-or-later
 *
 * ... 许可证声明 ...
 */

#pragma once

void loopback_setup (void);
```

### 设计决策

#### 1. 最小化接口

仅暴露一个函数，符合**最小权限原则**：
- 调用方无需了解 Netlink 协议细节
- 内部实现细节完全隐藏
- 降低模块间耦合

#### 2. 无状态设计

函数不接受参数，不返回错误码：
- 简化调用方代码
- 失败时直接退出（符合 Bubblewrap 整体错误处理策略）
- 依赖全局状态（如 `real_uid` 等）

#### 3. 无类型定义

头文件中不定义结构体或类型：
- 所有数据结构都是实现细节
- 避免暴露 `struct nlmsghdr` 等内核类型
- 保持接口简洁

## 关键代码路径与文件引用

### 包含关系

```
network.h
    ↑ 被包含
network.c  -------->  实现 loopback_setup()
    
bubblewrap.c  ----->  调用 loopback_setup()
    ↑
main() 中检查 opt_unshare_net 后调用
```

### 引用文件

| 文件 | 关系 | 说明 |
|------|------|------|
| `network.c` | 实现文件 | 包含此头文件并提供实现 |
| `bubblewrap.c` | 调用方 | 包含此头文件并调用函数 |

### 代码中的使用

**network.c**（第 30 行）：
```c
#include "network.h"
```

**bubblewrap.c**（第 40 行）：
```c
#include "network.h"
```

**调用点**（bubblewrap.c 第 3277-3278 行）：
```c
if (opt_unshare_net)
  loopback_setup (); /* Will exit if unsuccessful */
```

## 依赖与外部交互

### 内部依赖

此头文件本身不依赖其他头文件，是**叶子节点**头文件。

### 外部依赖

调用方需要包含此头文件才能使用网络功能。

### 编译依赖

```
network.h
    ↓ 被 network.c 包含
    ↓ 被 bubblewrap.c 包含
    
编译时：
    gcc -c network.c     # 需要 network.h
    gcc -c bubblewrap.c  # 需要 network.h
```

## 风险、边界与改进建议

### 风险

1. **接口变更风险**：
   - 风险：修改函数签名需要更新所有调用方
   - 当前：函数简单，变更可能性低
   - 缓解：保持接口稳定

2. **命名冲突**：
   - 风险：`loopback_setup` 是通用名称，可能与其他库冲突
   - 缓解：使用静态链接，或添加前缀如 `bwrap_`

3. **文档不足**：
   - 风险：头文件缺少函数文档注释
   - 缓解：依赖代码审查和外部文档

### 边界

1. **单一功能**：
   - 仅支持 loopback 配置
   - 不支持通用网络接口配置
   - 这是设计决策，不是限制

2. **无配置选项**：
   - 无法自定义 IP 地址
   - 无法选择启用/禁用 IPv6
   - 硬编码 127.0.0.1

3. **Linux 特定**：
   - 依赖 Linux Netlink 协议
   - 不可移植到其他操作系统

### 改进建议

1. **添加文档注释**：
   ```c
   #pragma once

   /**
    * loopback_setup:
    *
    * Configures the loopback interface (lo) in a new network namespace.
    * Sets the interface UP and assigns 127.0.0.1/8.
    *
    * This function must be called after unsharing into a new network namespace.
    * On failure, it prints an error message and exits.
    *
    * Since: 0.1.0
    */
   void loopback_setup (void);
   ```

2. **添加版本信息**：
   ```c
   #define BWRAP_NETWORK_VERSION_MAJOR 0
   #define BWRAP_NETWORK_VERSION_MINOR 1
   #define BWRAP_NETWORK_VERSION_PATCH 0
   ```

3. **考虑扩展接口**（如果需要更多网络功能）：
   ```c
   // 可选的扩展接口
   typedef enum {
       BWRAP_LOOPBACK_IPV4 = 1 << 0,
       BWRAP_LOOPBACK_IPV6 = 1 << 1,
   } BwrapLoopbackFlags;

   void loopback_setup_ex (BwrapLoopbackFlags flags);
   ```

4. **添加前缀避免命名冲突**：
   ```c
   void bwrap_loopback_setup (void);
   ```

5. **条件编译支持**（如果未来支持多种平台）：
   ```c
   #pragma once

   #ifdef HAVE_NETLINK
   void loopback_setup (void);
   #endif
   ```

### 代码风格一致性

当前代码遵循项目风格：
- 函数名使用小写加下划线
- 返回类型和函数名分行
- 无参数时使用 `(void)` 而非 `()`

建议保持此风格以维护代码一致性。
