# sandbox_smoketests.py 研究文档

## 场景与职责

`sandbox_smoketests.py` 是 Windows 沙箱的冒烟测试套件，用于验证 `codex-windows-sandbox` 的核心安全功能是否按预期工作。该测试脚本通过调用 Codex CLI 的 `sandbox windows` 子命令，执行一系列安全测试用例，确保沙箱的隔离性和访问控制机制有效。

## 功能点目的

### 1. 安全策略验证
测试两种主要沙箱策略：
- **Read-Only (RO)**: 只读模式，禁止任何写入操作
- **Workspace-Write (WS)**: 工作区写入模式，允许在指定目录写入

### 2. 隔离边界验证
验证沙箱的隔离边界，包括：
- 文件系统访问控制
- 网络访问阻止
- 路径遍历防护
- 符号链接/连接点攻击防护

### 3. 工具链可用性验证
验证沙箱内常用开发工具的可用性：
- `curl`, `git`, `ripgrep` 等

## 具体技术实现

### 测试架构
```
sandbox_smoketests.py
    │
    ├── 解析 Codex CLI 位置
    │       └── _resolve_codex_cmd()
    │
    ├── 运行测试用例
    │       └── run_sbx(policy, cmd_argv, cwd, ...)
    │           └── 调用: codex sandbox windows [--full-auto] -- <cmd>
    │
    └── 汇总结果
            └── summarize(results)
```

### 核心函数分析

#### `_resolve_codex_cmd()` - CLI 解析
```python
def _resolve_codex_cmd() -> List[str]:
    """解析 Codex CLI 可执行文件位置"""
    # 搜索顺序:
    # 1. ../target/debug/codex.exe
    # 2. ../target/release/codex.exe
    # 3. $CARGO_TARGET_DIR/debug/codex.exe
    # 4. $CARGO_TARGET_DIR/release/codex.exe
    # 5. PATH 中的 codex
```

#### `run_sbx()` - 沙箱执行器
```python
def run_sbx(
    policy: str,           # "read-only" 或 "workspace-write"
    cmd_argv: List[str],   # 要执行的命令
    cwd: Path,             # 工作目录
    env_extra: Optional[dict] = None,
    additional_root: Optional[Path] = None,
) -> Tuple[int, str, str]:
    # 构建命令行:
    # codex sandbox windows [--full-auto] [-c config] -- <cmd_argv>
```

### 测试用例详解

#### 文件系统访问测试 (测试 1-14, 24-28)

| 测试编号 | 名称 | 策略 | 验证内容 |
|---------|------|------|---------|
| 1 | RO: write in CWD denied | RO | 只读模式下禁止在工作目录写入 |
| 2 | WS: write in CWD allowed | WS | 写入模式下允许在工作目录写入 |
| 3 | WS: deny write outside workspace | WS | 禁止写入工作区外路径 |
| 3b | WS: allow write in additional root | WS | 允许写入额外配置的根目录 |
| 3c | RO: write in additional root denied | RO | 只读模式下禁止写入额外根目录 |
| 4 | WS: TEMP write allowed | WS | 允许写入 %TEMP% |
| 5 | RO: TEMP write denied | RO | 只读模式下禁止写入 %TEMP% |
| 6 | WS: append allowed | WS | 允许文件追加 |
| 7 | RO: append denied | RO | 只读模式下禁止文件追加 |
| 8-9 | PowerShell Set-Content | WS/RO | PowerShell 写入控制 |
| 10 | WS: mkdir+write allowed | WS | 创建目录并写入 |
| 11 | WS: rename succeeds | WS | 文件重命名 |
| 12 | WS: delete succeeds | WS | 文件删除 |
| 13-14 | Python file write | RO/WS | Python 写入控制 |
| 24 | WS: PS bytes write allowed | WS | PowerShell 字节写入 |
| 25 | RO: PS bytes write denied | RO | 禁止 PowerShell 字节写入 |
| 26 | WS: deep mkdir+write | WS | 深层目录创建和写入 |
| 27 | WS: move succeeds | WS | 文件移动 |
| 28 | RO: cmd redirection denied | RO | 命令行重定向禁止 |

#### 网络安全测试 (测试 15-16)

| 测试编号 | 名称 | 策略 | 验证内容 |
|---------|------|------|---------|
| 15 | WS: curl network blocked | WS | 阻止 curl 网络访问 |
| 16 | WS: iwr network blocked | WS | 阻止 PowerShell Invoke-WebRequest |
| 41 | RO: Start-Process https denied | RO | 阻止通过 Start-Process 打开浏览器 |

#### 路径遍历和攻击防护测试 (测试 29-40)

