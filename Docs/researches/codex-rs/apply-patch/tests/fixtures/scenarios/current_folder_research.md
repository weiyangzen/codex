# DIR `codex-rs/apply-patch/tests/fixtures/scenarios` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

该目录是 `apply_patch` 端到端规范样例库，不是执行逻辑本体。它的核心职责是把补丁语义沉淀为“可移植、可回放、可比对”的夹具（fixture），供集成测试稳定验证。

1. 规范承载：每个子目录表达一个单独场景，统一结构为 `input/`（可选）、`patch.txt`、`expected/`（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-17`）。
2. 回归基线：`tests/suite/scenarios.rs` 逐目录执行 patch 并仅比较最终文件树状态，避免测试逻辑与断言逻辑耦合（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-58`）。
3. 跨实现可复用：README 明确该目录面向“可移植到其他语言/平台”的规范测试集（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:2`）。

该目录当前有 23 个场景目录（含两个 `020_*`），覆盖 add/delete/update/move、多 chunk、失败路径、whitespace 容忍、Unicode、EOF 标记等行为边界。

## 功能点目的

### 1) 目录级规范约束

1. 统一换行：`.gitattributes` 强制 `** text eol=lf`，减少 CRLF/平台差异导致的快照噪声（`codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`）。
2. 场景最小化：一个目录只承载一段 `patch.txt` 与对应期望状态，避免多 patch 串联造成定位困难。

### 2) 场景覆盖意图（按语义分组）

1. 基础成功路径：
- `001_add_file`
- `002_multiple_operations`
- `003_multiple_chunks`
- `004_move_to_new_directory`
- `020_delete_file_success`

2. 失败与错误语义：
- `005_rejects_empty_patch`
- `006_rejects_missing_context`
- `007_rejects_missing_file_delete`
- `008_rejects_empty_update_hunk`
- `009_requires_existing_file_for_update`
- `012_delete_directory_fails`
- `013_rejects_invalid_hunk_header`

3. 行为边界与兼容性：
- 覆盖策略：`010_move_overwrites_existing_destination`、`011_add_overwrites_existing_file`
- 非事务语义：`015_failure_after_partial_success_leaves_changes`
- 内容格式：`014_update_file_appends_trailing_newline`、`016_pure_addition_update_chunk`、`021_update_file_deletion_only`、`022_update_file_end_of_file_marker`
- 解析宽容：`017_whitespace_padded_hunk_header`、`018_whitespace_padded_patch_markers`、`020_whitespace_padded_patch_marker_lines`
- 字符编码：`019_unicode_simple`

### 3) 与同 crate 其他测试的职责分工

1. `tests/suite/cli.rs`：验证 argv/stdin 与成功输出格式。
2. `tests/suite/tool.rs`：验证明确错误文案与退出码。
3. 本目录 + `tests/suite/scenarios.rs`：以数据驱动方式校验最终文件树，强调“语义最终态”而非输出文案。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程（从 fixture 到断言）

1. 入口：`test_apply_patch_scenarios()` 通过 `repo_root()` 定位 `tests/fixtures/scenarios` 后逐目录遍历（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`，`codex-rs/utils/cargo-bin/src/lib.rs:168-202`）。
2. 准备输入：若存在 `input/`，递归复制到 `tempdir()`（`codex-rs/apply-patch/tests/suite/scenarios.rs:31-35,107-126`）。
3. 执行 patch：读取 `patch.txt` 并执行命令：
   `apply_patch "<patch-body>"`（`codex-rs/apply-patch/tests/suite/scenarios.rs:37-46`）。
4. 快照比较：对 `expected/` 与实际临时目录分别构建目录快照（`BTreeMap<PathBuf, Entry>`）并做深比较（`codex-rs/apply-patch/tests/suite/scenarios.rs:48-58,65-105`）。
5. 平台兼容：快照与复制都用 `fs::metadata()` 跟随 symlink，兼容 Buck2 `__srcs` 场景（`codex-rs/apply-patch/tests/suite/scenarios.rs:89-95,113-118`）。

### 2) 核心数据结构

1. `Entry`：
- `File(Vec<u8>)`：按字节比较文件内容（避免文本编码假设）
- `Dir`：显式记录目录节点

2. `snapshot_dir()`：
- 返回 `BTreeMap<PathBuf, Entry>`，天然稳定排序，避免哈希迭代顺序波动。

### 3) 场景协议与补丁语法

