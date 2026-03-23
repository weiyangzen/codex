# test_real_app_server_integration.py 研究文档

## 场景与职责

本测试文件是 Python SDK 的端到端集成测试，验证 SDK 与真实 Codex app-server 的交互。这些测试需要实际运行 Codex 二进制文件，因此默认被跳过，仅在显式启用时执行。它们是发布前验证和 CI/CD 流程中的关键质量关卡。

## 功能点目的

### 1. 运行时环境准备
- **目的**: 为集成测试准备隔离的 Python 运行时环境
- **测试内容**:
  - 安装运行时包 `codex-cli-bin`
  - 配置 `PYTHONPATH` 以包含 SDK 源码
  - 设置环境变量

### 2. 真实服务器初始化验证
- **目的**: 验证 SDK 可以正确初始化并与真实服务器通信
- **测试内容**:
  - `initialize` 和 `model_list` RPC 调用
  - 服务器元数据解析
  - 模型列表获取

### 3. 线程和 Turn 端到端测试
- **目的**: 验证完整的对话流程
- **测试内容**:
  - 创建新线程 (`thread_start`)
  - 发送消息并获取响应 (`turn` / `run`)
  - 持久化验证（读取线程历史）
  - 同步和异步 API 的 parity

### 4. Notebook 验证
- **目的**: 验证 SDK 文档中的示例代码可以正确运行
- **测试内容**:
  - Notebook 引导代码从不同工作目录解析 SDK
  - 同步和高级示例单元格的执行

### 5. 流式处理测试
- **目的**: 验证流式通知处理
- **测试内容**:
  - `item/agentMessage/delta` 通知接收
  - `turn/completed` 通知接收
  - 流完整性验证

### 6. Turn 中断测试
- **目的**: 验证 Turn 中断功能
- **测试内容**: 启动长时间运行的 Turn，中断后发送后续消息

### 7. 示例代码验证
- **目的**: 验证所有示例代码可以正确执行
- **测试内容**: 14 个示例文件夹的同步和异步变体

## 具体技术实现

### 测试启用控制
```python
RUN_REAL_CODEX_TESTS = os.environ.get("RUN_REAL_CODEX_TESTS") == "1"
pytestmark = pytest.mark.skipif(
    not RUN_REAL_CODEX_TESTS,
    reason="set RUN_REAL_CODEX_TESTS=1 to run real Codex integration coverage",
)
```

**启用方式**:
```bash
export RUN_REAL_CODEX_TESTS=1
pytest sdk/python/tests/test_real_app_server_integration.py
```

### 运行时环境夹具
```python
@dataclass(frozen=True)
class PreparedRuntimeEnv:
    python: str
    env: dict[str, str]
    runtime_version: str

@pytest.fixture(scope="session")
def runtime_env(tmp_path_factory: pytest.TempPathFactory) -> PreparedRuntimeEnv:
    runtime_version = pinned_runtime_version()
    temp_root = tmp_path_factory.mktemp("python-runtime-env")
    isolated_site = temp_root / "site-packages"
    python = sys.executable

    # 安装 pydantic 到隔离环境
    _run_command([python, "-m", "pip", "install", "--target", str(isolated_site), "pydantic>=2.12"], ...)
    
    # 安装运行时包
    ensure_runtime_package_installed(python, ROOT, install_target=isolated_site)

    env = os.environ.copy()
    env["PYTHONPATH"] = os.pathsep.join([str(isolated_site), str(ROOT / "src")])
    env["CODEX_PYTHON_SDK_DIR"] = str(ROOT)
    return PreparedRuntimeEnv(python=python, env=env, runtime_version=runtime_version)
```

**隔离策略**:
- 使用 `--target` 安装到临时目录，避免污染系统环境
- 设置 `PYTHONPATH` 优先使用隔离环境的包

### 子进程执行辅助函数
```python
def _run_json_python(runtime_env: PreparedRuntimeEnv, source: str, *, timeout_s: int = 180) -> dict[str, object]:
    result = _run_python(runtime_env, source, timeout_s=timeout_s)
    assert result.returncode == 0, (
        "Python snippet failed.\n"
        f"STDOUT:\n{result.stdout}\n"
        f"STDERR:\n{result.stderr}"
        f"{_runtime_compatibility_hint(runtime_env, stdout=result.stdout, stderr=result.stderr)}"
    )
    return json.loads(result.stdout)
```

