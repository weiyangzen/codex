# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/001_add_file` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/001_add_file`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

`001_add_file` 是 `apply_patch` fixture 体系中的最小“新增文件”场景，用来验证补丁协议中 `*** Add File` 的基础语义是否稳定成立。

该目录只包含两类资产：

1. 输入补丁：`patch.txt`（`codex-rs/apply-patch/tests/fixtures/scenarios/001_add_file/patch.txt:1-4`）。
2. 预期结果：`expected/bar.md`（`codex-rs/apply-patch/tests/fixtures/scenarios/001_add_file/expected/bar.md:1`）。

它的职责不是覆盖复杂边界，而是作为整个场景集的“基线样例”：

1. 证明 parser 能正确识别 Add hunk。
2. 证明执行器会创建文件并写入带末尾换行的内容。
3. 证明场景回放器（`tests/suite/scenarios.rs`）能在“无 input/ 目录”的情况下正确比较最终文件树。

上层规范文档将该类目录定义为 `input/`（可选）+ `patch.txt` + `expected/` 的三段式结构（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`）。`001_add_file` 选择了其中最小形态：无 `input/`，只验证 patch 产生新文件。

## 功能点目的

### 1) 直接功能目的（针对本目录）

1. 验证 `*** Add File: bar.md` 能在空工作目录创建目标文件（`patch.txt:2`）。
2. 验证 `+This is a new file` 被写入后，与 `expected/bar.md` 完整一致（`patch.txt:3`，`expected/bar.md:1`）。
3. 验证回放器在不关心 stdout/stderr 的前提下，仅用文件树快照判断成功（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-58`）。

### 2) 在全场景集中的定位

1. `001_*` 作为编号最早场景，承担“最简单成功路径 smoke test”角色。
2. 它与 `011_add_overwrites_existing_file` 形成互补：
- `001` 覆盖“目标文件原本不存在”；
- `011` 覆盖“Add 覆盖已存在文件”（`codex-rs/apply-patch/tests/suite/tool.rs:177-193` 与 fixture `011_*`）。

### 3) 与其它测试层的职责分工

1. `001_add_file`（fixture 场景）关注最终文件树状态。
2. `tests/suite/cli.rs` 中 `test_apply_patch_cli_add_and_update` 额外关注 CLI 输出文本 `A <file>`（`codex-rs/apply-patch/tests/suite/cli.rs:17-31`）。
3. `src/lib.rs` 单元测试 `test_add_file_hunk_creates_file_with_contents` 关注函数级输出与内容（`codex-rs/apply-patch/src/lib.rs:568-591`）。

三层共同覆盖“Add File”语义：协议样例层、CLI 行为层、库函数层。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程（从本目录到最终断言）

1. `test_apply_patch_scenarios()` 遍历 `tests/fixtures/scenarios` 下所有子目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. 对 `001_add_file` 调用 `run_apply_patch_scenario()`：
- 检查 `input/`，本目录不存在则跳过复制（`scenarios.rs:34-37`）；
- 读取 `patch.txt`（`scenarios.rs:39-40`）；
- 在 `tempdir` 执行 `apply_patch <patch>`（`scenarios.rs:45-48`）；
- 比较 `expected/` 与临时目录的快照（`scenarios.rs:50-58`）。
3. 快照结构为 `BTreeMap<PathBuf, Entry>`，其中 `Entry::File(Vec<u8>)` 按字节比较，避免文本编码假设（`scenarios.rs:65-77`）。

### 2) Add File 的解析与执行细节

1. 解析层：`parse_one_hunk()` 识别 `*** Add File: ` 前缀，并将所有 `+` 行拼接为 `contents`（每行补 `\n`）（`codex-rs/apply-patch/src/parser.rs:251-270`）。
2. 语法入口：`parse_patch()` 默认走 Lenient 模式（`PARSE_IN_STRICT_MODE=false`），但本场景补丁本身是严格合法格式（`parser.rs:47,106-113,154-183`）。
3. 执行层：`apply_hunks_to_files()` 的 `Hunk::AddFile` 分支会：
- 必要时创建父目录；
- `std::fs::write(path, contents)` 写盘；
- 把路径记录到 `affected.added`（`codex-rs/apply-patch/src/lib.rs:289-300`）。
4. 输出层：`print_summary()` 把新增文件以 `A path` 输出（`lib.rs:541-544`）。

### 3) 协议与命令

1. 协议包裹：`*** Begin Patch` / `*** End Patch`（`patch.txt:1,4`；`parser.rs:31-32,233-243`）。
2. 操作头：`*** Add File: bar.md`（`patch.txt:2`；`parser.rs:33,251-270`）。
3. Add 内容行：必须是 `+` 前缀（`patch.txt:3`；语法文档 `codex-rs/apply-patch/apply_patch_tool_instructions.md`）。
4. 运行命令（测试中实际调用）：`apply_patch "<完整 patch 文本>"`（`scenarios.rs:45-47`）。

### 4) 上游工具链中的同语义路径

