# network.c 研究文档

## 场景与职责

`network.c` 是 Bubblewrap 项目中负责网络命名空间配置的核心模块。当用户使用 `--unshare-net` 选项创建新的网络命名空间时，该模块负责初始化沙箱内的网络环境。

### 核心职责

1. **Loopback 接口配置**：在新的网络命名空间中启用本地回环接口
2. **Netlink 通信**：通过 Linux Netlink 套接字与内核网络子系统交互
3. **IP 地址配置**：为 loopback 接口配置 127.0.0.1/8 地址
4. **接口状态管理**：将 loopback 接口设置为 UP 状态

### 使用场景

```bash
# 创建隔离的网络命名空间
bwrap --unshare-net --proc /proc --dev /dev bash

# 在沙箱中，只有 loopback 可用，无法访问外部网络
ping 8.8.8.8  # 失败：Network is unreachable
ping 127.0.0.1  # 成功
```

## 功能点目的

### 1. Loopback 接口设置（`loopback_setup` 函数）

这是 `network.c` 的核心功能，执行以下操作：

| 步骤 | 操作 | 目的 |
|------|------|------|
| 1 | 查找 `lo` 接口索引 | 确定要配置的目标接口 |
| 2 | 创建 Netlink 套接字 | 建立与内核的通信通道 |
| 3 | 发送 RTM_NEWADDR | 添加 127.0.0.1/8 IP 地址 |
| 4 | 发送 RTM_NEWLINK | 启用接口（设置 IFF_UP） |

### 2. 为什么需要这个模块

当创建新的网络命名空间（`CLONE_NEWNET`）时：
- 新命名空间最初只有 `lo` 接口
- 接口默认处于 DOWN 状态
- 没有配置 IP 地址
- 许多应用程序期望 `localhost` 可用

如果不配置 loopback：
- 绑定到 `127.0.0.1` 的应用程序会失败
- 本地 IPC 机制（如基于 localhost 的 socket）无法工作
- 某些库初始化会失败

## 具体技术实现

### Netlink 协议概述

Netlink 是 Linux 内核与用户空间之间通信的套接字接口，用于网络配置、路由表管理等。

**关键数据结构**：
```c
struct nlmsghdr {
    __u32 nlmsg_len;    // 消息总长度
    __u16 nlmsg_type;   // 消息类型（RTM_NEWADDR, RTM_NEWLINK 等）
    __u16 nlmsg_flags;  // 标志（NLM_F_REQUEST, NLM_F_ACK 等）
    __u32 nlmsg_seq;    // 序列号
    __u32 nlmsg_pid;    // 发送进程 PID
};
```

### 核心函数实现

#### 1. `add_rta` - 添加路由属性（第 32-47 行）

```c
static void *
add_rta (struct nlmsghdr *header,
         int              type,
         size_t           size)
{
  struct rtattr *rta;
  size_t rta_size = RTA_LENGTH (size);

  rta = (struct rtattr *) ((char *) header + NLMSG_ALIGN (header->nlmsg_len));
  rta->rta_type = type;
  rta->rta_len = rta_size;

  header->nlmsg_len = NLMSG_ALIGN (header->nlmsg_len) + rta_size;

  return RTA_DATA (rta);
}
```

**功能**：在 Netlink 消息末尾添加路由属性（如 IP 地址）

#### 2. `rtnl_send_request` - 发送请求（第 49-62 行）

```c
static int
rtnl_send_request (int              rtnl_fd,
                   struct nlmsghdr *header)
{
  struct sockaddr_nl dst_addr = { .nl_family = AF_NETLINK, .nl_pid = 0, .nl_groups = 0 };
  ssize_t sent;

  sent = TEMP_FAILURE_RETRY (sendto (rtnl_fd, (void *) header, header->nlmsg_len, 0,
                                     (struct sockaddr *) &dst_addr, sizeof (dst_addr)));
  if (sent < 0)
    return -1;

  return 0;
}
```

**功能**：通过 Netlink 套接字向内核发送请求

#### 3. `rtnl_read_reply` - 读取响应（第 64-99 行）

```c
static int
rtnl_read_reply (int          rtnl_fd,
                 unsigned int seq_nr)
{
  char buffer[1024];
  // ...
  while (1)
    {
      received = TEMP_FAILURE_RETRY (recv (rtnl_fd, buffer, sizeof (buffer), 0));
      // 验证序列号、PID
      // 处理 NLMSG_ERROR 和 NLMSG_DONE
    }
}
```

