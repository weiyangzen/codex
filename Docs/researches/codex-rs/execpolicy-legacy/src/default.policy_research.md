# default.policy 研究文档

## 场景与职责

`default.policy` 是执行策略引擎的默认策略配置文件，使用 Starlark 语言编写。它定义了：

1. **允许执行的程序**：列出可以安全执行的系统命令
2. **程序参数规范**：定义每个程序允许的选项和参数类型
3. **安全约束**：通过 `should_match` 和 `should_not_match` 验证规则正确性
4. **系统路径建议**：提供安全的可执行文件路径

该文件是策略引擎的行为基准，决定了哪些命令被视为安全、需要额外检查或被禁止。

## 功能点目的

### 1. 预定义常量

策略文件使用 `policy_parser.rs` 注入的常量：

| 常量 | 对应 ArgMatcher | 用途 |
|------|----------------|------|
| `ARG_OPAQUE_VALUE` | `OpaqueNonFile` | 非文件参数 |
| `ARG_RFILE` | `ReadableFile` | 单个可读文件 |
| `ARG_WFILE` | `WriteableFile` | 单个可写文件 |
| `ARG_RFILES` | `ReadableFiles` | 一个或多个可读文件 |
| `ARG_RFILES_OR_CWD` | `ReadableFilesOrCwd` | 可读文件或空（暗示 CWD）|
| `ARG_POS_INT` | `PositiveInteger` | 正整数 |
| `ARG_SED_COMMAND` | `SedCommand` | 安全 sed 命令 |
| `ARG_UNVERIFIED_VARARGS` | `UnverifiedVarargs` | 未验证的任意参数 |

### 2. define_program() 参数

```python
define_program(
    program="program_name",           # 程序名
    system_path=["/bin/prog"],        # 推荐的可执行路径
    option_bundling=False,            # 是否支持选项捆绑（如 -al）
    combined_format=False,            # 是否支持 --opt=value 格式
    options=[flag("-a"), opt("-n", ARG_POS_INT)],  # 允许的选项
    args=[ARG_RFILES, ARG_WFILE],     # 位置参数模式
    forbidden="reason",               # 如果匹配，禁止执行的原因
    should_match=[["arg1"]],          # 应该匹配的示例
    should_not_match=[["bad"]],       # 不应该匹配的示例
)
```

### 3. 内置辅助函数

- `flag(name)`：定义无值选项（布尔标志）
- `opt(name, type, required=False)`：定义带值选项

## 具体技术实现

### 策略规则详解

#### ls 命令
```python
define_program(
    program="ls",
    system_path=["/bin/ls", "/usr/bin/ls"],
    options=[
        flag("-1"),
        flag("-a"),
        flag("-l"),
    ],
    args=[ARG_RFILES_OR_CWD],
)
```
- 允许标志：-1, -a, -l
- 参数：零个或多个可读文件（空表示当前目录）
- 安全路径：/bin/ls, /usr/bin/ls

#### cat 命令
```python
define_program(
    program="cat",
    options=[
        flag("-b"),
        flag("-n"),
        flag("-t"),
    ],
    system_path=["/bin/cat", "/usr/bin/cat"],
    args=[ARG_RFILES],
    should_match=[
        ["file.txt"],
        ["-n", "file.txt"],
        ["-b", "file.txt"],
    ],
    should_not_match=[
        [],  # 无参数时从 stdin 读取，不适合当前场景
        ["-l", "file.txt"],  # 不自动批准建议锁
    ]
)
```
- 显式拒绝无参数调用（防止交互式阻塞）
- 拒绝 `-l` 选项（advisory locking）

#### cp 命令
```python
define_program(
    program="cp",
    options=[
        flag("-r"),
        flag("-R"),
        flag("--recursive"),
    ],
    args=[ARG_RFILES, ARG_WFILE],
    system_path=["/bin/cp", "/usr/bin/cp"],
    should_match=[["foo", "bar"]],
    should_not_match=[["foo"]],  # 至少需要两个参数
)
```
- 多源单目标模式
- 需要额外检查（写操作）

#### head 命令
```python
define_program(
    program="head",
    system_path=["/bin/head", "/usr/bin/head"],
    options=[
        opt("-c", ARG_POS_INT),
        opt("-n", ARG_POS_INT),
    ],
    args=[ARG_RFILES],
)
```
- 选项带正整数参数
- 需要一个或多个可读文件

#### printenv 命令（多规则）
```python
# 规则 1：无参数，打印所有环境变量
printenv_system_path = ["/usr/bin/printenv"]
define_program(
    program="printenv",
    args=[],
    system_path=printenv_system_path,
    should_match=[[]],
    should_not_match=[["PATH"]],
)

# 规则 2：单参数，打印特定变量
define_program(
    program="printenv",
    args=[ARG_OPAQUE_VALUE],
    system_path=printenv_system_path,
    should_match=[["PATH"]],
    should_not_match=[[], ["PATH", "HOME"]],
)
```
- 同一程序多个规则，按顺序匹配

