# GuardianRiskLevel.ts Research Document

## 场景与职责

`GuardianRiskLevel` 类型定义了 Guardian 自动审批系统的风险等级分类枚举。该类型在以下场景中发挥核心作用：

1. **风险分级**：将数值化的风险分数（`riskScore`）映射为离散的风险等级，简化用户理解和决策。

2. **阈值控制**：作为自动审批策略的基础，不同风险等级可以触发不同的处理流程（如低风险自动批准、高风险必须人工审核）。

3. **UI 可视化**：驱动用户界面的风险指示器展示，通过颜色、图标等视觉元素直观传达风险程度。

4. **策略配置**：支持基于风险等级的细粒度审批策略配置，如"中风险以上需要二次确认"。

**⚠️ 重要提示**：该类型被标记为 **UNSTABLE（不稳定）**，其定义预计在近期会发生变更。

## 功能点目的

`GuardianRiskLevel` 的设计目的是：

- **简化决策**：将连续的风险分数转化为离散等级，降低用户认知负担
- **标准化分类**：建立统一的风险分类标准，确保不同操作的风险可比
- **策略驱动**：支持基于风险等级的自动化审批规则
- **可扩展性**：三等级设计为未来扩展（如添加 `critical`）预留空间

### 风险等级语义

| 等级 | 典型分数范围 | 语义 | 建议处理 |
|------|-------------|------|----------|
| `low` | 0-33 | 低风险操作，通常是只读操作或受控的写操作 | 可自动批准或快速确认 |
| `medium` | 34-66 | 中等风险操作，可能涉及文件修改或网络请求 | 需要用户确认 |
| `high` | 67-100 | 高风险操作，可能涉及敏感数据或系统级变更 | 必须人工审核，可能需要额外验证 |

## 具体技术实现

### 数据结构定义

```typescript
/**
 * [UNSTABLE] Risk level assigned by guardian approval review.
 */
export type GuardianRiskLevel = "low" | "medium" | "high";
```

### 关键字段说明

这是一个字符串字面量联合类型（String Literal Union Type），包含三个可能的值：

| 值 | 类型 | 说明 |
|----|------|------|
| `"low"` | 字符串字面量 | 低风险等级。表示操作风险较低，通常是安全的只读操作或在受控环境中的写操作。UI 通常使用绿色表示。 |
| `"medium"` | 字符串字面量 | 中等风险等级。表示操作有一定风险，可能涉及文件修改、网络请求等。需要用户关注但通常可接受。UI 通常使用黄色/橙色表示。 |
| `"high"` | 字符串字面量 | 高风险等级。表示操作风险较高，可能涉及敏感数据访问、系统级变更、不可逆操作等。需要谨慎处理。UI 通常使用红色表示。 |

### 风险等级映射模型

```
风险分数 (0-100)
    │
    │  0-33          34-66          67-100
    │   │              │               │
    ▼   ▼              ▼               ▼
┌───────┐        ┌─────────┐      ┌─────────┐
│  low  │        │ medium  │      │  high   │
│ (绿色) │        │ (黄色)   │      │ (红色)   │
└───┬───┘        └────┬────┘      └────┬────┘
    │                 │                │
    ▼                 ▼                ▼
┌─────────┐      ┌──────────┐     ┌──────────┐
│自动批准  │      │需要确认   │     │人工审核   │
│快速确认  │      │标准流程   │     │额外验证   │
└─────────┘      └──────────┘     └──────────┘
```

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/GuardianRiskLevel.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (第 4293-4311 行)

### Rust 实现细节

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "lowercase")]  // 序列化为小写字符串
#[ts(export_to = "v2/")]
/// [UNSTABLE] Risk level assigned by guardian approval review.
pub enum GuardianRiskLevel {
    Low,
    Medium,
    High,
}

impl From<CoreGuardianRiskLevel> for GuardianRiskLevel {
    fn from(value: CoreGuardianRiskLevel) -> Self {
        match value {
            CoreGuardianRiskLevel::Low => Self::Low,
            CoreGuardianRiskLevel::Medium => Self::Medium,
            CoreGuardianRiskLevel::High => Self::High,
        }
    }
}
```

### 序列化映射

| Rust 变体 | JSON 值 | TypeScript 值 |
|-----------|---------|---------------|
| `Low` | `"low"` | `"low"` |
| `Medium` | `"medium"` | `"medium"` |
| `High` | `"high"` | `"high"` |

**注意**：与大多数 v2 API 类型使用 camelCase 不同，`GuardianRiskLevel` 使用小写字符串（`#[serde(rename_all = "lowercase")]`），这是有意为之的设计选择，使风险等级在 JSON 中更简洁易读。