**功能**：读取并验证内核响应，确保操作成功

#### 4. `rtnl_do_request` - 完整请求流程（第 101-112 行）

```c
static int
rtnl_do_request (int              rtnl_fd,
                 struct nlmsghdr *header)
{
  if (rtnl_send_request (rtnl_fd, header) != 0)
    return -1;

  if (rtnl_read_reply (rtnl_fd, header->nlmsg_seq) != 0)
    return -1;

  return 0;
}
```

**功能**：发送请求并等待响应的完整流程

#### 5. `rtnl_setup_request` - 请求初始化（第 114-134 行）

```c
static struct nlmsghdr *
rtnl_setup_request (char  *buffer,
                    int    type,
                    int    flags,
                    size_t size)
{
  struct nlmsghdr *header;
  size_t len = NLMSG_LENGTH (size);
  static uint32_t counter = 0;

  memset (buffer, 0, len);

  header = (struct nlmsghdr *) buffer;
  header->nlmsg_len = len;
  header->nlmsg_type = type;
  header->nlmsg_flags = flags | NLM_F_REQUEST;
  header->nlmsg_seq = counter++;
  header->nlmsg_pid = getpid ();

  return header;
}
```

**功能**：初始化 Netlink 消息头，设置序列号

### `loopback_setup` 完整流程（第 136-199 行）

```c
void
loopback_setup (void)
{
  int r, if_loopback;
  cleanup_fd int rtnl_fd = -1;
  char buffer[1024];
  struct sockaddr_nl src_addr = { .nl_family = AF_NETLINK, .nl_pid = 0, .nl_groups = 0 };
  struct nlmsghdr *header;
  struct ifaddrmsg *addmsg;
  struct ifinfomsg *infomsg;
  struct in_addr *ip_addr;

  // 1. 获取 loopback 接口索引
  src_addr.nl_pid = getpid ();
  if_loopback = (int) if_nametoindex ("lo");
  if (if_loopback <= 0)
    die_with_error ("loopback: Failed to look up lo");

  // 2. 创建 Netlink 套接字
  rtnl_fd = socket (PF_NETLINK, SOCK_RAW | SOCK_CLOEXEC, NETLINK_ROUTE);
  if (rtnl_fd < 0)
    die_with_error ("loopback: Failed to create NETLINK_ROUTE socket");

  // 3. 绑定套接字
  r = bind (rtnl_fd, (struct sockaddr *) &src_addr, sizeof (src_addr));
  if (r < 0)
    die_with_error ("loopback: Failed to bind NETLINK_ROUTE socket");

  // 4. 配置 IP 地址（RTM_NEWADDR）
  header = rtnl_setup_request (buffer, RTM_NEWADDR,
                               NLM_F_CREATE | NLM_F_EXCL | NLM_F_ACK,
                               sizeof (struct ifaddrmsg));
  addmsg = NLMSG_DATA (header);

  addmsg->ifa_family = AF_INET;
  addmsg->ifa_prefixlen = 8;        // /8 子网掩码
  addmsg->ifa_flags = IFA_F_PERMANENT;
  addmsg->ifa_scope = RT_SCOPE_HOST;
  addmsg->ifa_index = if_loopback;

  ip_addr = add_rta (header, IFA_LOCAL, sizeof (*ip_addr));
  ip_addr->s_addr = htonl (INADDR_LOOPBACK);  // 127.0.0.1

  ip_addr = add_rta (header, IFA_ADDRESS, sizeof (*ip_addr));
  ip_addr->s_addr = htonl (INADDR_LOOPBACK);

  if (rtnl_do_request (rtnl_fd, header) != 0)
    die_with_error ("loopback: Failed RTM_NEWADDR");

  // 5. 启用接口（RTM_NEWLINK）
  header = rtnl_setup_request (buffer, RTM_NEWLINK,
                               NLM_F_ACK,
                               sizeof (struct ifinfomsg));
  infomsg = NLMSG_DATA (header);

  infomsg->ifi_family = AF_UNSPEC;
  infomsg->ifi_type = 0;
  infomsg->ifi_index = if_loopback;
  infomsg->ifi_flags = IFF_UP;      // 启用接口
  infomsg->ifi_change = IFF_UP;

  if (rtnl_do_request (rtnl_fd, header) != 0)
    die_with_error ("loopback: Failed RTM_NEWLINK");
}
```

## 关键代码路径与文件引用

### 调用关系

