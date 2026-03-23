# test_artifact_workflow_and_binaries.py 研究文档

## 场景与职责

本测试文件负责验证 Python SDK 的构建、打包和运行时分发工作流。它确保代码生成、运行时包管理、SDK 打包等关键流程按预期工作，是发布流程的质量守门人。测试覆盖了从开发到发布的完整生命周期，包括类型生成、运行时安装、包结构验证等关键环节。

## 功能点目的

### 1. 代码生成工作流验证
- **目的**: 确保 `scripts/update_sdk_artifacts.py` 是唯一的代码生成入口点
- **测试内容**:
  - 验证脚本目录中只有一个 Python 脚本
  - 验证 `generate_types()` 函数按正确顺序调用生成步骤
  - 验证生成的代码使用 `--use-title-as-name` 等正确参数

### 2. Schema 处理验证
- **目的**: 确保 JSON Schema 的正确处理和转换
- **测试内容**:
  - 验证字符串枚举的 `oneOf` 结构被正确扁平化
  - 验证生成的类名使用稳定的 title 命名
  - 验证特定类型（如 `AuthMode`, `MessagePhase` 等）的处理

### 3. 运行时包管理验证
- **目的**: 确保 `codex-cli-bin` 运行时包的正确构建和分发
- **测试内容**:
  - 验证运行时包模板不包含预构建的二进制文件
  - 验证运行时包仅构建平台特定的 wheel（无 sdist）
  - 验证版本注入和依赖关系

### 4. 发布流程验证
- **目的**: 确保 SDK 和运行时包的发布流程正确
- **测试内容**:
  - 验证运行时发布暂存时复制二进制文件并设置版本
  - 验证 SDK 发布暂存时注入精确的运行时版本依赖
  - 验证暂存目录的清理和替换逻辑
  - 验证 GitHub API 认证失败时的重试逻辑

### 5. 二进制解析器验证
- **目的**: 确保 Codex 二进制文件的解析逻辑正确
- **测试内容**:
  - 验证从已安装运行时包解析默认二进制路径
  - 验证显式配置的 `codex_bin` 优先于运行时包
  - 验证缺失运行时包时抛出正确错误

## 具体技术实现

### 模块动态加载
```python
def _load_update_script_module():
    script_path = ROOT / "scripts" / "update_sdk_artifacts.py"
    spec = importlib.util.spec_from_file_location("update_sdk_artifacts", script_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module
```
- 使用 `importlib.util` 动态加载脚本模块，无需将其作为包安装
- 允许测试直接调用脚本内部函数

### AST 解析验证
```python
tree = ast.parse(source)
generate_types_fn = next(
    (node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "generate_types"),
    None,
)
```
- 使用 AST（抽象语法树）解析验证代码结构
- 验证函数调用顺序和参数

### 运行时包构建验证
```python
pyproject = tomllib.loads((ROOT.parent / "python-runtime" / "pyproject.toml").read_text())
hook_source = (ROOT.parent / "python-runtime" / "hatch_build.py").read_text()
hook_tree = ast.parse(hook_source)
```
- 解析 `pyproject.toml` 验证构建配置
- 解析 `hatch_build.py` 验证自定义构建钩子
- 验证 sdist 守卫（阻止源码分发）和平台特定 wheel 构建

### 发布元数据获取测试
```python
def fake_urlopen(request):
    authorization = request.headers.get("Authorization")
    authorizations.append(authorization)
    if authorization is not None:
        raise urllib.error.HTTPError(...)
    return io.StringIO('{"assets": []}')
```
- 使用 monkeypatch 模拟 `urllib.request.urlopen`
- 验证在 401 错误后重试不带认证头的请求

## 关键代码路径与文件引用

### 被测试的核心文件
| 文件路径 | 测试覆盖点 |
|---------|-----------|
| `sdk/python/scripts/update_sdk_artifacts.py` | 代码生成、包暂存、CLI 操作 |
| `sdk/python/_runtime_setup.py` | 运行时安装、版本解析、GitHub API 调用 |
| `sdk/python-runtime/pyproject.toml` | 运行时包构建配置 |
| `sdk/python-runtime/hatch_build.py` | 自定义构建钩子 |
| `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json` | Schema 定义 |

