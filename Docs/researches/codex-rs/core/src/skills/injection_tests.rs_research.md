# injection_tests.rs 研究文档

## 场景与职责

`injection_tests.rs` 是 `injection.rs` 模块的**单元测试文件**，负责验证技能注入系统的核心功能。测试覆盖以下关键场景：

1. **技能提及解析**：验证 `$skill-name` 语法和链接语法的正确解析
2. **歧义处理**：验证同名技能、connector 冲突等边界情况的处理
3. **优先级规则**：验证结构化输入优先于文本输入、路径优先于名称等规则
4. **去重逻辑**：验证重复提及的处理
5. **边界匹配**：验证技能名称的边界检测（前缀/后缀匹配）

该测试文件确保技能注入逻辑在各种复杂场景下的正确性和稳定性。

## 功能点目的

### 测试辅助函数

#### `make_skill` - 技能元数据工厂
```rust
fn make_skill(name: &str, path: &str) -> SkillMetadata
```
快速创建测试用的 `SkillMetadata` 实例，填充必要的默认值。

#### `set` - HashSet 构建器
```rust
fn set<'a>(items: &'a [&'a str]) -> HashSet<&'a str>
```
便捷地从字符串切片创建 HashSet，用于断言期望的提及集合。

#### `assert_mentions` - 提及断言
```rust
fn assert_mentions(text: &str, expected_names: &[&str], expected_paths: &[&str])
```
封装 `extract_tool_mentions` 调用和断言逻辑，简化测试编写。

#### `collect_mentions` - 提及收集包装
```rust
fn collect_mentions(...) -> Vec<SkillMetadata>
```
包装 `collect_explicit_skill_mentions` 函数，简化参数传递。

### 核心测试用例

#### 1. 边界匹配测试
- `text_mentions_skill_requires_exact_boundary`: 验证精确边界匹配
  - `$notion-research-doc` 匹配 `notion-research-doc` ✓
  - `$notion-research-docs` 不匹配 `notion-research-doc` ✓
  - `$notion-research-doc_extra` 不匹配 `notion-research-doc` ✓

- `text_mentions_skill_handles_end_boundary_and_near_misses`: 验证结尾边界
  - `$alpha-skillx` 不匹配 `alpha-skill`
  - 支持从长文本中提取正确的提及

- `text_mentions_skill_handles_many_dollars_without_looping`: 验证性能
  - 256 个连续 `$` 符号不会导致无限循环或性能问题

#### 2. 提及提取测试
- `extract_tool_mentions_handles_plain_and_linked_mentions`: 基础功能
  - 同时处理纯文本 `$alpha` 和链接 `[$beta](/tmp/beta)`

- `extract_tool_mentions_skips_common_env_vars`: 环境变量过滤
  - `$PATH`, `$HOME`, `$XDG_CONFIG_HOME` 等被正确过滤

- `extract_tool_mentions_requires_link_syntax`: 链接语法严格性
  - `[beta](/tmp/beta)` 缺少 `$` 符号，不被识别
  - `[$beta] /tmp/beta` 缺少括号，路径不被识别
  - `[$beta]()` 空路径不被识别

- `extract_tool_mentions_trims_linked_paths_and_allows_spacing`: 空白处理
  - 支持 `[$beta]   ( /tmp/beta )` 形式的额外空白

- `extract_tool_mentions_stops_at_non_name_chars`: 字符边界
  - `$alpha.skill` 只提取 `alpha`，点号终止名称

- `extract_tool_mentions_keeps_plugin_skill_namespaces`: 命名空间支持
  - `$slack:search` 完整保留冒号和后续内容

#### 3. 技能选择测试
- `collect_explicit_skill_mentions_text_respects_skill_order`: 顺序保持
  - 文本扫描不改变技能在列表中的原始顺序

- `collect_explicit_skill_mentions_prioritizes_structured_inputs`: 结构化优先
  - `UserInput::Skill` 优先于 `UserInput::Text`
  - 结构化输入的技能排在列表前面

- `collect_explicit_skill_mentions_skips_invalid_structured_and_blocks_plain_fallback`: 无效结构化输入处理
  - 无效路径的结构化输入会阻止同名技能的文本回退

- `collect_explicit_skill_mentions_skips_disabled_structured_and_blocks_plain_fallback`: 禁用技能处理
  - 被禁用的结构化输入同样阻止文本回退

#### 4. 去重和歧义处理测试
- `collect_explicit_skill_mentions_dedupes_by_path`: 路径去重
  - 相同路径的多次提及只保留一个

- `collect_explicit_skill_mentions_skips_ambiguous_name`: 歧义名称跳过
  - 同名技能存在多个时，纯名称提及被跳过

