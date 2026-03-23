# frame_30.txt 研究文档

## 场景与职责

`frame_30.txt` 是 Codex TUI 应用服务器中 ASCII 动画系统的第 30 帧，属于 `codex` 变体动画序列。

**动画序列位置**：第 30/36 帧
**时序位置**：2320ms（第 30 个 80ms 间隔）

## 功能点目的

1. **动画序列推进**：作为 36 帧循环的第 30 帧，超过 83% 周期点
2. **旋转展示**：展示 Codex 图标旋转约 290° 后的状态
3. **用户体验**：在终端启动期间提供持续的视觉反馈

## 具体技术实现

### 5/6 周期点特性
```
frame_30 是第 30 帧（索引 29）
时间：2320ms
周期进度：30/36 = 83.3%（正好 5/6）
剩余帧数：6 帧
旋转角度：290°
```

### 帧索引
```rust
const FRAME_30_INDEX: usize = 29;
let content = FRAMES_CODEX[FRAME_30_INDEX];
```

### 时间计算
```rust
let elapsed_ms = 2320;
let idx = (elapsed_ms / 80) % 36;  // = 29
let frame = FRAMES_CODEX[idx as usize];  // frame_30
```

## 关键代码路径与文件引用

### 文件引用链
```
frame_30.txt
  └─> frames.rs (include_str!)
      └─> FRAMES_CODEX[29]
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
    frames[idx]  // 可能返回 frame_30
}
```

## 依赖与外部交互

### 上游
- `frame_29.txt`
- 时间流逝

### 下游
- `frame_31.txt`
- 终端显示

### 外部控制
- 变体切换
- 动画开关

## 风险、边界与改进建议

### 5/6 周期考虑
1. **关键节点**：5/6 周期是动画的关键节点
2. **视觉一致性**：需要确保与前后帧的平滑过渡
3. **循环准备**：还有 6 帧回到 frame_1

### 改进建议
1. **关键帧标记**：在代码中标记 5/6 周期点
2. **帧验证**：验证 frame_30 与 frame_6 的关系（如果动画对称）
3. **性能优化**：确保关键节点的渲染性能

### 测试建议
```rust
#[test]
fn frame_30_is_five_sixths() {
    // 验证 frame_30 是第 30 帧
    assert_eq!(FRAMES_CODEX.len(), 36);
    let five_sixths_idx = FRAMES_CODEX.len() * 5 / 6;  // = 30
    // frame_30 在索引 29
    let frame_30 = FRAMES_CODEX[29];
    assert!(!frame_30.is_empty());
}
```
