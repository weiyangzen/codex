# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header/input` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header/input`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 目录内容：`foo.txt`

## 场景与职责

该目录是场景 `013_rejects_invalid_hunk_header` 的输入快照目录，用于提供补丁执行前的最小文件系统状态。目录中只有一个文件：

1. `foo.txt`，内容为 `stable`（`codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header/input/foo.txt:1`）。

同场景补丁故意使用非法 hunk header：

1. `*** Frobnicate File: foo`（`codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header/patch.txt:2`）。

因此本目录的核心职责是作为“失败前状态基线”，让测试验证以下事实：

1. 解析器会拒绝非法 hunk header；
2. 补丁失败后不应产生写盘副作用；
3. `actual` 目录应与 `expected/foo.txt` 保持一致（`stable`，`codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header/expected/foo.txt:1`）。

## 功能点目的

围绕该 `input/` 目录，场景要锁定的功能点是“语法错误快速失败 + 文件状态不变”：

1. 协议层只允许三类文件级 header：`*** Add File`、`*** Delete File`、`*** Update File`（`codex-rs/apply-patch/apply_patch_tool_instructions.md:12-17`）。
2. 未知 header 必须返回 `InvalidHunkError`，并给出合法 header 列表（`codex-rs/apply-patch/src/parser.rs:335-340`）。
3. CLI 应输出定位信息 `Invalid patch hunk on line ...`（`codex-rs/apply-patch/src/lib.rs:195-203`）。
4. 失败路径不进入 `apply_hunks` 执行落盘（`codex-rs/apply-patch/src/lib.rs:188-210`）。

`input/foo.txt` 的存在是必要前置条件：它排除了“文件不存在”这一干扰因素，使失败原因稳定锁定在“非法 header 语法”。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景执行流程（调用方）

`test_apply_patch_scenarios` 会遍历 `fixtures/scenarios`，逐个执行目录场景（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。  
单个目录由 `run_apply_patch_scenario` 驱动：

1. 复制 `input/` 到临时目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-37`）；
2. 读取 `patch.txt` 并执行 `apply_patch <patch>` 子进程（`codex-rs/apply-patch/tests/suite/scenarios.rs:39-48`）；
3. 对临时目录和 `expected/` 建立递归快照比较（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`）。

这里的关键实现细节是：场景 runner 故意不校验退出码，仅按最终文件树断言（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-45`）。因此本目录承担“副作用边界断言”角色。

### 2) 解析失败路径（被调用方）

解析入口：`apply_patch()` -> `parse_patch()`（`codex-rs/apply-patch/src/lib.rs:183-190`）。  
`parse_one_hunk` 对首行依次尝试三种 marker（`codex-rs/apply-patch/src/parser.rs:248-333`），均不匹配时返回：

1. `ParseError::InvalidHunkError`；
2. message：`'{first_line}' is not a valid hunk header ...`；
3. `line_number` 由外层循环计算（该场景为第 2 行）。

这与 `tool.rs` 的精确 stderr 断言保持一致（`codex-rs/apply-patch/tests/suite/tool.rs:210-218`）。

### 3) 数据结构与错误传播

关键结构：

1. `ApplyPatchArgs { patch, hunks, workdir }`（`codex-rs/apply-patch/src/lib.rs:85-90`）；
2. `Hunk::{AddFile, DeleteFile, UpdateFile}`（`codex-rs/apply-patch/src/parser.rs:59-76`）；
3. `ParseError::{InvalidPatchError, InvalidHunkError}`（`codex-rs/apply-patch/src/parser.rs:49-55`）；
4. 场景快照结构 `BTreeMap<PathBuf, Entry>`（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-77`）。

错误传播链：

1. `parse_one_hunk` 产出 `InvalidHunkError`；
2. `apply_patch` 写 stderr 并返回 `ApplyPatchError::ParseError`（`codex-rs/apply-patch/src/lib.rs:191-207`）；
3. `run_main` 捕获错误并返回退出码 `1`（`codex-rs/apply-patch/src/standalone_executable.rs:51-58`）。