**兼容性提示**:
```python
def _runtime_compatibility_hint(runtime_env: PreparedRuntimeEnv, *, stdout: str, stderr: str) -> str:
    combined = f"{stdout}\n{stderr}"
    if "ThreadStartResponse" in combined and "approvalsReviewer" in combined:
        return (
            "\nCompatibility hint:\n"
            f"Pinned runtime {runtime_env.runtime_version} returned a thread/start payload "
            "that is older than the current SDK schema and is missing "
            "`approvalsReviewer`. Bump `sdk/python/_runtime_setup.py` to a matching "
            "released runtime version.\n"
        )
    return ""
```

### 端到端测试示例
```python
def test_real_thread_and_turn_start_smoke(runtime_env: PreparedRuntimeEnv) -> None:
    data = _run_json_python(
        runtime_env,
        textwrap.dedent("""
            import json
            from codex_app_server import Codex, TextInput

            with Codex() as codex:
                thread = codex.thread_start(
                    model="gpt-5.4",
                    config={"model_reasoning_effort": "high"},
                )
                result = thread.turn(TextInput("hello")).run()
                persisted = thread.read(include_turns=True)
                persisted_turn = next(
                    (turn for turn in persisted.thread.turns or [] if turn.id == result.id),
                    None,
                )
                print(json.dumps({
                    "thread_id": thread.id,
                    "turn_id": result.id,
                    "status": result.status.value,
                    "items_count": len(result.items or []),
                    "persisted_items_count": 0 if persisted_turn is None else len(persisted_turn.items or []),
                }))
        """),
    )

    assert isinstance(data["thread_id"], str) and data["thread_id"].strip()
    assert isinstance(data["turn_id"], str) and data["turn_id"].strip()
    assert data["status"] == "completed"
```

### 示例测试参数化
```python
EXAMPLE_CASES: list[tuple[str, str]] = [
    ("01_quickstart_constructor", "sync.py"),
    ("01_quickstart_constructor", "async.py"),
    ("02_turn_run", "sync.py"),
    ("02_turn_run", "async.py"),
    # ... 共 28 个测试用例
]

@pytest.mark.parametrize(("folder", "script"), EXAMPLE_CASES)
def test_real_examples_run_and_assert(runtime_env: PreparedRuntimeEnv, folder: str, script: str) -> None:
    result = _run_example(runtime_env, folder, script)
    assert result.returncode == 0, f"Example failed: {folder}/{script}"
    
    # 根据示例类型验证特定输出
    if folder == "01_quickstart_constructor":
        assert "Status:" in out and "Text:" in out
    elif folder == "02_turn_run":
        assert "thread_id:" in out and "turn_id:" in out
    # ...
```

### Notebook 单元格提取
```python
def _notebook_cell_source(cell_index: int) -> str:
    notebook = json.loads(NOTEBOOK_PATH.read_text())
    return "".join(notebook["cells"][cell_index]["source"])

def test_notebook_sync_cell_smoke(runtime_env: PreparedRuntimeEnv) -> None:
    source = "\n\n".join([
        _notebook_cell_source(1),
        _notebook_cell_source(2),
        _notebook_cell_source(3),
    ])
    result = _run_python(runtime_env, source, timeout_s=240)
    assert "status:" in result.stdout
```

## 关键代码路径与文件引用

### 被测试的核心文件
| 文件路径 | 相关实现 |
|---------|---------|
| `sdk/python/src/codex_app_server/api.py` | `Codex`, `AsyncCodex`, `Thread`, `AsyncThread` |
| `sdk/python/src/codex_app_server/client.py` | `AppServerClient` |
| `sdk/python/_runtime_setup.py` | `ensure_runtime_package_installed()`, `pinned_runtime_version()` |
| `sdk/python/examples/` | 示例代码目录 |
| `sdk/python/notebooks/sdk_walkthrough.ipynb` | Notebook 文档 |