- `collect_explicit_skill_mentions_prefers_linked_path_over_name`: 路径优先
  - 链接路径匹配优先于名称匹配
  - 即使有歧义名称，路径匹配仍可成功

#### 5. Connector 冲突测试
- `collect_explicit_skill_mentions_skips_plain_name_when_connector_matches`: Connector 优先
  - 如果 connector slug 与技能名称冲突，纯名称提及被跳过

- `collect_explicit_skill_mentions_allows_explicit_path_with_connector_conflict`: 路径绕过冲突
  - 使用链接路径语法可以绕过 connector 冲突

#### 6. 禁用路径测试
- `collect_explicit_skill_mentions_skips_when_linked_path_disabled`: 禁用路径过滤
  - 链接指向被禁用的技能路径时，该提及被跳过

- `collect_explicit_skill_mentions_prefers_resource_path`: 资源路径优先
  - 验证资源路径匹配的优先级

- `collect_explicit_skill_mentions_skips_missing_path_with_no_fallback`: 缺失路径处理
  - 链接指向不存在的路径，且无其他匹配时，返回空

## 具体技术实现

### 测试模式
使用 `pretty_assertions::assert_eq` 提供清晰的测试失败差异对比：
```rust
use pretty_assertions::assert_eq;
```

### 测试组织结构
- 每个测试函数聚焦单一行为
- 使用描述性命名：`{被测功能}_{场景}_{期望结果}`
- 使用 `assert_eq!(actual, expected)` 顺序（实际值在前，期望值在后）

### 边界测试技术
```rust
// 测试大量输入不会导致性能问题
let prefix = "$".repeat(256);
let text = format!("{prefix} not-a-mention");
```

## 关键代码路径与文件引用

### 被测函数
| 被测函数 | 测试覆盖 |
|---------|----------|
| `text_mentions_skill` | `text_mentions_skill_*` 系列测试 |
| `extract_tool_mentions` | `extract_tool_mentions_*` 系列测试 |
| `collect_explicit_skill_mentions` | `collect_explicit_skill_mentions_*` 系列测试 |

### 依赖模块
| 模块 | 用途 |
|------|------|
| `super::*` | 被测模块的公共 API |
| `pretty_assertions::assert_eq` | 增强的断言输出 |
| `std::collections::{HashMap, HashSet}` | 测试数据结构 |
| `codex_protocol::user_input::UserInput` | 用户输入类型 |
| `codex_protocol::protocol::SkillScope` | 技能作用域 |

## 依赖与外部交互

### 测试框架
- 使用 Rust 内置测试框架 (`#[test]`)
- 无需外部测试 runner

### 外部依赖
- `pretty_assertions`: 提供彩色差异输出
- `std::collections`: 标准集合类型

## 风险、边界与改进建议

### 测试覆盖分析

**已覆盖场景：**
- ✅ 基础提及解析
- ✅ 链接语法解析
- ✅ 环境变量过滤
- ✅ 歧义名称处理
- ✅ Connector 冲突
- ✅ 禁用路径处理
- ✅ 去重逻辑
- ✅ 优先级规则

**未覆盖场景（潜在改进）：**

1. **Unicode 支持测试**
   - 技能名称包含 Unicode 字符（如中文、Emoji）
   - 当前 `is_mention_name_char` 仅支持 ASCII

2. **错误处理测试**
   - 文件系统错误（权限不足、磁盘满）
   - 无效的文件编码

3. **并发测试**
   - 多线程环境下的技能提及收集

4. **性能基准测试**
   - 大规模技能列表（1000+ 技能）的性能
   - 长文本（MB 级别）的解析性能

5. **模糊测试**
   - 随机输入字符串的鲁棒性
   - 边界情况发现

### 改进建议

1. **参数化测试**
   ```rust
   // 使用 test_case crate 减少重复代码
   #[test_case("$alpha", &["alpha"], &[])]
   #[test_case("$beta", &["beta"], &[])]
   fn test_mention_extraction(text: &str, names: &[&str], paths: &[&str]) { ... }
   ```

2. **测试数据分离**
   - 将测试数据移至外部文件（JSON/YAML）
   - 便于非开发人员添加测试用例

3. **Mock 对象**
   - 使用 `mockall` 或类似库模拟文件系统
   - 提高测试的确定性和速度

4. **覆盖率报告**
   - 集成 `tarpaulin` 或 `cargo-llvm-cov`
   - 确保关键路径的 100% 覆盖

5. **文档测试**
   - 为公共 API 添加 `/// # Examples` 文档测试
   - 示例代码即测试