### 4) 协议/命令与上游工具链

协议来源：

1. fixtures 协议：`input/ + patch.txt + expected/`（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-7`）；
2. apply_patch 语法与 header 约束（`codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`）。

上游调用链（core）：

1. handler 先做 `maybe_parse_apply_patch_verified` 预检（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-175`）；
2. 预检失败返回 `apply_patch verification failed: ...`（`codex-rs/core/src/tools/handlers/apply_patch.rs:241-244`）；
3. runtime 使用 `codex --codex-run-as-apply-patch` 执行（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-93`）；
4. arg0 分发到 `codex_apply_patch::apply_patch`（`codex-rs/arg0/src/lib.rs:90-99`）。

复现命令：

```bash
apply_patch "*** Begin Patch
*** Frobnicate File: foo
*** End Patch"
```

## 关键代码路径与文件引用

1. 目标目录输入文件：`codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header/input/foo.txt:1`
2. 同场景补丁：`codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header/patch.txt:1-3`
3. 同场景期望：`codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header/expected/foo.txt:1`
4. 场景协议文档：`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-7`
5. 场景驱动测试：`codex-rs/apply-patch/tests/suite/scenarios.rs:11-60`
6. CLI 负向断言：`codex-rs/apply-patch/tests/suite/tool.rs:210-218`
7. parser header 分派与错误：`codex-rs/apply-patch/src/parser.rs:248-340`
8. parser 对无效 header 的单测：`codex-rs/apply-patch/src/parser.rs:673-681`
9. 解析错误到 stderr 的格式化：`codex-rs/apply-patch/src/lib.rs:191-203`
10. CLI 退出码路径：`codex-rs/apply-patch/src/standalone_executable.rs:11-58`
11. crate 依赖配置：`codex-rs/apply-patch/Cargo.toml:1-30`
12. Bazel compile_data：`codex-rs/apply-patch/BUILD.bazel:3-10`
13. daily todo 生成脚本：`.ops/generate_daily_research_todo.sh:1-42`
14. checklist 对应条目：`Docs/researches/blueprint_checklist.md:124`

## 依赖与外部交互

### 依赖

1. 运行时依赖：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. 测试依赖：`assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`codex-rs/apply-patch/Cargo.toml:25-30`）。

### 外部交互

1. 文件系统：场景框架复制 `input/`，执行后比较 `actual`/`expected` 快照（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-37,50-60`）。
2. 子进程：通过 `cargo_bin("apply_patch")` 启动可执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
3. 标准流：无效 header 报错走 stderr（`codex-rs/apply-patch/src/lib.rs:199-203`）。
4. 上游交互：core 在执行前预检 patch 语义（`codex-rs/core/src/tools/handlers/apply_patch.rs:174,241-244`）。

## 风险、边界与改进建议

### 风险

1. fixture runner 不断言 stderr/exit code；若错误文案回归，仅靠该 `input/` 场景无法发现（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-45`）。
2. 当前场景仅覆盖“完全未知 header”，对大小写偏差、多空格、近似拼写覆盖不足。
3. 错误文案中合法 header 列表是字符串拼接，未来扩展 header 时存在同步遗漏风险。

### 边界

1. 本目录验证的是“解析失败导致文件状态不变”，不直接验证审批、沙箱、权限路径。
2. 输入体量极小（单文件单行），不覆盖多文件/深目录对失败回滚观测的复杂度。

### 改进建议

1. 为场景框架增加可选 `stderr` 和 `exit_code` 断言文件，补齐负向可观测性。
2. 新增“近似非法 header”场景（大小写错误、额外空格、拼写相近）形成语法矩阵。
3. 将合法 header 列表提示改为基于 marker 常量生成，减少协议与错误文案漂移。
4. 在 `scenarios/README.md` 增补“负向场景建议同时在 tool.rs 断言错误文案”的约定。
