# conftest.py 研究文档

## 场景与职责

`conftest.py` 是 pytest 测试框架的配置文件，位于 `sdk/python/tests/` 目录下。它负责在测试会话开始前配置 Python 路径，确保测试能够正确导入 `codex_app_server` 包及其相关模块。这是 Python SDK 测试套件的基础配置入口。

## 功能点目的

### 1. 源码路径注入
- **目的**: 确保测试代码优先从 `sdk/python/src` 加载源码，而非已安装的包
- **实现**: 将 `src` 目录插入到 `sys.path` 的最前面
- **关键逻辑**: 如果 `src` 已存在于 `sys.path` 中，先移除再插入，确保优先级

### 2. 模块缓存清理
- **目的**: 防止测试运行前已加载的 `codex_app_server` 模块干扰测试结果
- **实现**: 遍历 `sys.modules`，移除所有以 `codex_app_server` 开头的模块
- **场景**: 当测试在已导入模块的环境中运行时（如 IDE 或连续测试），确保干净状态

## 具体技术实现

### 路径计算逻辑
```python
ROOT = Path(__file__).resolve().parents[1]  # sdk/python/
SRC = ROOT / "src"                           # sdk/python/src
```

### 路径注入流程
1. 解析 `src` 目录的绝对路径
2. 检查并移除已存在的相同路径（避免重复）
3. 使用 `sys.path.insert(0, src_str)` 将源码路径置于最前

### 模块清理流程
```python
for module_name in list(sys.modules):
    if module_name == "codex_app_server" or module_name.startswith("codex_app_server."):
        sys.modules.pop(module_name)
```

## 关键代码路径与文件引用

### 本文件位置
- `sdk/python/tests/conftest.py`

### 影响范围
- 所有 `sdk/python/tests/` 目录下的测试文件
- 包括：`test_artifact_workflow_and_binaries.py`, `test_async_client_behavior.py`, `test_client_rpc_methods.py`, `test_contract_generation.py`, `test_public_api_runtime_behavior.py`, `test_public_api_signatures.py`, `test_real_app_server_integration.py`

### 依赖的目录结构
```
sdk/python/
├── src/
│   └── codex_app_server/      # 被注入到 sys.path 的源码目录
├── tests/
│   └── conftest.py            # 本文件
└── ...
```

## 依赖与外部交互

### 标准库依赖
- `sys`: 用于路径操作和模块管理
- `pathlib.Path`: 用于跨平台路径处理

### 与 pytest 的集成
- pytest 自动发现机制：pytest 会自动加载 `conftest.py` 中的配置
- 执行时机：在每个测试会话开始前执行

### 与运行时包的关系
- 确保测试使用本地源码而非已安装的 `codex-cli-bin` 运行时包
- 与 `_runtime_setup.py` 协同工作，后者负责运行时包的安装和管理

## 风险、边界与改进建议

### 潜在风险
1. **路径污染**: 如果其他测试或代码修改了 `sys.path`，可能导致导入顺序混乱
2. **模块残留**: 清理逻辑只处理 `codex_app_server` 前缀的模块，如果存在循环导入或复杂依赖，可能清理不彻底
3. **并发问题**: 在多线程测试环境中，模块清理可能在测试执行期间发生，导致竞态条件

### 边界情况
1. **空路径处理**: 如果 `src` 目录不存在，代码会抛出异常（但这种情况在正确配置的项目中不会发生）
2. **Windows/Unix 路径差异**: 使用 `pathlib` 处理，已考虑跨平台兼容性

### 改进建议
1. **添加验证**: 在路径注入后验证 `codex_app_server` 是否能正确从源码导入
   ```python
   try:
       import codex_app_server
       assert "src" in codex_app_server.__file__
   except (ImportError, AssertionError):
       raise RuntimeError("Failed to import codex_app_server from source")
   ```

2. **日志记录**: 添加调试日志，记录路径修改和模块清理操作

3. **环境变量控制**: 添加环境变量开关，允许在需要时禁用路径注入（如测试已安装包时）
   ```python
   if os.environ.get("CODEX_TEST_USE_INSTALLED"):
       return  # 跳过路径注入
   ```

4. **清理范围扩展**: 考虑清理所有与 codex 相关的模块，包括可能的子包
   ```python
   prefixes = ("codex_app_server", "codex_cli_bin")
   for module_name in list(sys.modules):
       if any(module_name == p or module_name.startswith(f"{p}.") for p in prefixes):
           sys.modules.pop(module_name)
   ```