1. `core` 的 `ApplyPatchHandler` 会先 `maybe_parse_apply_patch_verified`，再决定直接输出或委托运行时执行（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-239`）。
2. 运行时构造 `codex --codex-run-as-apply-patch <patch>` 命令执行（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-101`）。
3. `arg0` 收到 `--codex-run-as-apply-patch` 后直接调用 `codex_apply_patch::apply_patch`（`codex-rs/arg0/src/lib.rs:89-107`）。

这说明 `001_add_file` 虽然位于测试夹具目录，但覆盖的 Add 语义与生产链路一致。

## 关键代码路径与文件引用

### A. 目标目录本体

1. `codex-rs/apply-patch/tests/fixtures/scenarios/001_add_file/patch.txt:1-4`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/001_add_file/expected/bar.md:1`

### B. 直接调用方（谁消费该目录）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`（遍历场景目录）。
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:30-60`（执行并比较快照）。
3. `codex-rs/apply-patch/tests/all.rs:1-3` 与 `codex-rs/apply-patch/tests/suite/mod.rs:1-3`（测试聚合入口）。

### C. 被调用方（场景执行时触发的实现）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`（CLI 参数/stdin 与退出码）。
2. `codex-rs/apply-patch/src/lib.rs:183-213`（`apply_patch` 入口）。
3. `codex-rs/apply-patch/src/lib.rs:279-300`（Add File 写盘）。
4. `codex-rs/apply-patch/src/lib.rs:537-551`（成功摘要 `A <path>`）。
5. `codex-rs/apply-patch/src/parser.rs:248-270`（Add hunk 解析）。

### D. 配置、文档、脚本上下文

1. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`（fixture 结构定义）。
2. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`（统一 LF）。
3. `codex-rs/apply-patch/apply_patch_tool_instructions.md`（补丁语言规范）。
4. `codex-rs/apply-patch/Cargo.toml:1-30`（crate/bin 与测试依赖）。
5. `codex-rs/apply-patch/BUILD.bazel:1-11`（Bazel compile_data）。
6. `.ops/generate_daily_research_todo.sh:5-7,15-18,33-39`（从 checklist 生成每日 TODO）。
7. `Docs/researches/blueprint_checklist.md:74`（本目录研究勾选条目）。

## 依赖与外部交互

### 1) 代码依赖

1. `codex-utils-cargo-bin`：在测试中解析 `repo_root()` 与 `cargo_bin("apply_patch")`（`scenarios.rs:1,12,45`）。
2. `tempfile`：为每个场景提供独立临时目录（`scenarios.rs:8,31`）。
3. `pretty_assertions`：目录快照比较失败时提供可读 diff（`scenarios.rs:2,55-58`）。
4. `assert_cmd`：在 `cli/tool` 测试模块用于执行并断言进程行为（`cli.rs:1`，`tool.rs:1`）。

### 2) 外部交互面

1. 文件系统：创建临时目录、读取 `patch.txt`、写入 `bar.md`、读取 `expected/` 快照。
2. 进程：每个场景拉起一次 `apply_patch` 可执行文件。
3. 平台差异处理：快照与拷贝使用 `fs::metadata()` 跟随符号链接，兼容 Buck2 下 `__srcs` 的 symlink 形态（`scenarios.rs:92-95,113-114`）。

### 3) 协议/接口约束

1. path 必须相对路径（规范文档要求），本场景使用 `bar.md`（`apply_patch_tool_instructions.md`）。
2. Add 文件内容通过 `+` 行定义，本场景只有一行，最终文件仍由引擎补全末尾换行。

## 风险、边界与改进建议

### 风险与边界

1. 场景只比最终文件树，不断言退出码与 stdout/stderr（`scenarios.rs:42-45`）。如果未来输出文案退化而文件状态仍正确，该场景不会报警。
2. 本场景无 `input/`，未验证“目录已存在/权限受限/同名冲突”等真实环境变量。
3. `Add File` 在实现上是 `std::fs::write` 覆盖写入（`lib.rs:297-299`），对“已存在文件时是否应拒绝”采用的是覆盖语义；该设计由 `011_add_overwrites_existing_file` 佐证，但可能与部分用户直觉不一致。
4. `test_apply_patch_scenarios` 未排序遍历目录（`scenarios.rs:18`），失败时日志顺序受文件系统返回顺序影响。

### 改进建议

1. 为场景机制增加可选元数据（例如 `expect_exit`、`expect_stdout_contains`），在保持“最终态断言”优点的同时补齐行为断言。
2. 在 `001_add_file` 增补子用例或新编号场景：
- `Add File` 到多级目录（验证父目录创建）；
- `Add File` 空内容（验证空文件语义）；
- `Add File` 含 Unicode 与末尾空行（验证编码/换行一致性）。
3. 对 `test_apply_patch_scenarios` 先按目录名排序再执行，提升复现稳定性。
4. 在 `scenarios/README.md` 中显式声明“`001_*` 为最小基线场景”，降低维护者对覆盖范围的误解。

