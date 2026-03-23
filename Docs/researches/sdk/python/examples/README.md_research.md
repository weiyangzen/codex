# sdk/python/examples/README.md 研究文档

## 场景与职责

`sdk/python/examples/README.md` 是 OpenAI Codex Python SDK 的示例集合文档入口，位于 `sdk/python/examples/` 目录下。该文档承担以下核心职责：

1. **示例导航中心**：作为 14 个示例代码文件夹的统一索引和入口点
2. **快速入门指南**：提供从环境搭建到运行第一个示例的完整流程
3. **运行时依赖说明**：解释示例如何自动获取和配置 `codex-cli-bin` 运行时
4. **SDK 使用范式**：阐明同步 (`Codex`) 和异步 (`AsyncCodex`) 两种 API 风格

该文档面向希望快速上手 Codex Python SDK 的开发者，特别是：
- 首次接触 SDK 的新用户
- 需要了解同步/异步 API 差异的开发者
- 需要参考具体功能实现模式的工程师

## 功能点目的

### 1. 示例结构说明
每个示例文件夹包含两个版本：
- `sync.py`：使用同步 API (`Codex` 类)
- `async.py`：使用异步 API (`AsyncCodex` 类)

这种双版本设计允许开发者根据应用场景选择适合的编程模型。

### 2. 环境准备指南
文档提供了推荐的虚拟环境设置流程：
```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install -U pip
python -m pip install -e .
```

### 3. 运行时自动配置机制
关键说明：当从仓库检出运行示例时，SDK 源码使用本地树（不捆绑运行时二进制文件）。`_bootstrap.py` 辅助模块负责：
- 检测已安装的 `codex-cli-bin` 运行时包
- 如未安装，自动下载匹配的 GitHub Release 制品
- 临时暂存并安装运行时包
- 清理临时文件

当前固定的运行时版本：`0.116.0-alpha.1`

### 4. 示例索引与功能映射

| 示例目录 | 功能描述 |
|---------|---------|
| `01_quickstart_constructor/` | 首次运行 / 健康检查 |
| `02_turn_run/` | 检查完整的 turn 输出字段 |
| `03_turn_stream_events/` | 使用精选事件视图流式传输 turn |
| `04_models_and_metadata/` | 发现连接运行时的可见模型 |
| `05_existing_thread/` | 恢复真实存在的线程（脚本内创建） |
| `06_thread_lifecycle_and_controls/` | 线程生命周期 + 控制调用 |
| `07_image_and_text/` | 远程图片 URL + 文本多模态 turn |
| `08_local_image_and_text/` | 本地图片 + 文本多模态 turn（使用生成的临时样本图片） |
| `09_async_parity/` | 同步流的对等实现（在其他示例中查看异步对等实现） |
| `10_error_handling_and_retry/` | 过载重试模式 + 类型化错误处理结构 |
| `11_cli_mini_app/` | 交互式聊天循环 |
| `12_turn_params_kitchen_sink/` | 结构化输出与精选的高级 `turn(...)` 配置 |
| `13_model_select_and_turn_params/` | 列出模型，选择最高模型 + 最高支持的推理力度，运行 turns，打印消息和用量 |
| `14_turn_controls/` | 单独的尽力而为 `steer()` 和 `interrupt()` 演示与简洁摘要 |

## 具体技术实现

### 运行时版本管理
- **固定版本**：`0.116.0-alpha.1`
- **版本来源**：GitHub Release (`openai/codex` 仓库)
- **制品命名模式**：`codex-{arch}-{platform}.{ext}`
  - 平台支持：macOS (aarch64/x86_64)、Linux (aarch64/x86_64)、Windows (aarch64/x86_64)
  - 格式：`.tar.gz` (Unix) / `.zip` (Windows)

### 示例运行模式
```python
# 同步模式示例流程
with Codex(config=runtime_config()) as codex:
    thread = codex.thread_start(model="gpt-5.4", config={...})
    result = thread.run("prompt")

# 异步模式示例流程
async with AsyncCodex(config=runtime_config()) as codex:
    thread = await codex.thread_start(model="gpt-5.4", config={...})
    result = await thread.run("prompt")
```

### 本地源码加载机制
所有示例通过以下模式实现本地 SDK 源码加载（无需安装 wheel）：
```python
_EXAMPLES_ROOT = Path(__file__).resolve().parents[1]
if str(_EXAMPLES_ROOT) not in sys.path:
    sys.path.insert(0, str(_EXAMPLES_ROOT))

from _bootstrap import ensure_local_sdk_src, runtime_config
ensure_local_sdk_src()  # 将 sdk/python/src 添加到 sys.path
```

## 关键代码路径与文件引用

### 核心依赖文件
| 文件路径 | 作用 |
|---------|------|
| `_bootstrap.py` | 示例共享的引导辅助模块，提供运行时配置、本地 SDK 加载、工具函数 |
| `_runtime_setup.py` | 运行时包下载、安装和管理（上级目录） |
| `../src/codex_app_server/` | 本地 SDK 源码目录 |

