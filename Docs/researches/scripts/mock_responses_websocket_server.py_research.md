# mock_responses_websocket_server.py 深度研究文档

## 场景与职责

`mock_responses_websocket_server.py` 是一个用于本地开发和测试的 WebSocket 服务器模拟器，模拟 OpenAI Responses API 的 WebSocket 接口行为。该脚本主要服务于以下场景：

1. **本地开发测试**：无需连接真实 OpenAI API 即可测试 Codex CLI
2. **集成测试支持**：为自动化测试提供可控的 API 响应
3. **离线开发**：在没有网络或 API 密钥的环境中进行开发
4. **响应行为调试**：精确控制 API 响应序列，调试复杂交互场景

### 与测试框架的关系

该脚本模拟的行为与 `codex-rs/core/tests/suite/agent_websocket.rs` 中的测试用例对应：

```rust
// agent_websocket.rs 中的测试用例
let server = start_websocket_server(vec![vec![
    vec![
        ev_response_created("resp-1"),
        ev_shell_command_call(call_id, "echo websocket"),
        ev_completed("resp-1"),
    ],
    vec![
        ev_response_created("resp-2"),
        ev_assistant_message("msg-1", "done"),
        ev_completed("resp-2"),
    ],
]]).await;
```

Python 脚本实现了类似的响应序列，用于手动测试和调试。

## 功能点目的

### 1. WebSocket 服务器模拟
- **目的**：提供本地 WebSocket 端点，模拟 OpenAI Responses API
- **默认配置**：
  - 主机：`127.0.0.1`
  - 默认端口：`8765`
  - 路径：`/v1/responses`

### 2. 响应事件序列模拟
- **目的**：模拟真实的 API 响应流程
- **事件类型**：
  - `response.created` - 响应创建
  - `response.output_item.done` - 输出项完成（函数调用或消息）
  - `response.done` - 响应完成
  - `response.completed` - 响应结束

### 3. 两阶段交互模式
模拟典型的 Codex 交互流程：

**第一阶段**：触发函数调用
```
接收 request
├── 发送 response.created
├── 发送 function_call 事件（shell_command）
└── 发送 response.done
```

**第二阶段**：处理工具输出并返回结果
```
接收 request（包含工具输出）
├── 发送 response.created
├── 发送 assistant 消息（"done"）
└── 发送 response.completed
```

### 4. 请求日志记录
- **目的**：记录所有接收到的请求，便于调试
- **输出格式**：带时间戳的 JSON，格式化打印

## 具体技术实现

### 核心数据结构

```python
# 事件构建函数
def _event_response_created(response_id: str) -> dict[str, Any]:
    return {"type": "response.created", "response": {"id": response_id}}

def _event_function_call(call_id: str, name: str, arguments_json: str) -> dict[str, Any]:
    return {
        "type": "response.output_item.done",
        "item": {
            "type": "function_call",
            "call_id": call_id,
            "name": name,
            "arguments": arguments_json,
        },
    }

def _event_assistant_message(message_id: str, text: str) -> dict[str, Any]:
    return {
        "type": "response.output_item.done",
        "item": {
            "type": "message",
            "role": "assistant",
            "id": message_id,
            "content": [{"type": "output_text", "text": text}],
        },
    }
```

### 关键流程

```
启动服务器
├── 绑定到 ws://HOST:PORT
├── 打印配置信息（供用户复制到 config.toml）
└── 等待连接

处理连接
├── 验证请求路径
├── 阶段 1：
│   ├── 接收 JSON 请求（req1）
│   ├── 发送 response.created
│   ├── 发送 function_call 事件
│   └── 发送 response.done
├── 阶段 2：
│   ├── 接收 JSON 请求（req2，应包含工具输出）
│   ├── 发送 response.created
│   ├── 发送 assistant 消息
│   └── 发送 response.completed
└── 关闭连接
```

### 路径验证

```python
path = getattr(getattr(websocket, "request", None), "path", None)
path_no_qs = path.split("?", 1)[0] if path != "(unknown)" else path

if path_no_qs != "(unknown)" and path_no_qs != expected_path:
    await websocket.close(code=1008, reason="unexpected websocket path")
    return
```

### 配置输出

脚本启动后会输出可直接使用的 `config.toml` 配置：

```toml
[model_providers.localapi_ws]
base_url = "ws://127.0.0.1:8765/v1"
name = "localapi_ws"
wire_api = "responses_websocket"
env_key = "OPENAI_API_KEY_STAGING"

[profiles.localapi_ws]
model = "gpt-5.2"
model_provider = "localapi_ws"
model_reasoning_effort = "medium"
```

## 关键代码路径与文件引用

### 脚本本身
- **路径**：`scripts/mock_responses_websocket_server.py` (195 行)
- **Shebang**：`#!/usr/bin/env python3`

### 依赖库
- **websockets**：WebSocket 服务器实现

### 相关测试文件
- `codex-rs/core/tests/suite/agent_websocket.rs` - 对应的 Rust 集成测试
- 测试中使用 `core_test_support::responses::start_websocket_server` 启动模拟服务器