| 测试编号 | 名称 | 策略 | 攻击类型 |
|---------|------|------|---------|
| 29 | WS: junction poisoning via CWD denied | WS | 目录连接点（Junction）攻击 |
| 30 | WS: junction into Windows denied | WS | 通过连接点访问系统目录 |
| 31 | WS: raw device access denied | WS | 原始设备访问（PhysicalDrive0） |
| 32 | WS: ADS write denied | WS | 备用数据流（Alternate Data Stream）写入 |
| 32 | WS: long-path escape denied | WS | 长路径（\\?\）逃逸 |
| 33 | WS: protected path case-variation denied | WS | 大小写变体绕过（.GiT vs .git） |
| 34 | WS: .codex cap_sid tamper denied | WS | 沙箱配置文件篡改 |
| 35 | WS: PATH stub bypass denied | WS | PATH 环境变量欺骗 |
| 36 | WS: symlink race write denied | WS | 符号链接竞争条件 |
| 37 | WS: deep junction/world-writable escape denied | WS | 深层连接点 + 全局可写目录 |
| 38 | WS: workspace-root symlink poisoning denied | WS | 工作区根目录符号链接替换 |
| 39 | WS: UNC link escape denied | WS | UNC 路径（\\localhost\C$）逃逸 |
| 39 | WS: other-drive link escape denied | WS | 其他磁盘（D:\）逃逸 |
| 40 | WS: post-timeout outside write still denied | WS | 超时后的写入仍然受限 |

#### 工具链测试 (测试 18-20)

| 测试编号 | 名称 | 说明 |
|---------|------|------|
| 18 | WS: curl present | 验证 curl 可用 |
| 19 | WS: rg --version | 验证 ripgrep 可用 |
| 20 | WS: git --version | 验证 git 可用 |

### 关键技术实现

#### 目录连接点创建
```python
def make_junction(link: Path, target: Path) -> bool:
    """创建目录连接点（Junction）"""
    cmd = ["cmd", "/c", f'mklink /J "{link}" "{target}"']
    # Junction 是 Windows 的目录符号链接，不需要管理员权限
```

#### 符号链接创建
```python
def make_symlink(link: Path, target: Path) -> bool:
    """创建目录符号链接"""
    cmd = ["cmd", "/c", f'mklink /D "{link}" "{target}"']
    # /D 表示目录符号链接
```

#### 竞争条件测试
```python
# 测试 36: 符号链接竞争
# 后台线程快速切换符号链接目标
toggle = [
    "cmd", "/c",
    f'for /L %i in (1,1,400) do (rmdir flip & mklink /D flip "{inside_abs}" >NUL & rmdir flip & mklink /D flip "{outside_abs}" >NUL)',
]
subprocess.Popen(toggle, ...)  # 后台运行

# 同时尝试写入
rc, out, err = run_sbx("workspace-write", ["cmd", "/c", "echo race > flip\\race.txt"], ...)
```

## 关键代码路径与文件引用

### 调用关系
```
sandbox_smoketests.py
    │
    ├── 调用 codex.exe
    │       └── codex-rs/cli/src/main.rs
    │               └── sandbox windows 子命令
    │                       └── codex-rs/windows-sandbox-rs/src/lib.rs
    │                               └── run_windows_sandbox_capture()
    │
    ├── 间接调用 codex-windows-sandbox-setup.exe
    │       └── 设置 ACL、创建用户
    │
    └── 间接调用 codex-command-runner.exe
            └── 在沙箱中执行命令
```

### 测试目录结构
```
%USERPROFILE%/
├── sbx_ws_tests/           # 主测试工作区 (WS_ROOT)
├── sbx_ws_outside/         # 工作区外目录 (OUTSIDE)
└── WorkspaceRoot/          # 额外可写根目录 (EXTRA_ROOT)
```

### 配置文件覆盖
```python
# 测试额外可写根目录时使用的配置覆盖
overrides = [
    "-c",
    f'sandbox_workspace_write.writable_roots=["{additional_root.as_posix()}"]',
]
```

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 | 必需 |
|------|------|------|
| Python 3.8+ | 测试脚本运行 | 是 |
| codex.exe | Codex CLI | 是 |
| cmd.exe | Windows 命令解释器 | 是 |
| powershell.exe | PowerShell | 是（部分测试） |
| python.exe | Python 解释器 | 是（部分测试） |
| curl.exe | 网络工具 | 否（可选测试 18） |
| rg.exe | ripgrep | 否（可选测试 19） |
| git.exe | Git | 否（可选测试 20） |
| ssh.exe | SSH 客户端 | 否（测试 35） |
| icacls.exe | ACL 工具 | 是（测试 37） |

### Windows 特定功能
- **Junction Points**: `mklink /J`
- **Symbolic Links**: `mklink /D`
- **ACL 修改**: `icacls`
- **环境变量**: `%TEMP%`, `%USERPROFILE%`, `%PATH%`

### 与沙箱的交互
```
sandbox_smoketests.py
    │
    ├── 创建测试目录结构
    │
    ├── 调用 codex sandbox windows
    │       ├── 启动 codex-windows-sandbox-setup（如果需要）
    │       │       └── 配置 ACL
    │       │
    │       └── 启动 codex-command-runner
    │               └── 创建受限 Token
    │               └── 执行测试命令
    │
    └── 验证结果（文件存在性、返回码等）
```

