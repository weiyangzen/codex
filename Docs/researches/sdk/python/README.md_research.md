# sdk/python/README.md 研究文档

## 场景与职责

README.md 是 Codex App Server Python SDK 的官方文档入口，面向 Python 开发者提供：
- 项目概述与定位说明（Experimental Python SDK for `codex app-server` JSON-RPC v2）
- 安装指南与快速开始教程
- 文档地图（Docs map）指引
- 运行时打包策略说明
- 维护者工作流（CI/CD 发布流程）
- 兼容性版本信息

该文件是 SDK 用户的第一接触点，承担着降低使用门槛、建立正确预期的关键职责。

## 功能点目的

### 1. 项目定位说明
- 明确 SDK 为实验性（Experimental）产品
- 说明通信协议：JSON-RPC v2 over stdio
- 说明数据模型：Pydantic models with snake_case Python fields，序列化为 camelCase wire format

### 2. 安装指南
- 本地开发安装：`pip install -e .`
- 运行时依赖说明：`codex-cli-bin` 包的两种获取方式
  - 发布版本：自动安装 pinned 的 `codex-cli-bin`
  - 本地开发：通过 `AppServerConfig(codex_bin=...)` 显式指定本地构建

### 3. Quickstart 示例
```python
from codex_app_server import Codex

with Codex() as codex:
    thread = codex.thread_start(model="gpt-5")
    result = thread.run("Say hello in one sentence.")
    print(result.final_response)
```
- 展示同步 API 的基本使用模式
- 强调 context manager 的重要性（确保 shutdown）
- 说明 `result.final_response` 可能为 `None` 的情况

### 4. 文档地图（Docs Map）
- `docs/getting-started.md` - 黄金路径教程
- `docs/api-reference.md` - API 参考
- `docs/faq.md` - 常见问题
- `examples/README.md` - 可运行示例索引
- `notebooks/sdk_walkthrough.ipynb` - Jupyter 教程

### 5. 运行时打包策略
- 仓库不再将 `codex` 二进制文件提交到 `sdk/python`
- 发布版本 SDK 固定依赖特定版本的 `codex-cli-bin`
- `sdk/python-runtime` 是发布产物的模板，仅用于暂存发布工件

### 6. 维护者工作流
提供 CI 发布流程支持：
```bash
python scripts/update_sdk_artifacts.py generate-types
python scripts/update_sdk_artifacts.py stage-sdk <dir> --runtime-version 1.2.3
python scripts/update_sdk_artifacts.py stage-runtime <dir> <binary> --runtime-version 1.2.3
```

### 7. 兼容性版本矩阵
| 组件 | 信息 |
|------|------|
| Package | `codex-app-server-sdk` |
| Runtime Package | `codex-cli-bin` |
| SDK Version | `0.2.0` |
| Python | `>=3.10` |
| Protocol | JSON-RPC v2 |

## 具体技术实现

### 文档结构
- Markdown 格式，标准 README 结构
- 代码块使用 Python 语法高亮
- 内联注释说明关键注意事项

### 关键设计决策
1. **Eager Initialization**: `Codex()` 在构造函数中执行启动和 `initialize`
2. **Context Manager 必需**: 使用 `with Codex() as codex:` 确保资源释放
3. **API 分层**:
   - `thread.run()` - 简单场景（阻塞等待完成）
   - `thread.turn()` - 复杂场景（streaming, steering, interrupt）

## 关键代码路径与文件引用

### 相关文件
| 文件 | 关系 |
|------|------|
| `pyproject.toml` | 版本号来源（`version = "0.2.0"`） |
| `src/codex_app_server/__init__.py` | 导出的公共 API |
| `src/codex_app_server/api.py` | `Codex`, `Thread`, `TurnHandle` 实现 |
| `docs/getting-started.md` | 详细教程 |
| `examples/` | 可运行示例 |
| `scripts/update_sdk_artifacts.py` | 维护者脚本 |

### 版本号同步
README 中的版本号需与以下文件保持一致：
- `pyproject.toml`: `version = "0.2.0"`
- `src/codex_app_server/__init__.py`: `__version__ = "0.2.0"`

## 依赖与外部交互

### 外部依赖
1. **codex-cli-bin**: 运行时二进制依赖
   - 通过 PyPI 分发平台特定 wheel
   - 内部调用 `codex app-server --listen stdio://`

2. **Python 版本**: >=3.10

3. **pydantic**: >=2.12（数据验证）

### 协议依赖
- **JSON-RPC v2**: 与 Rust codex app-server 通信
- **stdio transport**: 进程间通信机制

## 风险、边界与改进建议

### 风险点
1. **实验性 API**: 明确标记为 Experimental，API 可能不稳定
2. **版本锁定**: SDK 与 `codex-cli-bin` 版本需保持同步
3. **单消费者限制**: 当前实验版本同一时间只能有一个活跃的 turn consumer

### 边界条件
1. **final_response 可能为 None**: 当 turn 完成但没有 final-answer 或 phase-less assistant message 时
2. **网络依赖**: 首次安装时需要下载 GitHub Release 的二进制文件
3. **平台支持**: 仅支持特定平台（macOS, Linux, Windows 的 x86_64/aarch64）

### 改进建议
1. **版本检查**: 建议在 SDK 初始化时检查 `codex-cli-bin` 版本兼容性
2. **离线安装**: 提供明确的离线安装文档（预下载二进制）
3. **错误处理**: 增加更多常见错误的排查指南（如 GH_TOKEN 配置）
4. **API 稳定性**: 随着项目成熟，逐步移除 Experimental 标记
5. **并发支持**: 文档中 TODO 提到需要替换 client-wide guard 为 per-turn event demux