### 配置关联
- `config.toml` - Codex CLI 的配置文件，可配置使用此模拟服务器

## 依赖与外部交互

### Python 依赖
| 包 | 用途 | 安装 |
|----|------|------|
| `websockets` | WebSocket 服务器 | `pip install websockets` |

### 标准库
| 模块 | 用途 |
|------|------|
| `asyncio` | 异步事件循环 |
| `datetime` | ISO 格式时间戳 |
| `json` | JSON 序列化/反序列化 |
| `argparse` | 命令行参数解析 |

### 网络协议
- **WebSocket**：基于 TCP 的全双工通信
- **子协议**：无特定子协议要求
- **路径**：`/v1/responses`

### 与 Codex CLI 的交互

```
Codex CLI                    Mock Server
    |                             |
    |---- WebSocket handshake ---->|
    |                             |
    |---- response.create -------->|
    |                             |
    |<--- response.created --------|
    |<--- function_call event -----|
    |<--- response.done -----------|
    |                             |
    |---- response.create -------->|
    |    (with tool output)       |
    |                             |
    |<--- response.created --------|
    |<--- assistant message ------|
    |<--- response.completed ------|
    |                             |
    |---- close / disconnect ----->|
```

## 风险、边界与改进建议

### 已知风险

1. **固定响应序列**
   - 风险：脚本实现固定的两阶段响应，不支持灵活配置
   - 限制：无法测试多轮对话或错误场景

2. **无状态设计**
   - 风险：不维护会话状态，每个连接独立
   - 影响：无法测试依赖历史上下文的场景

3. **端口冲突**
   - 风险：默认端口 8765 可能被占用
   - 缓解：支持 `--port 0` 自动选择可用端口

4. **并发限制**
   - 风险：单线程处理，不支持真正的并发连接
   - 场景：多个客户端同时连接会串行处理

### 边界情况

1. **路径不匹配**
   - 行为：返回 WebSocket 关闭码 1008（Policy Violation）
   - 处理：立即关闭连接

2. **客户端提前断开**
   - 处理：`websockets.exceptions.ConnectionClosedOK` 捕获
   - 行为：静默处理，不抛出异常

3. **无效 JSON**
   - 风险：接收非 JSON 数据会导致异常
   - 当前：未处理，会抛出异常

4. **二进制消息**
   - 处理：尝试 UTF-8 解码为 JSON
   - 风险：非 UTF-8 二进制数据会导致错误

### 改进建议

1. **支持配置文件**
   ```python
   parser.add_argument("--config", help="Path to response sequence config file")
   # 支持 YAML/JSON 格式定义响应序列
   ```

2. **添加错误模拟**
   ```python
   def _event_error(message: str) -> dict[str, Any]:
       return {"type": "error", "message": message}
   # 支持模拟 API 错误响应
   ```

3. **支持多轮对话**
   ```python
   # 维护会话状态，支持多轮交互
   sessions: dict[str, SessionState] = {}
   ```

4. **添加延迟模拟**
   ```python
   async def send_event(ev: dict[str, Any], delay: float = 0) -> None:
       if delay:
           await asyncio.sleep(delay)
       await websocket.send(_dump_json(ev))
   ```

5. **支持 TLS**
   ```python
   # 添加 SSL 上下文支持
   ssl_context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
   ssl_context.load_cert_chain(certfile, keyfile)
   await websockets.serve(handler, HOST, port, ssl=ssl_context)
   ```

6. **增强日志**
   ```python
   import logging
   logging.basicConfig(level=logging.DEBUG)
   # 添加详细的服务器日志
   ```

7. **支持流式响应**
   ```python
   # 模拟真实的流式输出（逐字/逐句）
   async def stream_assistant_message(text: str, chunk_size: int = 5):
       for i in range(0, len(text), chunk_size):
           chunk = text[i:i+chunk_size]
           await send_event(_event_content_chunk(chunk))
           await asyncio.sleep(0.1)
   ```

8. **添加健康检查端点**
   ```python
   # 支持 HTTP 健康检查
   async def health_handler(request):
       return web.Response(text="OK")
   ```

### 测试建议

```python
# 建议添加的测试场景
def test_websocket_handshake():
    """测试 WebSocket 握手"""
    pass

def test_response_sequence():
    """测试完整响应序列"""
    pass

def test_invalid_path():
    """测试无效路径处理"""
    pass

def test_early_disconnect():
    """测试客户端提前断开"""
    pass
```

### 与真实 API 的差异

| 特性 | 模拟服务器 | 真实 OpenAI API |
|------|-----------|----------------|
| 认证 | 忽略 | 需要有效 API 密钥 |
| 延迟 | 几乎无 | 网络延迟 + 处理时间 |
| 响应内容 | 固定 | 基于输入动态生成 |
| 错误处理 | 简单 | 详细的错误码和消息 |
| 并发 | 单连接 | 高并发支持 |
| 流式输出 | 一次性 | Server-Sent Events |
