# frame_17.txt 研究文档

## 场景与职责

`frame_17.txt` 是 Codex TUI 应用服务器中 ASCII 动画系统的第 17 帧，属于 `codex` 变体动画序列。

**动画序列位置**：第 17/36 帧
**时序位置**：1280ms（第 17 个 80ms 间隔）

## 功能点目的

1. **动画序列中点**：作为 36 帧循环的第 17 帧，接近周期中点
2. **旋转展示**：展示 Codex 图标旋转约 160° 后的状态
3. **用户体验**：在终端启动期间提供持续的视觉反馈

## 具体技术实现

### 帧时序分析
```
frame_17 是第 17 帧（索引 16）
时间：1280ms
周期进度：17/36 ≈ 47.2%
接近中点（50%）
```

### 帧访问代码
```rust
// 直接访问
let frame_17 = FRAMES_CODEX[16];

// 通过时间计算
let elapsed = Duration::from_millis(1280);
let idx = (elapsed.as_millis() / 80) % 36;
assert_eq!(idx, 16);
let frame = FRAMES_CODEX[idx as usize];
```

### 动画状态转换
```
frame_16 (1200ms) → frame_17 (1280ms) → frame_18 (1360ms)
     idx=15      →      idx=16       →      idx=17
```

## 关键代码路径与文件引用

### 文件引用链
```
frame_17.txt
  └─> frames.rs (include_str!)
      └─> FRAMES_CODEX[16]
          └─> ascii_animation.rs
              └─> welcome.rs
                  └─> 终端显示
```

### 关键代码
```rust
// frames.rs
pub(crate) const FRAMES_CODEX: [&str; 36] = frames_for!("codex");

// ascii_animation.rs
fn frames(&self) -> &'static [&'static str] {
    self.variants[self.variant_idx]  // 返回 &FRAMES_CODEX
}

pub(crate) fn current_frame(&self) -> &'static str {
    let frames = self.frames();
    let idx = /* 计算 */;
    frames[idx]  // 可能返回 frame_17
}
```

## 依赖与外部交互

### 上游
- `frame_16.txt`：前序帧
- `Instant::now()`：时间基准

### 下游
- `frame_18.txt`：后续帧
- 终端显示

### 外部控制
- 用户可通过 `Ctrl+.` 切换变体
- 系统可通过配置禁用动画

## 风险、边界与改进建议

### 边界情况
1. **周期中点**：frame_17 接近动画中点，视觉上应该与 frame_1 有明显差异
2. **变体切换**：切换后从 frame_1 开始
3. **终端限制**：小终端不显示动画

### 改进建议
1. **中点标记**：在代码中标记中点帧，便于调试
2. **对称优化**：利用动画的对称性减少帧数
3. **预览工具**：开发工具预览所有帧

### 维护清单
- [ ] 验证 frame_17 与 frame_1 的视觉差异
- [ ] 确保动画在中点前后对称
- [ ] 测试变体切换后动画重置