#### sed 命令（安全限制）
```python
common_sed_flags = [
    flag("-n"),
    flag("-u"),
]
sed_system_path = ["/usr/bin/sed"]

# 规则 1：第一个参数是 sed 命令
define_program(
    program="sed",
    options=common_sed_flags,
    args=[ARG_SED_COMMAND, ARG_RFILES],
    system_path=sed_system_path,
)

# 规则 2：-e 选项指定命令
define_program(
    program="sed",
    options=common_sed_flags + [
        opt("-e", ARG_SED_COMMAND, required=True),
    ],
    args=[ARG_RFILES],
    system_path=sed_system_path,
)
```
- 不支持 `-i`（原地编辑）和 `-f`（脚本文件）
- `ARG_SED_COMMAND` 只验证安全的打印命令（如 `122,202p`）
- 防止 GNU sed 的 `e` 标志执行任意命令

#### rg (ripgrep) 命令
```python
define_program(
    program="rg",
    options=[
        opt("-A", ARG_POS_INT),
        opt("-B", ARG_POS_INT),
        opt("-C", ARG_POS_INT),
        opt("-d", ARG_POS_INT),
        opt("--max-depth", ARG_POS_INT),
        opt("-g", ARG_OPAQUE_VALUE),
        opt("--glob", ARG_OPAQUE_VALUE),
        opt("-m", ARG_POS_INT),
        opt("--max-count", ARG_POS_INT),
        flag("-n"),
        flag("-i"),
        flag("-l"),
        flag("--files"),
        flag("--files-with-matches"),
        flag("--files-without-match"),
    ],
    args=[ARG_OPAQUE_VALUE, ARG_RFILES_OR_CWD],
    should_match=[
        ["-n", "init"],
        ["-n", "init", "."],
        ["-i", "-n", "init", "src"],
        ["--files", "--max-depth", "2", "."],
    ],
    should_not_match=[
        ["-m", "-n", "init"],  # -m 需要值
        ["--glob", "src"],     # --glob 需要值
    ],
    system_path=[],  # 期望使用捆绑版本
)
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/execpolicy-legacy/src/default.policy`

### 相关文件
- `codex-rs/execpolicy-legacy/src/policy_parser.rs`：解析策略文件
- `codex-rs/execpolicy-legacy/src/lib.rs`：通过 `include_str!` 嵌入

### 加载流程

```
lib.rs:get_default_policy()
  └── include_str!("default.policy")  // 编译时嵌入
      └── PolicyParser::new("#default", DEFAULT_POLICY)
          └── parse()
              ├── 注册 ARG_* 常量到 Starlark 模块
              ├── 执行策略文件
              │   └── define_program() 等内置函数
              │       └── PolicyBuilder 收集规则
              └── PolicyBuilder::build()
                  └── 创建 Policy 实例
```

### 验证流程

```
tests/suite/good.rs
  └── get_default_policy()
      └── policy.check_each_good_list_individually()
          └── 对每个 should_match 示例调用 ProgramSpec::check()

tests/suite/bad.rs
  └── get_default_policy()
      └── policy.check_each_bad_list_individually()
          └── 对每个 should_not_match 示例验证失败
```

## 依赖与外部交互

### 内部依赖
- `policy_parser.rs`：提供 Starlark 内置函数
- `lib.rs`：嵌入策略文件内容

### 测试依赖
- `tests/suite/*.rs`：验证策略规则

## 风险、边界与改进建议

### 风险点

1. **sed 安全性**
   - 当前只支持 `122,202p` 格式的打印命令
   - GNU sed 的 `e` 标志可执行任意命令
   - 注释中提到：
     ```shell
     $ yes | head -n 4 > /tmp/yes.txt
     $ sed 's/y/echo hi/e' /tmp/yes.txt
     hi
     hi
     hi
     hi
     ```

2. **rg 无系统路径**
   - `system_path=[]` 表示期望使用捆绑版本
   - 如果系统版本被使用，可能有不同的行为

3. **选项捆绑未实现**
   - `option_bundling` 标记为 PLANNED
   - `ls -al` 当前会失败

4. **cat 无参数被拒绝**
   - 从 stdin 读取在某些场景下是合理的
   - 当前策略过于保守

### 边界情况

1. **多规则匹配顺序**
   - printenv 有两个规则，按定义顺序匹配
   - 第一个匹配的规则生效

2. **路径优先级**
   - `system_path` 是有序列表
   - 第一个存在的可执行文件被使用

3. **should_not_match 验证**
   - 确保不应该匹配的规则确实不匹配
   - 防止过于宽松的规则

### 改进建议

1. **扩展 sed 支持**
   ```python
   # 添加更多安全的 sed 命令模式
   # 如：s/pattern/replacement/（无 e 标志）
   # 如：d（删除行）
   ```

2. **实现选项捆绑**
   ```python
   define_program(
       program="ls",
       option_bundling=True,  # 启用 -al 支持
       # ...
   )
   ```

3. **添加更多常用命令**
   ```python
   # find（受限版本）
   # grep
   # awk（受限版本）
   # xargs（受限版本）
   ```

4. **细化 cat 策略**
   ```python
   # 允许无参数，但标记为需要 stdin 检查
   define_program(
       program="cat",
       args=[ARG_RFILES_OR_STDIN],  # 新类型
       # ...
   )
   ```

5. **添加注释和文档**
   ```python
   # 说明每个规则的安全考量
   # 记录已知限制
   ```

6. **策略版本控制**
   ```python
   # 添加版本信息
   policy_version = "1.0.0"
   policy_compat = ["0.9.x"]
   ```

7. **动态策略加载**
   - 当前策略编译时嵌入
   - 考虑支持运行时加载（用于测试和扩展）
