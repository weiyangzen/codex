# format_env_display.rs 研究文档

## 场景与职责

`format_env_display.rs` 是 `codex-utils-cli` crate 的实用工具模块，负责安全地格式化环境变量信息以供显示。该模块的核心职责是在 UI（TUI 或命令行输出）中展示环境变量时保护敏感信息，防止 API 密钥、令牌等机密数据泄露。

该模块主要服务于以下场景：
- **MCP 服务器配置展示**：在 `codex mcp list` 命令中显示服务器环境配置
- **TUI 历史记录渲染**：在对话历史中展示工具执行的环境上下文
- **调试信息输出**：在日志或调试输出中安全地展示环境变量

## 功能点目的

### 1. 敏感信息脱敏

将环境变量的值替换为 `*****`，防止敏感信息泄露：
- `TOKEN=secret123` → `TOKEN=*****`
- `API_KEY=abc` → `API_KEY=*****`

### 2. 双源环境变量支持

支持两种环境变量来源：
- **HashMap 来源**：已解析的键值对（如 MCP 配置中的 `env` 字段）
- **字符串列表来源**：环境变量名列表（如 MCP 配置中的 `env_vars` 字段，值从父进程继承）

### 3. 排序与格式化输出

- 按键名字母顺序排序，确保输出一致性
- 使用 `, ` 连接多个变量
- 空状态时返回 `-` 占位符

## 具体技术实现

### 核心函数

```rust
pub fn format_env_display(
    env: Option<&HashMap<String, String>>, 
    env_vars: &[String]
) -> String
```

### 实现逻辑

```rust
pub fn format_env_display(env: Option<&HashMap<String, String>>, env_vars: &[String]) -> String {
    let mut parts: Vec<String> = Vec::new();

    // 1. 处理 HashMap 来源的环境变量
    if let Some(map) = env {
        let mut pairs: Vec<_> = map.iter().collect();
        pairs.sort_by(|(a, _), (b, _)| a.cmp(b));  // 按键排序
        parts.extend(pairs.into_iter().map(|(key, _)| format!("{key}=*****")));
    }

    // 2. 处理字符串列表来源的环境变量
    if !env_vars.is_empty() {
        parts.extend(env_vars.iter().map(|var| format!("{var}=*****")));
    }

    // 3. 空状态处理
    if parts.is_empty() {
        "-".to_string()
    } else {
        parts.join(", ")
    }
}
```

### 关键设计决策

1. **值完全脱敏**：不显示值的任何部分（如部分掩码 `***123`），而是完全替换
2. **统一掩码字符串**：所有值使用相同长度的 `*****`，避免通过长度推测原值
3. **排序保证一致性**：HashMap 迭代顺序不确定，显式排序确保相同输入产生相同输出
4. **空值语义**：返回 `-` 而非空字符串，明确表达"无环境变量"状态

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/utils/cli/src/format_env_display.rs` (62 行，含测试)

### 调用方

#### MCP 命令模块
- `codex-rs/cli/src/mcp_cmd.rs` (第 28 行): `use codex_utils_cli::format_env_display::format_env_display;`
- `codex-rs/cli/src/mcp_cmd.rs` (第 562 行): MCP 服务器添加时的环境展示
- `codex-rs/cli/src/mcp_cmd.rs` (第 824 行): MCP 服务器列表展示

#### TUI 历史记录渲染
- `codex-rs/tui/src/history_cell.rs` (第 63 行): 导入
- `codex-rs/tui/src/history_cell.rs` (第 1872 行): 工具执行环境展示

#### TUI App Server 历史记录
- `codex-rs/tui_app_server/src/history_cell.rs` (第 68 行): 导入
- `codex-rs/tui_app_server/src/history_cell.rs` (第 1879 行): 工具执行环境展示
- `codex-rs/tui_app_server/src/history_cell.rs` (第 2046 行): 流式 HTTP 传输配置展示

### 使用示例

#### MCP 配置展示
```rust
// 在 mcp_cmd.rs 中
let env_display = format_env_display(env.as_ref(), env_vars);
println!("  env: {env_display}");
// 输出: env: TOKEN=*****, PATH=*****
```

#### TUI 渲染
```rust
// 在 history_cell.rs 中
let env_display = format_env_display(env.as_ref(), env_vars);
if env_display != "-" {
    lines.push(vec!["    • Env: ".into(), env_display.into()].into());
}
```

## 依赖与外部交互

### 直接依赖
- `std::collections::HashMap`: 环境变量键值对存储

### Crate 依赖关系
```
codex-utils-cli
└── std::collections::HashMap
```

### 模块导出
在 `codex-rs/utils/cli/src/lib.rs` 中作为 pub mod 导出：
```rust
pub mod format_env_display;
```

这使得调用方可以选择导入函数或直接使用模块路径：
```rust
// 方式 1: 直接导入函数
use codex_utils_cli::format_env_display::format_env_display;