### 关键测试函数
| 函数名 | 测试目标 |
|-------|---------|
| `test_generation_has_single_maintenance_entrypoint_script` | 单一维护入口点 |
| `test_generate_types_wires_all_generation_steps` | 生成步骤顺序 |
| `test_schema_normalization_only_flattens_string_literal_oneofs` | Schema 扁平化 |
| `test_python_codegen_schema_annotation_adds_stable_variant_titles` | 类名稳定性 |
| `test_runtime_package_is_wheel_only_and_builds_platform_specific_wheels` | Wheel 构建 |
| `test_stage_runtime_release_copies_binary_and_sets_version` | 运行时暂存 |
| `test_stage_sdk_release_injects_exact_runtime_pin` | SDK 依赖注入 |
| `test_release_metadata_retries_without_invalid_auth` | 认证重试 |
| `test_default_runtime_is_resolved_from_installed_runtime_package` | 二进制解析 |

## 依赖与外部交互

### 外部系统依赖
- **GitHub API**: `_release_metadata()` 函数调用 GitHub Releases API 获取运行时包信息
- **文件系统**: 大量文件读写操作，包括临时目录创建、二进制文件复制等

### 环境变量
- `GH_TOKEN` / `GITHUB_TOKEN`: 用于 GitHub API 认证

### 测试夹具
- `tmp_path`: pytest 提供的临时目录夹具
- `monkeypatch`: pytest 提供的环境修改夹具

### 被测试的 CLI 命令
```bash
python scripts/update_sdk_artifacts.py generate-types
python scripts/update_sdk_artifacts.py stage-sdk <dir> --runtime-version <ver>
python scripts/update_sdk_artifacts.py stage-runtime <dir> <binary> --runtime-version <ver>
```

## 风险、边界与改进建议

### 潜在风险
1. **外部网络依赖**: `test_release_metadata_retries_without_invalid_auth` 测试模拟了网络请求，但真实场景可能遇到更多网络问题
2. **平台差异**: 测试在 Windows 和 Unix 上的行为可能不同（如二进制文件名、路径分隔符）
3. **版本耦合**: 测试硬编码了版本号检查（如 `0.2.0`），当版本升级时需要同步更新

### 边界情况
1. **并发执行**: 多个测试同时运行时，临时目录操作可能冲突
2. **磁盘空间**: 测试涉及大量文件操作，需要足够的临时磁盘空间
3. **权限问题**: 在受限环境中，二进制文件权限设置可能失败

### 改进建议
1. **增加平台特定测试**: 为 Windows、macOS、Linux 分别添加平台特定的测试用例
   ```python
   @pytest.mark.skipif(sys.platform != "win32", reason="Windows only")
   def test_windows_binary_name():
       assert runtime_binary_name() == "codex.exe"
   ```

2. **网络隔离测试**: 添加完全离线的测试模式，验证在没有网络时的行为

3. **版本号解耦**: 使用动态版本获取而非硬编码
   ```python
   expected_version = current_sdk_version()
   assert f'version = "{expected_version}"' in pyproject
   ```

4. **增加完整性检查**: 验证暂存后的包可以通过 pip 安装
   ```python
   def test_staged_runtime_is_installable(tmp_path):
       staged = stage_python_runtime_package(tmp_path, "1.0.0", fake_binary)
       result = subprocess.run([sys.executable, "-m", "pip", "install", "--dry-run", str(staged)])
       assert result.returncode == 0
   ```

5. **Schema 变更检测**: 当 schema 文件变更时，自动触发代码生成并验证差异
   ```python
   def test_schema_changes_detected():
       # 比较当前 schema 与上次生成时的 schema 哈希
       # 如果不同，验证生成的代码已更新
   ```
