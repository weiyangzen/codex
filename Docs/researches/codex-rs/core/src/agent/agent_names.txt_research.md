# agent_names.txt 研究文档

## 场景与职责

`agent_names.txt` 是一个纯文本数据文件，位于 `codex-rs/core/src/agent/` 目录下。该文件包含 101 个历史人物名字，用于为 Codex 多代理系统中的子代理（sub-agent）生成随机昵称。这些名字涵盖数学家、科学家、哲学家等领域的历史名人。

该文件通过 Rust 的 `include_str!` 宏在编译时嵌入到 `control.rs` 中，作为默认的代理昵称候选池。

## 功能点目的

1. **提供默认昵称池**：当用户没有配置特定角色的昵称候选列表时，系统从此文件中随机选择名字作为子代理的昵称
2. **增强用户体验**：为每个子代理分配一个独特的历史人物名字，便于用户区分和记忆不同的代理实例
3. **支持昵称循环**：当所有名字都被使用后，系统会自动添加序数后缀（如 "Plato the 2nd"）来扩展命名空间

## 具体技术实现

### 数据格式
- 纯文本文件，每行一个名字
- 包含 100 个历史名人名字 + 1 个特殊名字 "Jason"
- 名字按历史时间顺序排列，从古希腊到现代

### 名字分类

**古代数学家/科学家（古希腊-罗马时期）**：
- Euclid, Archimedes, Ptolemy, Hypatia

**中世纪学者**：
- Avicenna, Averroes, Aquinas

**文艺复兴-启蒙时期**：
- Copernicus, Kepler, Galileo, Bacon, Descartes, Pascal, Fermat, Huygens, Leibniz, Newton, Halley

**近代科学家（18-19世纪）**：
- Euler, Lagrange, Laplace, Volta, Gauss, Ampere, Faraday, Darwin, Lovelace, Boole, Pasteur, Maxwell, Mendel, Curie, Planck, Tesla, Poincare

**现代科学家（20世纪）**：
- Noether, Hilbert, Einstein, Raman, Bohr, Turing, Hubble, Feynman, Franklin, McClintock, Meitner, Herschel, Linnaeus, Wegener, Chandrasekhar, Sagan, Goodall, Carson, Carver

**哲学家**：
- Socrates, Plato, Aristotle, Epicurus, Cicero, Confucius, Mencius, Zeno, Locke, Hume, Kant, Hegel, Kierkegaard, Mill, Nietzsche, Peirce, James, Dewey, Russell, Popper, Sartre, Beauvoir, Arendt, Rawls, Singer, Anscombe, Parfit, Kuhn

**其他科学家**：
- Boyle, Hooke, Harvey, Dalton, Ohm, Helmholtz, Gibbs, Lorentz, Schrodinger, Heisenberg, Pauli, Dirac, Bernoulli, Godel, Nash, Banach, Ramanujan, Erdos

**特殊名字**：
- Jason（可能是对某人的致敬）

### 使用方式

在 `control.rs` 中通过以下代码嵌入：

```rust
const AGENT_NAMES: &str = include_str!("agent_names.txt");

fn default_agent_nickname_list() -> Vec<&'static str> {
    AGENT_NAMES
        .lines()
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .collect()
}
```

## 关键代码路径与文件引用

### 读取路径
- **定义位置**: `codex-rs/core/src/agent/agent_names.txt`
- **嵌入位置**: `codex-rs/core/src/agent/control.rs` (第 30 行)
- **使用函数**: `default_agent_nickname_list()` 在 `control.rs` 第 38-44 行

### 调用链
```
agent_nickname_candidates() [control.rs:46-61]
    ├── 如果有角色配置: 使用角色配置的 nickname_candidates
    └── 否则: default_agent_nickname_list() [control.rs:57]
            └── AGENT_NAMES (agent_names.txt 内容)
```

### 相关文件
- `codex-rs/core/src/agent/control.rs`: 主控制逻辑，嵌入并使用该文件
- `codex-rs/core/src/agent/guards.rs`: `SpawnReservation` 处理昵称分配
- `codex-rs/core/src/config/mod.rs`: `AgentRoleConfig` 定义角色特定的昵称候选

## 依赖与外部交互

### 内部依赖
- **编译时嵌入**: 使用 Rust `include_str!` 宏，文件内容在编译时嵌入二进制
- **运行时解析**: 按行分割并过滤空行，转换为字符串切片向量

### 配置覆盖
用户可以通过配置文件的 `agents.<role>.nickname_candidates` 字段提供自定义昵称列表，覆盖默认的历史名人列表：

```toml
[agents.researcher]
nickname_candidates = ["Alpha", "Beta", "Gamma"]
```

### 角色特定配置
在 `role.rs` 中，内置角色（如 "explorer", "worker"）可以使用自定义的昵称候选列表，如果不配置则回退到 `agent_names.txt`。

## 风险、边界与改进建议

### 当前风险

1. **硬编码名字池**：
   - 101 个名字在高并发场景下可能很快耗尽
   - 虽然 `guards.rs` 中的 `format_agent_nickname()` 通过添加序数后缀（如 "the 2nd"）解决了这个问题，但名字会变得冗长

2. **文化偏向性**：
   - 名字主要来自西方历史和科学传统
   - 缺乏亚洲、非洲、南美洲等其他地区的代表性人物

3. **无动态更新**：
   - 作为编译时嵌入的资源，无法在运行时更新
   - 需要重新编译才能修改名字列表

### 边界情况

1. **空文件处理**：`default_agent_nickname_list()` 会过滤空行，但如果文件完全为空，将返回空向量
2. **并发昵称分配**：多个线程同时请求昵称时，`guards.rs` 中的 `Mutex` 确保线程安全
3. **昵称池重置**：当所有名字都被使用时，`reserve_agent_nickname()` 会清空已使用集合并增加重置计数

### 改进建议

1. **国际化支持**：
   - 添加更多非西方历史人物名字
   - 按用户地区设置选择不同的名字池

2. **可配置性增强**：
   - 支持从外部文件动态加载昵称列表
   - 允许用户完全自定义名字池而无需重新编译

3. **命名策略扩展**：
   - 支持使用代号系统（如 "Agent-001"）
   - 支持使用随机生成的名字（如 "Azure Dolphin"）

4. **文档完善**：
   - 在文件顶部添加注释说明每个名字的背景
   - 添加版本信息以便追踪更新

5. **测试覆盖**：
   - 添加测试确保名字列表格式正确
   - 验证名字唯一性（当前列表中有潜在重复风险）