### 使用位置

1. **GuardianApprovalReview**（第 4325 行）：作为风险评估结果的一部分
   ```rust
   pub struct GuardianApprovalReview {
       pub status: GuardianApprovalReviewStatus,
       pub risk_score: Option<u8>,
       pub risk_level: Option<GuardianRiskLevel>,  // 此处使用
       pub rationale: Option<String>,
   }
   ```

2. **测试用例**（第 7435 行）：验证风险等级反序列化
   ```rust
   let review: GuardianApprovalReview = serde_json::from_value(json!({
       "status": "denied",
       "riskScore": 91,
       "riskLevel": "high",  // 小写字符串
       "rationale": "too risky"
   }))
   ```

## 依赖与外部交互

### 上游依赖

- `CoreGuardianRiskLevel`：核心协议层的风险等级定义

### 下游消费者

- `GuardianApprovalReview`：包含此风险等级作为评估结果
- **审批策略引擎**：根据风险等级决定审批流程
- **UI 组件**：风险指示器、颜色编码、图标选择
- **审计系统**：风险分布统计和分析

### 核心协议映射

```rust
// 从核心协议层转换
impl From<CoreGuardianRiskLevel> for GuardianRiskLevel {
    fn from(value: CoreGuardianRiskLevel) -> Self {
        match value {
            CoreGuardianRiskLevel::Low => Self::Low,
            CoreGuardianRiskLevel::Medium => Self::Medium,
            CoreGuardianRiskLevel::High => Self::High,
        }
    }
}
```

## 风险、边界与改进建议

### 潜在风险

1. **API 不稳定**：明确标记为 UNSTABLE，可能在未来的版本中变更或扩展
2. **分数映射不一致**：不同操作类型的风险分数到等级的映射标准可能不一致
3. **等级粒度不足**：三等级设计可能不足以覆盖所有风险场景
4. **文化差异**："low/medium/high" 的语义理解可能因用户背景而异

### 边界情况

1. **分数边界**：风险分数正好在边界值（如 33/34、66/67）时的处理
2. **缺失评估**：`riskLevel` 为 `null` 时的默认处理策略
3. **动态调整**：用户调整风险阈值后的历史数据一致性
4. **复合风险**：多个低风险操作组合可能产生高风险结果

### 改进建议

1. **添加等级**：
   - `critical`：极高风险，需要管理员审批
   - `info`：信息性风险，仅记录不拦截

2. **分数阈值可配置**：
   - 允许用户或组织自定义风险分数到等级的映射阈值
   - 支持基于操作类型的差异化阈值

3. **添加置信度**：
   - 与风险等级一起提供评估置信度
   - 低置信度时建议人工复核

4. **结构化风险信息**：
   - 添加风险类别（安全、隐私、性能、合规等）
   - 每个类别有自己的风险等级

5. **历史趋势**：
   - 提供风险等级的历史趋势分析
   - 识别风险模式变化

6. **稳定 API**：
   - 尽快确定最终设计并移除 UNSTABLE 标记

### TypeScript 使用模式

```typescript
// 风险等级排序（用于比较）
const riskLevelOrder: Record<GuardianRiskLevel, number> = {
  low: 0,
  medium: 1,
  high: 2,
};

function compareRiskLevel(a: GuardianRiskLevel, b: GuardianRiskLevel): number {
  return riskLevelOrder[a] - riskLevelOrder[b];
}

function isHighRisk(level: GuardianRiskLevel | null): boolean {
  return level === 'high';
}

function requiresManualReview(level: GuardianRiskLevel | null): boolean {
  return level === 'medium' || level === 'high';
}

// UI 颜色映射
const riskLevelColors: Record<GuardianRiskLevel, string> = {
  low: '#22c55e',    // green-500
  medium: '#f59e0b', // amber-500
  high: '#ef4444',   // red-500
};

// exhaustive switch 示例
function getRiskLevelDescription(level: GuardianRiskLevel): string {
  switch (level) {
    case 'low':
      return '此操作风险较低，通常可以安全执行。';
    case 'medium':
      return '此操作存在中等风险，建议仔细审阅后再执行。';
    case 'high':
      return '此操作风险较高，请确保您完全理解其影响。';
    default:
      const _exhaustive: never = level;
      return '未知风险等级';
  }
}
```

### 兼容性注意事项

- 该类型处于活跃开发中，可能添加新的等级
- 客户端应使用 exhaustive switch 或默认分支处理未知等级
- 类型由 `ts-rs` 自动生成，手动修改会被覆盖
- JSON 传输使用小写字符串（非 camelCase）
- 与 `GuardianApprovalReviewStatus` 不同，此类型使用小写序列化
