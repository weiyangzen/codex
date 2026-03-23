# test_contract_generation.py 研究文档

## 场景与职责

本测试文件验证 Python SDK 的代码生成契约完整性。它确保通过 `scripts/update_sdk_artifacts.py` 生成的代码与仓库中检入的代码保持一致，防止开发者忘记重新生成代码或手动修改生成的文件。

## 功能点目的

### 1. 生成文件一致性验证
- **目的**: 确保检入的生成文件是最新的
- **背景**: SDK 的生成代码（`v2_all.py`, `notification_registry.py`, `api.py`）是从 JSON Schema 自动生成的
- **测试方法**: 运行代码生成脚本，比较前后文件内容

### 2. 单一维护入口点验证
- **目的**: 确保所有生成操作都通过 `update_sdk_artifacts.py` 脚本执行
- **背景**: 维护多个生成入口点会导致不一致和遗漏
- **测试方法**: 验证 `scripts/` 目录中只有一个 Python 脚本

## 具体技术实现

### 快照比较机制
```python
GENERATED_TARGETS = [
    Path("src/codex_app_server/generated/notification_registry.py"),
    Path("src/codex_app_server/generated/v2_all.py"),
    Path("src/codex_app_server/api.py"),
]

def _snapshot_target(root: Path, rel_path: Path) -> dict[str, bytes] | bytes | None:
    target = root / rel_path
    if not target.exists():
        return None
    if target.is_file():
        return target.read_bytes()
    
    # 递归快照目录
    snapshot: dict[str, bytes] = {}
    for path in sorted(target.rglob("*")):
        if path.is_file() and "__pycache__" not in path.parts:
            snapshot[str(path.relative_to(target))] = path.read_bytes()
    return snapshot
```

**关键设计**:
- 支持单文件和目录的快照
- 排除 `__pycache__` 目录
- 使用字典结构存储相对路径到内容的映射

### 生成流程测试
```python
def test_generated_files_are_up_to_date():
    before = _snapshot_targets(ROOT)

    # 设置环境并运行生成脚本
    env = os.environ.copy()
    python_bin = str(Path(sys.executable).parent)
    env["PATH"] = f"{python_bin}{os.pathsep}{env.get('PATH', '')}"

    subprocess.run(
        [sys.executable, "scripts/update_sdk_artifacts.py", "generate-types"],
        cwd=ROOT,
        check=True,
        env=env,
    )

    after = _snapshot_targets(ROOT)
    assert before == after, "Generated files drifted after regeneration"
```

**执行流程**:
1. 捕获生成前的文件状态快照
2. 运行代码生成脚本
3. 捕获生成后的文件状态快照
4. 比较前后快照，验证无差异

### 环境配置
```python
env["PATH"] = f"{python_bin}{os.pathsep}{env.get('PATH', '')}"
```
- 确保脚本可以找到正确的 Python 解释器
- 优先使用当前虚拟环境的 Python

## 关键代码路径与文件引用

### 被测试的核心文件
| 文件路径 | 说明 |
|---------|------|
| `sdk/python/scripts/update_sdk_artifacts.py` | 代码生成脚本入口 |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 从 schema 生成的 Pydantic 模型 |
| `sdk/python/src/codex_app_server/generated/notification_registry.py` | 通知类型注册表 |
| `sdk/python/src/codex_app_server/api.py` | 公共 API 层（包含生成的代码块） |

### 代码生成流程
```
JSON Schema (codex-rs/app-server-protocol/schema/)
    ↓
datamodel-code-generator
    ↓
v2_all.py (Pydantic 模型)
    ↓
notification_registry.py (通知注册表)
    ↓
api.py (公共 API 方法)
```

### 关键测试断言
| 测试函数 | 断言 | 验证目标 |
|---------|------|---------|
| `test_generated_files_are_up_to_date` | `before == after` | 生成文件与检入文件一致 |

## 依赖与外部交互

### 外部工具依赖
- `datamodel-code-generator`: 从 JSON Schema 生成 Pydantic 模型
- `ruff-format`: 代码格式化

### 文件系统依赖
- 需要写入临时文件进行代码生成
- 依赖 `sdk/python/src` 目录结构

### 环境依赖
- Python 解释器路径
- `PATH` 环境变量

## 风险、边界与改进建议

### 潜在风险
1. **工具版本差异**: 不同版本的 `datamodel-code-generator` 可能生成不同的代码
2. **平台差异**: Windows 和 Unix 的换行符差异可能导致比较失败
3. **非确定性生成**: 如果生成过程包含时间戳或随机元素，比较会失败

### 边界情况
1. **文件权限**: 生成文件的权限可能与原始文件不同
2. **符号链接**: 如果目标文件是符号链接，快照比较可能不准确
3. **并发执行**: 多个测试同时运行生成脚本可能冲突

### 改进建议
1. **规范化换行符**: 在比较前统一换行符
   ```python
   def _normalize_content(content: bytes) -> bytes:
       return content.replace(b'\r\n', b'\n')
   ```

2. **工具版本锁定**: 验证生成工具版本与预期一致
   ```python
   def test_codegen_tool_version():
       result = subprocess.run([sys.executable, "-m", "datamodel_code_generator", "--version"], ...)
       assert expected_version in result.stdout
   ```

3. **选择性比较**: 排除已知的非确定性内容（如时间戳）
   ```python
   def _filter_timestamp_lines(content: bytes) -> bytes:
       lines = content.split(b'\n')
       filtered = [l for l in lines if not l.startswith(b'# timestamp:')]
       return b'\n'.join(filtered)
   ```

4. **详细差异输出**: 当比较失败时，提供详细的差异信息
   ```python
   if before != after:
       diff = compute_diff(before, after)
       raise AssertionError(f"Generated files drifted:\n{diff}")
   ```

5. **增量生成测试**: 验证只修改相关文件，不影响其他生成文件
   ```python
   def test_generation_is_incremental():
       # 修改单个 schema 文件
       # 验证只有相关生成文件变更
   ```

6. **CI 集成**: 在 CI 中自动运行此测试，阻止未重新生成代码的 PR
   ```yaml
   # .github/workflows/ci.yml
   - name: Check generated code
     run: pytest sdk/python/tests/test_contract_generation.py -v
   ```