```
bubblewrap.c:main()
    ↓ 如果 opt_unshare_net 为 true
bubblewrap.c:clone() 创建新网络命名空间
    ↓ 子进程中
bubblewrap.c: 第 3277-3278 行
    loopback_setup()  [network.c]
        ├── if_nametoindex("lo")
        ├── socket(PF_NETLINK, ...)
        ├── bind()
        ├── rtnl_do_request(RTM_NEWADDR)  // 配置 IP
        └── rtnl_do_request(RTM_NEWLINK)  // 启用接口
```

### 相关文件

| 文件 | 关系 | 说明 |
|------|------|------|
| `network.h` | 头文件 | 声明 `loopback_setup()` 函数 |
| `bubblewrap.c` | 调用方 | 在适当时候调用 `loopback_setup()` |
| `utils.h` | 依赖 | 提供 `die_with_error`, `cleanup_fd` 等工具 |

### 代码中的关键位置

**调用点**（`bubblewrap.c` 第 3277-3278 行）：
```c
if (opt_unshare_net)
  loopback_setup (); /* Will exit if unsuccessful */
```

**头文件**（`network.h`）：
```c
#pragma once
void loopback_setup (void);
```

## 依赖与外部交互

### 系统调用

| 调用 | 用途 |
|------|------|
| `if_nametoindex()` | 将接口名转换为内核索引 |
| `socket(PF_NETLINK, ...)` | 创建 Netlink 套接字 |
| `bind()` | 绑定套接字地址 |
| `sendto()` | 发送 Netlink 消息 |
| `recv()` | 接收内核响应 |

### 内核接口

**Netlink 协议族**：
- `NETLINK_ROUTE`：网络路由和接口配置

**消息类型**：
- `RTM_NEWADDR`：添加 IP 地址
- `RTM_NEWLINK`：配置网络接口

**标志**：
- `NLM_F_REQUEST`：请求消息
- `NLM_F_CREATE`：如果不存在则创建
- `NLM_F_EXCL`：如果已存在则失败
- `NLM_F_ACK`：要求确认响应

### 头文件依赖

```c
#include <arpa/inet.h>      // htonl, INADDR_LOOPBACK
#include <net/if.h>         // if_nametoindex, IFF_UP
#include <netinet/in.h>     // AF_INET
#include <linux/netlink.h>  // Netlink 核心定义
#include <linux/rtnetlink.h> // 路由 Netlink 定义
```

## 风险、边界与改进建议

### 风险

1. **Netlink 通信失败**：
   - 风险：内核不支持或资源不足
   - 缓解：使用 `die_with_error` 提供清晰错误信息
   - 位置：第 152, 156, 160, 182, 198 行

2. **接口索引查找失败**：
   - 风险：某些系统可能使用非标准 loopback 名称
   - 缓解：硬编码 `"lo"` 是 Linux 标准

3. **竞态条件**：
   - 风险：多线程环境下序列号可能冲突
   - 缓解：使用静态计数器，但 Bubblewrap 是单线程的

4. **缓冲区溢出**：
   - 风险：1024 字节缓冲区可能不足
   - 缓解：实际使用远小于此，且有断言检查

### 边界

1. **仅支持 IPv4**：
   - 当前只配置 `AF_INET`（IPv4）
   - 未配置 IPv6 loopback（::1）
   - 改进建议：添加 IPv6 支持

2. **仅支持 loopback**：
   - 不配置其他网络接口
   - 不设置路由表
   - 这是设计决策（最小权限原则）

3. **同步阻塞**：
   - 使用阻塞 I/O
   - 无超时机制
   - 在内核正常时不是问题

### 改进建议

1. **添加 IPv6 支持**：
   ```c
   // 添加 IPv6 loopback 配置
   addmsg->ifa_family = AF_INET6;
   // 配置 ::1/128
   ```

2. **错误恢复**：
   ```c
   // 当前失败时直接退出
   // 可考虑重试机制
   for (int retry = 0; retry < 3; retry++) {
       if (rtnl_do_request(rtnl_fd, header) == 0)
           break;
       usleep(1000);
   }
   ```

3. **日志增强**：
   ```c
   // 添加调试日志
   debug("Configuring loopback interface: index=%d", if_loopback);
   ```

4. **功能检测**：
   ```c
   // 检查内核是否支持所需功能
   if (access("/proc/sys/net/ipv6", F_OK) == 0) {
       // 配置 IPv6
   }
   ```

5. **单元测试**：
   - 添加模拟 Netlink 响应的测试
   - 测试错误处理路径
   - 验证内存管理（valgrind）