## 风险、边界与改进建议

### 风险点

1. **主机环境依赖**:
   - 测试依赖于主机的 ACL 配置
   - `ro_temp_denied` 探测用于适应不同主机环境
   ```python
   probe_rc, _, _ = run_sbx("read-only", ["cmd", "/c", "echo probe > %TEMP%\\sbx_ro_probe.txt"], WS_ROOT)
   ro_temp_denied = probe_rc != 0
   ```

2. **竞争条件测试的不确定性**:
   - 测试 36（符号链接竞争）是尽力而为（best-effort）
   - 竞争窗口可能错过

3. **可选测试的跳过**:
   - 如果工具未安装，测试会被跳过而非失败
   - 可能掩盖环境配置问题

4. **硬编码超时**:
   ```python
   TIMEOUT_SEC = 20
   ```
   - 在慢速系统上可能不足

### 边界条件

| 场景 | 处理 |
|------|------|
| Codex CLI 未找到 | 抛出 `FileNotFoundError` |
| 测试超时 | `subprocess.TimeoutExpired` |
| 连接点创建失败 | 跳过相关测试 |
| 符号链接创建失败 | 跳过相关测试 |
| 主机允许 TEMP 写入（RO 模式） | 跳过相关测试 |

### 已知失败

测试 41 标记为 **KNOWN FAIL**:
```python
add(
    "RO: Start-Process https denied (KNOWN FAIL)",
    rc != 0,
    f"rc={rc}, stdout={out}, stderr={err}",
)
```
- GUI 逃逸问题尚未修复
- 通过 `Start-Process` 打开浏览器可能绕过沙箱限制

### 改进建议

1. **参数化配置**:
   ```python
   import argparse
   
   parser = argparse.ArgumentParser()
   parser.add_argument("--timeout", type=int, default=20)
   parser.add_argument("--codex-path", type=str)
   parser.add_argument("--skip-network", action="store_true")
   args = parser.parse_args()
   ```

2. **并行测试执行**:
   - 使用 `pytest` 或 `unittest` 框架
   - 支持并行执行加速
   ```python
   # 使用 pytest
   def test_ro_write_denied():
       ...
   
   def test_ws_write_allowed():
       ...
   ```

3. **更详细的日志**:
   ```python
   import logging
   logging.basicConfig(level=logging.DEBUG)
   ```

4. **测试数据清理**:
   ```python
   import atexit
   
   @atexit.register
   def cleanup():
       shutil.rmtree(WS_ROOT, ignore_errors=True)
   ```

5. **结果报告增强**:
   - 生成 JUnit XML 报告
   - 支持 CI 系统集成

6. **环境检查**:
   ```python
   def check_prerequisites():
       assert sys.platform == "win32", "Windows only"
       assert shutil.which("cmd"), "cmd.exe required"
       # ...
   ```

7. **重试机制**:
   ```python
   from functools import wraps
   
   def retry(max_attempts=3):
       def decorator(func):
           @wraps(func)
           def wrapper(*args, **kwargs):
               for i in range(max_attempts):
                   try:
                       return func(*args, **kwargs)
                   except Exception as e:
                       if i == max_attempts - 1:
                           raise
           return wrapper
       return decorator
   ```

8. **测试隔离**:
   - 每个测试使用独立的子目录
   - 避免测试间的相互影响

### 与 CI/CD 集成

建议的 CI 配置：
```yaml
# .github/workflows/windows-sandbox-tests.yml
name: Windows Sandbox Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      - name: Build Codex CLI
        run: cargo build -p codex-cli --release
      - name: Run Smoke Tests
        run: python codex-rs/windows-sandbox-rs/sandbox_smoketests.py
```

### 安全测试覆盖分析

| 攻击向量 | 覆盖状态 | 测试编号 |
|---------|---------|---------|
| 文件写入（CWD） | ✅ | 1-2, 6-7 |
| 文件写入（外部） | ✅ | 3 |
| TEMP 目录写入 | ✅ | 4-5 |
| 网络访问 | ✅ | 15-16, 41 |
| 连接点攻击 | ✅ | 29-30, 37 |
| 符号链接攻击 | ✅ | 36, 38-39 |
| ADS 攻击 | ✅ | 32 |
| 长路径逃逸 | ✅ | 32 |
| 大小写变体绕过 | ✅ | 33 |
| 配置文件篡改 | ✅ | 34 |
| PATH 欺骗 | ✅ | 35 |
| 原始设备访问 | ✅ | 31 |
| 竞争条件 | ✅ | 36 |
| UNC 路径逃逸 | ✅ | 39 |
| 跨磁盘逃逸 | ✅ | 39 |
| 超时后逃逸 | ✅ | 40 |

该测试套件提供了全面的安全覆盖，是验证 Windows 沙箱实现的重要工具。
