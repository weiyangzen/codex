# env_var_dependencies.rs 研究文档

## 场景与职责

`env_var_dependencies.rs` 是 Codex 技能系统中负责**环境变量依赖解析**的模块。当用户使用的技能需要特定的环境变量（如 API 密钥、配置值等）时，该模块负责：

1. **收集环境变量依赖**：从技能的元数据中提取类型为 `env_var` 的工具依赖
2. **解析依赖值**：按优先级（会话缓存 → 系统环境变量）查找已存在的值
3. **交互式提示**：对于缺失的环境变量，通过 UI 向用户发起请求，要求输入
4. **会话级存储**：将用户输入的值存储在会话级别的内存缓存中，仅对当前会话有效

该模块是技能依赖管理系统的关键组成部分，确保技能在执行前拥有所需的配置环境。

## 功能点目的

### 1. `SkillDependencyInfo` 结构体
```rust
pub(crate) struct SkillDependencyInfo {
    pub(crate) skill_name: String,    // 依赖所属的技能名称
    pub(crate) name: String,          // 环境变量名
    pub(crate) description: Option<String>, // 可选的描述说明
}
```
用于封装单个环境变量依赖的信息，便于在模块内部传递和处理。

### 2. `resolve_skill_dependencies_for_turn` - 核心解析函数
这是模块的入口函数，在每次用户回合（turn）时被调用：

**执行流程：**
1. **快速返回**：如果依赖列表为空，立即返回
2. **获取现有环境**：从会话中获取已缓存的依赖环境变量
3. **遍历依赖项**：
   - 使用 `seen_names` HashSet 去重
   - 跳过已在会话缓存中的变量
   - 尝试从系统环境变量读取 (`std::env::var`)
   - 记录成功读取的值到 `loaded_values`
   - 记录缺失的依赖到 `missing` 列表
4. **更新会话缓存**：将新读取的环境变量存入会话
5. **请求缺失值**：调用 `request_skill_dependencies` 向用户请求缺失的值

### 3. `collect_env_var_dependencies` - 依赖收集函数
从技能元数据列表中提取所有 `env_var` 类型的依赖：
- 遍历所有被提及的技能
- 检查每个技能的 `dependencies.tools` 列表
- 筛选 `type == "env_var"` 且 `value` 非空的工具依赖
- 返回 `SkillDependencyInfo` 列表

### 4. `request_skill_dependencies` - 用户交互函数
通过 `request_user_input` 协议向用户发起交互式请求：

**关键特性：**
- 为每个缺失的依赖生成一个问题
- 问题格式包含技能名称、环境变量名和描述
- 标记为 `is_secret: true`，确保 UI 以密码形式显示输入
- 使用 `skill-deps-{sub_id}` 作为 call_id 便于追踪
- 解析响应中的 `user_note:` 前缀提取用户输入值
- 将收集到的值存入会话依赖环境

## 具体技术实现

### 依赖解析优先级
```
1. 会话缓存 (sess.dependency_env()) - 最高优先级
2. 系统环境变量 (std::env::var) 
3. 用户交互输入 - 最低优先级，作为补充
```

### 用户输入协议
使用 `codex_protocol::request_user_input` 模块定义的类型：
- `RequestUserInputArgs`: 包含问题列表的请求参数
- `RequestUserInputQuestion`: 单个问题定义（id, header, question, is_secret）
- `RequestUserInputResponse`: 用户响应，包含答案映射

### 响应解析逻辑
```rust
for entry in &answer.answers {
    if let Some(note) = entry.strip_prefix("user_note: ")
        && !note.trim().is_empty()
    {
        user_note = Some(note.trim().to_string());
    }
}
```
从答案条目中提取 `user_note:` 前缀的内容作为环境变量值。

## 关键代码路径与文件引用

### 本文件关键函数
| 函数 | 行号 | 职责 |
|------|------|------|
| `resolve_skill_dependencies_for_turn` | 24-66 | 主入口，协调依赖解析流程 |
| `collect_env_var_dependencies` | 68-91 | 从技能元数据收集 env_var 依赖 |
| `request_skill_dependencies` | 94-162 | 向用户发起输入请求 |

### 调用路径
```
codex-rs/core/src/codex.rs:5487
    └── resolve_skill_dependencies_for_turn(&sess, &turn_context, &env_var_dependencies).await
        
调用条件（Feature Gate）:
    config.features.enabled(Feature::SkillEnvVarDependencyPrompt)
```

### 依赖的数据结构
- `SkillMetadata` (model.rs): 技能元数据，包含 dependencies 字段
- `SkillToolDependency` (model.rs): 工具依赖定义
- `Session::dependency_env()` / `set_dependency_env()`: 会话级环境变量缓存
- `TurnContext`: 回合上下文，包含 sub_id 用于生成 call_id

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `crate::codex::Session` | 会话管理，环境变量缓存读写 |
| `crate::codex::TurnContext` | 回合上下文，获取 sub_id |
| `crate::skills::SkillMetadata` | 技能元数据结构 |

### 外部协议依赖
| 模块 | 用途 |
|------|------|
| `codex_protocol::request_user_input::*` | 用户输入请求/响应类型定义 |
| `tracing::warn` | 日志记录 |

### 标准库依赖
- `std::collections::{HashMap, HashSet}`: 去重和映射存储
- `std::env`: 读取系统环境变量
- `std::sync::Arc`: 异步上下文中的共享所有权

## 风险、边界与改进建议

### 已知风险

1. **会话级存储限制**
   - 环境变量仅存储在内存中，会话结束后丢失
   - 用户每次新会话都需要重新输入
   - 风险：用户体验不佳，特别是对于频繁使用的技能

2. **无持久化机制**
   - 当前实现没有将用户输入写入配置文件或密钥管理器
   - 与系统环境变量相比，缺乏持久性

3. **并发安全**
   - `sess.dependency_env()` 和 `sess.set_dependency_env()` 是异步操作
   - 需要确保 Session 内部使用适当的同步机制（如 Mutex）

4. **错误处理不完整**
   - `env::var` 的 `NotPresent` 错误被静默处理
   - 其他错误仅记录 warn 日志，不中断流程

### 边界情况

1. **重复依赖名**
   - 使用 `seen_names` HashSet 去重，确保同一变量只处理一次
   - 如果多个技能依赖同名环境变量，只提示一次

2. **空响应处理**
   - 如果用户取消或提供空响应，`response.answers` 为空
   - 函数优雅返回，不报错

3. **环境变量名大小写**
   - 依赖系统环境变量的行为（Unix 区分大小写，Windows 不区分）

### 改进建议

1. **持久化支持**
   ```rust
   // 建议：添加可选的持久化到系统密钥管理器
   async fn persist_to_keyring(&self, name: &str, value: &str) -> Result<()>;
   ```

2. **缓存优化**
   - 考虑添加 TTL 或版本控制，避免过时值
   - 支持从 `.env` 文件加载预设值

3. **用户体验改进**
   - 添加"记住此值"选项，让用户选择是否持久化
   - 提供环境变量配置向导

4. **安全性增强**
   - 考虑使用零拷贝字符串处理敏感值
   - 添加内存擦除机制，会话结束后清除敏感数据

5. **测试覆盖**
   - 当前文件无直接单元测试，依赖集成测试
   - 建议添加 mock Session 和 TurnContext 的单元测试
