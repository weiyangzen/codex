# frame_24.txt 研究文档

## 场景与职责

`frame_24.txt` 是 Codex TUI 应用服务器中 ASCII 动画系统的第 24 帧，属于 `codex` 变体动画序列。

**动画序列位置**：第 24/36 帧
**时序位置**：1840ms（第 24 个 80ms 间隔）

## 功能点目的

1. **动画序列推进**：作为 36 帧循环的第 24 帧，达到 2/3 周期点（66.7%）
2. **旋转展示**：展示 Codex 图标旋转约 230° 后的状态
3. **用户体验**：在终端启动期间提供持续的视觉反馈

## 具体技术实现

### 2/3 周期点特性
```
frame_24 是第 24 帧（索引 23）
时间：1840ms
周期进度：24/36 = 66.7%（正好 2/3）
剩余帧数：12 帧
旋转角度：230°
```

### 帧索引
```rust
const FRAME_24_INDEX: usize = 23;
let content = FRAMES_CODEX[FRAME_24_INDEX];
```

### 时间计算
```rust
let elapsed_ms = 1840;
let idx = (elapsed_ms / 80) % 36;  // = 23
let frame = FRAMES_CODEX[idx as usize];  // frame_24
```

## 关键代码路径与文件引用

### 文件引用链
```
frame_24.txt
  └─> frames.rs (include_str!)
      └─> FRAMES_CODEX[23]
          └─> ascii_animation.rs
              └─> welcome.rs
                  └─> 终端显示
```

### 关键代码
```rust
// frames.rs
pub(crate) const FRAMES_CODEX: [&str; 36] = frames_for!("codex");

// ascii_animation.rs
pub(crate) fn current_frame(&self) -> &'static str {
    let frames = self.frames();
    let elapsed_ms = self.start.elapsed().as_millis();
    let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    frames[idx]  // 可能返回 frame_24
}
```

## 依赖与外部交互

### 上游
- `frame_23.txt`
- 时间流逝

### 下游
- `frame_25.txt`
- 终端显示

### 外部控制
- 变体切换
- 动画开关

## 风险、边界与改进建议

### 2/3 周期考虑
1. **关键节点**：2/3 周期是动画的关键节点
2. **视觉一致性**：需要确保与前后帧的平滑过渡
3. **循环准备**：还有 12 帧回到 frame_1

### 改进建议
1. **关键帧标记**：在代码中标记 2/3 周期点
2. **帧验证**：验证 frame_24 与 frame_12 的关系（如果动画对称）
3. **性能优化**：确保关键节点的渲染性能

### 测试建议
```rust
#[test]
fn frame_24_is_two_thirds() {
    // 验证 frame_24 是第 24 帧
    assert_eq!(FRAMES_CODEX.len(), 36);
    let two_thirds_idx = FRAMES_CODEX.len() * 2 / 3;  // = 24
    // frame_24 在索引 23
    let frame_24 = FRAMES_CODEX[23];
    assert!(!frame_24.is_empty());
}
```