1. fixture 协议：`input/ + patch.txt + expected/`（README）。
2. patch 协议：
- 包裹标记：`*** Begin Patch` / `*** End Patch`
- 操作头：`*** Add File` / `*** Delete File` / `*** Update File`
- Update 细节：`@@` chunk、可选 `*** Move to`、可选 `*** End of File`
（`codex-rs/apply-patch/apply_patch_tool_instructions.md:1-72`，`codex-rs/apply-patch/src/parser.rs:6-21`）。

### 4) 关键命令

1. 场景回放：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 本目录样例中的被测命令：`apply_patch '<完整 patch 文本>'`

## 关键代码路径与文件引用

### A. 目标目录与规范文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/*/patch.txt`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/*/input/**`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/*/expected/**`

### B. 直接调用方（谁消费该目录）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-58`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-3`
3. `codex-rs/apply-patch/tests/all.rs:1-3`

### C. 被调用方（场景回放时实际执行）

1. 二进制入口：`codex-rs/apply-patch/src/main.rs:1-3`
2. CLI 参数逻辑：`codex-rs/apply-patch/src/standalone_executable.rs:11-58`
3. 补丁执行主入口：`codex-rs/apply-patch/src/lib.rs:183-266`
4. 文件落盘逻辑：`codex-rs/apply-patch/src/lib.rs:279-339`
5. 解析逻辑：`codex-rs/apply-patch/src/parser.rs:106-434`
6. 行匹配策略：`codex-rs/apply-patch/src/seek_sequence.rs:12-110`

### D. 上下文测试与文档

1. `codex-rs/apply-patch/tests/suite/tool.rs`（错误消息/退出码导向验证）
2. `codex-rs/apply-patch/tests/suite/cli.rs`（CLI 参数/标准输入导向验证）
3. `codex-rs/apply-patch/apply_patch_tool_instructions.md`
4. `Docs/researches/codex-rs/apply-patch/tests/current_folder_research.md`（上层 tests 目录研究）

## 依赖与外部交互

### 1) 代码依赖

1. `tempfile`：临时目录隔离。
2. `assert_cmd`：进程调用与断言基础。
3. `codex-utils-cargo-bin`：`cargo_bin("apply_patch")` 与 `repo_root()` 解析，兼容 Cargo/Bazel。
4. `pretty_assertions`：目录快照断言差异可读化。

### 2) 外部交互

1. 文件系统：递归复制 `input`、执行 patch 写盘、递归读取目录生成快照。
2. 进程：每个场景都会拉起 `apply_patch` 子进程。
3. 运行环境：
- 通过 `repo_root.marker` 与 runfiles 机制定位仓库根目录。
- 通过 `metadata()` 跟随符号链接以适配 Buck2。

### 3) 配置与脚本关联

1. 本目录本身无运行时配置文件；其行为由 `parser/lib` 实现决定。
2. 研究流程相关脚本：`.ops/generate_daily_research_todo.sh` 会基于 `Docs/researches/blueprint_checklist.md` 生成当日 todo。

## 风险、边界与改进建议

### 风险与边界

1. `scenarios.rs` 不断言 exit status/stdout/stderr，仅比较最终文件树；输出文案回归可能漏检（`codex-rs/apply-patch/tests/suite/scenarios.rs:43-45`）。
2. `read_dir` 未排序，场景执行顺序依赖文件系统返回顺序，失败日志可读性和复现体验不稳定。
3. 场景编号存在双 `020_*`，长期维护时容易引发“编号即顺序”的误解。
4. 当前场景未覆盖权限类/只读文件/路径穿越等高风险 I/O 边界。
5. 未覆盖超大补丁与大文件下的性能回归（`apply_replacements` 为基于 `Vec` 的 remove/insert 策略）。

### 改进建议

1. 在 `scenarios.rs` 增加可选断言元数据（例如 `expect_exit`, `expect_stderr_contains`），保留现有最终态断言同时覆盖关键错误通路。
2. 在遍历场景前按目录名排序，稳定 CI 输出与本地复现。
3. 为场景补充 `SCENARIO_INDEX.md`（编号、语义标签、对应实现模块），降低认知成本。
4. 新增安全/边界场景：
- 删除目录符号链接、只读文件写入失败
- 含 `..` 的路径输入
- 超大文件多 chunk 更新
5. 统一场景编号策略（将第二个 `020_*` 后移为 `023_*` 或引入语义前缀），减少维护歧义。