### 关键测试函数
| 函数名 | 测试目标 |
|-------|---------|
| `test_real_initialize_and_model_list` | 服务器初始化和模型列表 |
| `test_real_thread_and_turn_start_smoke` | 基本线程/Turn 流程 |
| `test_real_thread_run_convenience_smoke` | Thread.run() 便捷方法 |
| `test_real_async_thread_turn_usage_and_ids_smoke` | 异步 API 和用量统计 |
| `test_real_streaming_smoke_turn_completed` | 流式通知处理 |
| `test_real_turn_interrupt_smoke` | Turn 中断功能 |
| `test_real_examples_run_and_assert` | 示例代码执行 |
| `test_notebook_*` | Notebook 单元格执行 |

### 示例覆盖矩阵
| 示例 | 描述 |
|-----|------|
| 01_quickstart_constructor | 快速入门 |
| 02_turn_run | Turn 执行 |
| 03_turn_stream_events | 流式事件 |
| 04_models_and_metadata | 模型和元数据 |
| 05_existing_thread | 现有线程 |
| 06_thread_lifecycle_and_controls | 线程生命周期 |
| 07_image_and_text | 图片和文本 |
| 08_local_image_and_text | 本地图片 |
| 09_async_parity | 异步 API |
| 10_error_handling_and_retry | 错误处理 |
| 11_cli_mini_app | CLI 迷你应用 |
| 12_turn_params_kitchen_sink | 完整参数 |
| 13_model_select_and_turn_params | 模型选择 |
| 14_turn_controls | Turn 控制 |

## 依赖与外部交互

### 外部系统依赖
- **Codex 二进制文件**: 通过 `codex-cli-bin` 包提供
- **OpenAI API**: app-server 需要调用 OpenAI API
- **网络连接**: 下载运行时包、调用 API

### 环境变量
- `RUN_REAL_CODEX_TESTS`: 启用集成测试
- `OPENAI_API_KEY`: app-server 需要
- `GH_TOKEN` / `GITHUB_TOKEN`: 下载运行时包（可选）

### 文件系统依赖
- 临时目录用于隔离环境
- 示例代码和 Notebook 文件

### 时间要求
- 测试超时设置：180-360 秒
- 模型推理可能需要较长时间

## 风险、边界与改进建议

### 潜在风险
1. **外部依赖不稳定**: OpenAI API 可能不可用或响应慢
2. **成本**: 每次测试调用都会消耗 API 额度
3. **平台差异**: 运行时包在不同平台的行为可能略有不同
4. **版本兼容性**: SDK 和运行时版本不匹配可能导致失败

### 边界情况
1. **API 限流**: 大量测试可能触发 OpenAI API 限流
2. **超时**: 模型推理时间不确定，可能导致超时
3. **网络中断**: 下载运行时包或调用 API 时网络问题

### 改进建议
1. **增加重试机制**: 对 flaky 的 API 调用增加指数退避重试
   ```python
   @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
   def test_with_retry():
       # 测试逻辑
   ```

2. **使用录制/回放**: 使用 vcr.py 录制 API 响应，后续测试回放
   ```python
   @pytest.mark.vcr()
   def test_real_thread_and_turn_start_smoke():
       # 首次运行录制，后续回放
   ```

3. **并行执行控制**: 使用 pytest-xdist 的 `--dist=loadfile` 避免并行执行集成测试
   ```bash
   pytest -n auto --dist=loadfile  # 每个文件一个进程
   ```

4. **选择性执行**: 添加标记允许只运行特定示例
   ```python
   @pytest.mark.example("quickstart")
   def test_01_quickstart():
       ...
   ```

5. **健康检查**: 在测试开始前验证服务器可用
   ```python
   def test_server_health_check(runtime_env):
       # 快速 ping 服务器，失败则跳过所有测试
   ```

6. **资源清理**: 确保测试创建的线程被清理
   ```python
   @pytest.fixture(autouse=True)
   def cleanup_threads():
       yield
       # 清理所有测试线程
   ```

7. **成本监控**: 记录 API 调用次数和 token 使用量
   ```python
   def test_with_cost_tracking():
       with track_api_cost() as cost:
           # 测试逻辑
       print(f"Test cost: ${cost.total}")
   ```
