# frame_24.txt 研究文档

## 场景与职责

`frame_24.txt` 是 Codex TUI 欢迎界面 ASCII 动画序列的第 24 帧。该帧展示 Codex 标志在展开过程中的一个过渡形态，位于 36 帧动画循环的 2/3 位置。

## 功能点目的

1. **2/3 里程碑**：作为第 24 帧，完成 66.7% 的动画循环
2. **展开中段**：标志展开到接近初始状态的中段
3. **循环推进**：距离回到初始状态还有 12 帧

## 具体技术实现

### 文件规格
- **帧序号**：24 / 36
- **循环位置**：66.7%（24/36 = 2/3）
- **显示时间**：动画开始后约 1840ms
- **文件大小**：662 字节

### 数学关系
```
24/36 = 2/3 ≈ 66.7%
已用时间: 24 × 80ms = 1920ms
剩余时间: 12 × 80ms = 960ms
总周期: 36 × 80ms = 2880ms
```

### 对称性分析
```
frame_12 (33.3%) ←──── 对称 ────→ frame_24 (66.7%)
  收缩阶段中点              展开阶段中点
```

### 代码集成
```rust
// 所有变体数组
pub(crate) const ALL_VARIANTS: &[&[&str]] = &[
    &FRAMES_DEFAULT,
    &FRAMES_CODEX,  // 本文件所属
    &FRAMES_OPENAI,
    // ... 其他变体
];
```

## 关键代码路径与文件引用

### 引用路径
```
frame_24.txt
  ↓ include_str!
FRAMES_CODEX[23]
  ↓
AsciiAnimation::with_variants(..., ALL_VARIANTS, 0)
  ↓
WelcomeWidget::new(...)
```

### 变体切换
用户可通过 `Ctrl+.` 切换到其他变体：
```rust
pub(crate) fn pick_random_variant(&mut self) -> bool {
    let mut rng = rand::rng();
    let next = rng.random_range(0..self.variants.len());
    self.variant_idx = next;  // 可能切换到 FRAMES_CODEX
    self.request_frame.schedule_frame();
}
```

## 依赖与外部交互

### 系统交互
- 终端尺寸检查：`height >= 37 && width >= 60`
- 动画开关：`animations_enabled` 配置

### 模块依赖
- `rand`：变体随机选择
- `tokio`：异步调度
- `ratatui`：渲染

## 风险、边界与改进建议

### 边界条件
- **对称边界**：应与 frame_12 形成视觉对称
- **循环边界**：距离循环结束还有 1/3

### 改进建议
1. **对称验证测试**：自动化验证 frame_12 与 frame_24 的对称性
2. **变体预览**：添加命令行选项列出所有可用变体
3. **性能优化**：考虑使用 GPU 加速渲染（如果终端支持）