// 方式 2: 通过模块路径使用
use codex_utils_cli::format_env_display;
format_env_display::format_env_display(...)
```

## 风险、边界与改进建议

### 已知风险

1. **信息泄露风险**
   - 当前实现仅掩码值，但键名本身可能敏感（如 `SECRET_KEY_NAME`）
   - 环境变量数量可能泄露配置信息

2. **HashMap 与列表重复**
   - 如果同一变量同时出现在 `env` 和 `env_vars` 中，会显示两次
   - 示例：`env={"PATH": "/bin"}` + `env_vars=["PATH"]` → `PATH=*****, PATH=*****`

3. **大小写敏感排序**
   - 当前使用默认字符串比较，大写字母排在小写字母之前
   - `Z` 排在 `a` 之前，可能与用户预期不符

### 边界情况

| 场景 | 行为 |
|------|------|
| `env=None, env_vars=[]` | 返回 `"-"` |
| `env=Some({}), env_vars=[]` | 返回 `"-"` |
| 空字符串键 | 显示 `=*****`（虽然罕见但可能） |
| 大量环境变量 | 长字符串，可能影响 UI 布局 |

### 测试覆盖

模块包含 4 个单元测试：
- `returns_dash_when_empty`: 空输入返回 `-`
- `formats_sorted_env_pairs`: 验证排序行为
- `formats_env_vars_with_dollar_prefix`: 字符串列表来源
- `combines_env_pairs_and_vars`: 双来源合并

### 改进建议

1. **去重处理**
   ```rust
   // 建议使用 BTreeSet 去重并保持排序
   use std::collections::BTreeSet;
   let all_keys: BTreeSet<&str> = map_keys.union(&list_keys).collect();
   ```

2. **大小写不敏感排序**
   ```rust
   pairs.sort_by(|(a, _), (b, _)| a.to_lowercase().cmp(&b.to_lowercase()));
   ```

3. **键名掩码选项**
   ```rust
   pub fn format_env_display(
       env: Option<&HashMap<String, String>>,
       env_vars: &[String],
       mask_keys: bool,  // 新增：是否也掩码键名
   ) -> String
   ```

4. **截断处理**
   ```rust
   // 环境变量过多时截断显示
   if parts.len() > 10 {
       parts.truncate(10);
       parts.push("...".to_string());
   }
   ```

5. **类型安全封装**
   ```rust
   // 建议：使用 newtype 模式区分原始值和脱敏值
   pub struct MaskedEnvVar(pub String);
   pub struct MaskedEnvValue(pub String);
   ```

6. **可选显示原始值**
   ```rust
   // 调试模式下允许显示原始值（需显式启用）
   pub fn format_env_display(
       env: Option<&HashMap<String, String>>,
       env_vars: &[String],
       reveal: bool,  // 仅调试使用
   ) -> String
   ```