### 引导流程调用链
```
sync.py/async.py
  → _bootstrap.py:ensure_local_sdk_src()
    → _bootstrap.py:_ensure_runtime_dependencies()  # 检查 pydantic
    → 将 sdk/python/src 添加到 sys.path
  → _bootstrap.py:runtime_config()
    → _runtime_setup.py:ensure_runtime_package_installed()  # 确保 codex-cli-bin 可用
    → 返回 AppServerConfig 实例
```

### SDK 公共 API 入口
```python
# 同步 API
from codex_app_server import Codex, Thread, TurnHandle

# 异步 API
from codex_app_server import AsyncCodex, AsyncThread, AsyncTurnHandle

# 输入类型
from codex_app_server import TextInput, ImageInput, LocalImageInput, SkillInput, MentionInput

# 配置和模型
from codex_app_server import AppServerConfig, ThreadStartParams, TurnStartParams
```

## 依赖与外部交互

### Python 依赖
- **Python 版本**: >= 3.10
- **核心依赖**: pydantic（用于数据模型验证）
- **运行时依赖**: codex-cli-bin（Rust 实现的 Codex 运行时）

### 外部系统交互
1. **GitHub API**（`_runtime_setup.py`）
   - 获取 Release 元数据：`api.github.com/repos/openai/codex/releases/tags/rust-v{version}`
   - 下载制品：`github.com/openai/codex/releases/download/rust-v{version}/{asset}`
   - 认证：支持 `GH_TOKEN` / `GITHUB_TOKEN` 环境变量

2. **本地子进程**（`client.py`）
   - 启动 Codex 运行时：`codex app-server --listen stdio://`
   - 通信协议：JSON-RPC over stdio

3. **模型服务**（通过运行时）
   - OpenAI API（默认）
   - 其他配置的模型提供商

### 网络要求
- 首次运行需要网络连接下载运行时（如果未安装）
- 运行时与模型服务通信需要网络

## 风险、边界与改进建议

### 当前风险

1. **运行时版本锁定风险**
   - 固定版本 `0.116.0-alpha.1` 可能滞后于最新功能
   - 升级需要同步更新 `_runtime_setup.py` 中的 `PINNED_RUNTIME_VERSION`

2. **平台支持限制**
   - 仅支持特定架构/平台组合
   - 不支持 32 位系统或特定 Linux 发行版

3. **GitHub API 限制**
   - 未认证请求有速率限制（60 req/hour）
   - 建议用户配置 `GH_TOKEN` 或 `GITHUB_TOKEN`

4. **并发限制**
   - 当前 SDK 实验性不支持并发 turn 消费者
   - 尝试并发流式处理会抛出 `RuntimeError`

### 边界条件

1. **临时目录管理**
   - 运行时下载使用 `tempfile.TemporaryDirectory`
   - 安装失败可能留下残留文件（虽然使用上下文管理器）

2. **进程生命周期**
   - 运行时进程在 `Codex.close()` / 上下文退出时终止
   - 异常退出可能导致僵尸进程

3. **内存限制**
   - stderr 输出缓存限制为 400 行（`deque(maxlen=400)`）
   - 大量输出可能丢失早期日志

### 改进建议

1. **版本管理优化**
   ```python
   # 建议：支持版本范围或自动检测最新稳定版
   PINNED_RUNTIME_VERSION = ">=0.116.0-alpha.1,<0.117.0"
   ```

2. **离线模式支持**
   - 添加 `CODEX_RUNTIME_PATH` 环境变量支持
   - 允许完全离线运行（跳过下载）

3. **并发支持增强**
   - 实现 per-turn 事件多路复用（TODO 注释已存在）
   - 支持多个并发 turn 流

4. **错误处理改进**
   - 区分网络错误、权限错误和运行时错误
   - 提供重试和回退机制

5. **文档增强**
   - 添加每个示例的预期输出示例
   - 提供故障排除指南
   - 说明环境变量配置选项

6. **测试覆盖**
   - 为 `_bootstrap.py` 和 `_runtime_setup.py` 添加单元测试
   - 模拟 GitHub API 响应进行测试

### 相关文件引用

```
sdk/python/
├── examples/
│   ├── README.md              # 本文档
│   ├── _bootstrap.py          # 示例引导辅助
│   ├── 01_quickstart_constructor/
│   │   ├── sync.py
│   │   └── async.py
│   ├── ... (其他示例目录)
│   └── 14_turn_controls/
│       ├── sync.py
│       └── async.py
├── _runtime_setup.py          # 运行时安装逻辑
├── src/codex_app_server/
│   ├── __init__.py           # 公共 API 导出
│   ├── api.py                # Codex/AsyncCodex 类
│   ├── client.py             # AppServerClient 实现
│   ├── models.py             # 数据模型
│   ├── _inputs.py            # 输入类型定义
│   └── _run.py               # 运行结果收集
└── pyproject.toml            # 包配置
```
