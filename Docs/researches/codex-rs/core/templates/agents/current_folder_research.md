# Research: codex-rs/core/templates/agents

## Executive Summary

The `codex-rs/core/templates/agents` directory contains a single but critical file: `orchestrator.md`. This file serves as the **system prompt template** for the main Codex agent (GPT-5 based), defining its personality, behavior patterns, tool usage guidelines, and collaboration protocols. It is the foundational instruction set that governs how the primary agent interacts with users and delegates work to sub-agents.

---

## 1. 场景与职责 (Scenarios & Responsibilities)

### 1.1 Core Purpose

The `orchestrator.md` template defines the **primary agent's system prompt** - the base instructions injected into every conversation with the main Codex agent. It establishes:

- **Identity**: Codex as a GPT-5 based collaborative pair-programmer AI
- **Personality**: Concise, direct, friendly; takes engineering quality seriously
- **Communication Style**: CLI-optimized, low-noise, actionable guidance
- **Tool Usage Patterns**: When and how to use available tools
- **Sub-agent Orchestration**: Rules for spawning and coordinating sub-agents

### 1.2 Usage Scenarios

| Scenario | Description |
|----------|-------------|
| **Primary Agent Initialization** | Loaded as base instructions when the main Codex session starts |
| **Sub-agent Delegation** | Provides guidelines for when/how to spawn sub-agents (explorer, worker roles) |
| **Tool Selection** | Guides the agent on preferring `rg` over `grep`, using `apply_patch`, etc. |
| **User Collaboration** | Defines the collaborative posture (equal co-builder, preserve user intent) |
| **Review Mode** | Sets the code-review mindset when user asks for reviews |

### 1.3 Key Responsibilities

1. **Behavioral Framing**: Establishes the agent as a "collaborative, highly capable pair-programmer"
2. **Communication Constraints**: Enforces CLI-appropriate output (no emojis, tight formatting, flat lists)
3. **Tool Usage Guidelines**: Documents preferred tools and patterns (e.g., `rg` over alternatives)
4. **Sub-agent Management**: Defines when and how to spawn parallel sub-agents for efficiency
5. **Safety & Ethics**: Git safety rules (never destructive commands without approval)

---

## 2. 功能点目的 (Functional Purposes)

### 2.1 Template Content Structure

The `orchestrator.md` template is organized into functional sections:

```
orchestrator.md
├── Identity & Personality          # Who the agent is
├── Tone and Style                  # How to communicate
├── Responsiveness                  # When/how to update the user
├── Code Style                      # Engineering principles
├── Reviews                         # Review mindset
├── Environment                     # Git, AGENTS.md conventions
├── Tool Use                        # Tool selection guidelines
└── Sub-agents                      # Parallel delegation rules
```

### 2.2 Key Functional Components

#### 2.2.1 Personality Definition
```markdown
You are a collaborative, highly capable pair-programmer AI. 
You take engineering quality seriously, and collaboration is a kind of quiet joy...
```

**Purpose**: Establishes emotional tone and working relationship with users.

#### 2.2.2 Communication Constraints
- **No nested bullets**: Keep lists flat (single level)
- **Numbered lists**: Use `1. 2. 3.` style only (period, not parenthesis)
- **Headers**: Short Title Case (1-3 words), no blank line after
- **Code blocks**: Always include info string when possible
- **File references**: Use clickable formats (`src/app.ts:42`, `b/server/index.js#L10`)

**Purpose**: Ensures output is optimized for CLI/terminal rendering.

#### 2.2.3 User Update Protocol
The template defines a strict **Frequency & Length** protocol:
- Short updates (1-2 sentences) for meaningful insights
- Brief heads-down notes before long operations
- Only initial plan, plan updates, and final recap can be longer

**Purpose**: Keeps users informed without overwhelming them during tool-heavy operations.

#### 2.2.4 Sub-agent Orchestration Rules

The template includes a dedicated **Sub-agents** section that defines:

| Rule | Description |
|------|-------------|
| **Core Rule** | Sub-agents exist to make the agent go fast; time is a constraint |
| **Parallelism** | Prefer multiple sub-agents to parallelize work |
| **Coordination** | Wait for sub-agents before yielding (unless user asks a question) |
| **Agent Selection** | Choose the correct agent type for the task |

**Purpose**: Enables efficient parallel execution while maintaining user experience.

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 Template Loading & Usage

The `orchestrator.md` file is **NOT directly loaded via `include_str!`** like other templates. Instead, it appears to be loaded through the configuration/prompt system. Related templates are loaded in:

```rust
// codex-rs/core/src/client_common.rs
pub const REVIEW_PROMPT: &str = include_str!("../review_prompt.md");
pub const REVIEW_EXIT_SUCCESS_TMPL: &str = include_str!("../templates/review/exit_success.xml");
pub const REVIEW_EXIT_INTERRUPTED_TMPL: &str = include_str!("../templates/review/exit_interrupted.xml");
```

### 3.2 Related Template Systems

#### 3.2.1 Collaboration Mode Presets
Located in: `codex-rs/core/src/models_manager/collaboration_mode_presets.rs`

```rust
const COLLABORATION_MODE_PLAN: &str = include_str!("../../templates/collaboration_mode/plan.md");
const COLLABORATION_MODE_DEFAULT: &str = include_str!("../../templates/collaboration_mode/default.md");
```

These templates define mode-specific behavior (Plan mode, Default mode, Execute mode, Pair Programming mode).

#### 3.2.2 Memory System Templates
Located in: `codex-rs/core/src/memories/mod.rs`

```rust
pub(super) const PROMPT: &str = include_str!("../../templates/memories/stage_one_system.md");
```

Used for the memory writing agent's Phase 1 extraction.

#### 3.2.3 Compaction Templates
Located in: `codex-rs/core/src/compact.rs`

```rust
pub const SUMMARIZATION_PROMPT: &str = include_str!("../templates/compact/prompt.md");
pub const SUMMARY_PREFIX: &str = include_str!("../templates/compact/summary_prefix.md");
```

Used for context window compaction.

### 3.3 Sub-agent Role System

The orchestrator template references sub-agents that are defined in:

**File**: `codex-rs/core/src/agent/role.rs`

Built-in roles include:
- **`default`**: Default agent with no special configuration
- **`explorer`**: Fast, authoritative codebase exploration agent
- **`worker`**: Execution and production work agent
- **`awaiter`** (commented out): Long-running task monitoring agent

```rust
pub const DEFAULT_ROLE_NAME: &str = "default";

// Built-in role definitions
AgentRoleConfig {
    description: Some("Default agent.".to_string()),
    config_file: None,
    nickname_candidates: None,
}
```

### 3.4 Multi-Agent Tool Handlers

**File**: `codex-rs/core/src/tools/handlers/multi_agents.rs`

Implements the collaboration tool surface:
- `spawn_agent`: Spawn new sub-agents
- `send_input`: Send messages to existing agents
- `wait_agent`: Wait for agent completion
- `close_agent`: Shutdown agents
- `resume_agent`: Resume agents from rollout

### 3.5 Agent Control Plane

**File**: `codex-rs/core/src/agent/control.rs`

The `AgentControl` struct provides:
- Thread spawning via `spawn_agent()`
- Input sending via `send_input()`
- Status monitoring via `subscribe_status()`
- Completion watching for parent-child notification

```rust
#[derive(Clone, Default)]
pub(crate) struct AgentControl {
    manager: Weak<ThreadManagerState>,
    state: Arc<Guards>,
}
```

---

## 4. 关键代码路径与文件引用 (Key Code Paths & File References)

### 4.1 Direct Template Files

| File | Purpose | Loaded By |
|------|---------|-----------|
| `orchestrator.md` | Main agent system prompt | Configuration system |
| `collaboration_mode/plan.md` | Plan mode instructions | `collaboration_mode_presets.rs` |
| `collaboration_mode/default.md` | Default mode instructions | `collaboration_mode_presets.rs` |
| `collaboration_mode/execute.md` | Execute mode instructions | (Referenced) |
| `collaboration_mode/pair_programming.md` | Pair programming mode | (Referenced) |
| `compact/prompt.md` | Compaction system prompt | `compact.rs` |
| `compact/summary_prefix.md` | Compaction summary prefix | `compact.rs` |
| `memories/stage_one_system.md` | Memory extraction prompt | `memories/mod.rs` |
| `memories/consolidation.md` | Memory consolidation instructions | (Phase 2 agent) |
| `review/exit_success.xml` | Review success template | `client_common.rs` |
| `review/exit_interrupted.xml` | Review interrupted template | `client_common.rs` |

### 4.2 Core Implementation Files

| File | Description |
|------|-------------|
| `codex-rs/core/src/agent/mod.rs` | Agent module exports |
| `codex-rs/core/src/agent/control.rs` | AgentControl for spawn/manage |
| `codex-rs/core/src/agent/role.rs` | Role resolution and built-in configs |
| `codex-rs/core/src/agent/builtins/explorer.toml` | Explorer role config |
| `codex-rs/core/src/agent/builtins/awaiter.toml` | Awaiter role config |
| `codex-rs/core/src/agent/guards.rs` | Spawn depth limits, guards |
| `codex-rs/core/src/tools/handlers/multi_agents.rs` | Tool handlers for collab |
| `codex-rs/core/src/tools/handlers/multi_agents/spawn.rs` | Spawn agent implementation |
| `codex-rs/core/src/tools/orchestrator.rs` | ToolOrchestrator (approvals/sandbox) |

### 4.3 Role Configuration Flow

```
User Request
    ↓
spawn_agent tool call
    ↓
multi_agents/spawn.rs::Handler::handle()
    ↓
build_agent_spawn_config()  ← Creates base config from turn context
    ↓
apply_role_to_config()      ← Applies role layer (role.rs)
    ↓
resolve_role_config()       ← Resolves built-in or user-defined role
    ↓
built_in::configs()         ← Returns built-in role map
    ↓
AgentControl::spawn_agent() ← Creates new thread with config
```

---

## 5. 依赖与外部交互 (Dependencies & External Interactions)

### 5.1 Internal Dependencies

```
templates/agents/orchestrator.md
    ├── Referenced by: Configuration/Prompt system
    ├── Related to: collaboration_mode/*.md (mode-specific overlays)
    ├── Related to: memories/*.md (memory agent prompts)
    └── Consumed by: codex::Session (indirectly via config)
```

### 5.2 External Interactions

| Interaction | Description |
|-------------|-------------|
| **Model Provider** | System prompt sent to GPT-5/Codex model via API |
| **Sub-agents** | Orchestrator defines rules for spawning child processes |
| **User** | Defines communication patterns and collaboration style |
| **File System** | References AGENTS.md discovery rules |
| **Git** | Defines git safety rules (no destructive commands) |

### 5.3 Configuration Integration

The orchestrator template works with:

1. **`ConfigToml`**: Base configuration structure
2. **`AgentRoleConfig`**: Role-specific overrides
3. **`BaseInstructions`**: Runtime instruction injection
4. **`CollaborationModeMask`**: Mode-specific instruction overlays

---

## 6. 风险、边界与改进建议 (Risks, Boundaries & Recommendations)

### 6.1 Current Risks

#### Risk 1: Template Drift
**Issue**: The `orchestrator.md` file is not validated at compile time (unlike `include_str!` templates). Risk of syntax errors or formatting issues going undetected.

**Mitigation**: Add a build-time check or test that validates the template can be loaded.

#### Risk 2: Sub-agent Section Ambiguity
**Issue**: The template mentions `spawn_agent` availability depends on the tool being present, but this isn't dynamically checked in the template itself.

**Mitigation**: The template should clarify that sub-agent sections are conditional on feature availability.

#### Risk 3: Commented Code in Template
**Issue**: Line 81 contains a commented-out instruction:
```markdown
<!-- - Parallelize tool calls whenever possible - especially file reads, such as `cat`, `rg`, `sed`, `sed`, `ls`, `git show`, `nl`, `wc`. Use `multi_tool_use.parallel` to parallelize tool calls and only this. -->
```

This is dead content that should be removed.

### 6.2 Boundaries & Limitations

| Boundary | Description |
|----------|-------------|
| **Static Content** | Template is static; cannot adapt to runtime conditions |
| **No i18n** | Template is English-only; no localization support |
| **Model-Specific** | Written for GPT-5/Codex; may not transfer to other models |
| **Tool List Static** | Tool references (rg, apply_patch) assume specific tool availability |

### 6.3 Improvement Recommendations

#### Recommendation 1: Add Template Validation Test
```rust
// In tests or build script
#[test]
fn validate_orchestrator_template() {
    let content = include_str!("../templates/agents/orchestrator.md");
    assert!(!content.contains("<!--"), "No HTML comments in template");
    assert!(content.len() > 1000, "Template has substantial content");
}
```

#### Recommendation 2: Document Template Loading Path
The exact mechanism for loading `orchestrator.md` should be documented. Currently it's unclear if this is:
- Loaded from filesystem at runtime
- Embedded via a macro not visible in grep results
- Loaded through a configuration layer

#### Recommendation 3: Remove Dead Content
Remove the commented HTML comment on line 81 to keep the template clean.

#### Recommendation 4: Version the Template
Add a version header to track template iterations:
```markdown
---
version: 1.0.0
last_updated: 2026-03-22
model_target: gpt-5-codex
---
```

#### Recommendation 5: Consider Splitting
The template is 106 lines and growing. Consider splitting into:
- `orchestrator_core.md` - Essential identity and behavior
- `orchestrator_tools.md` - Tool usage guidelines
- `orchestrator_subagents.md` - Sub-agent delegation rules

This would improve maintainability and allow selective loading based on feature flags.

### 6.4 Testing Gaps

| Gap | Impact | Recommendation |
|-----|--------|----------------|
| No compile-time inclusion | Runtime errors possible | Use `include_str!` or validate in tests |
| No template versioning | Hard to track changes | Add metadata header |
| No A/B framework | Can't test template variants | Add template variant support |

---

## 7. Appendix: Template Cross-Reference

### 7.1 All Templates in codex-rs/core/templates

```
templates/
├── agents/
│   └── orchestrator.md              # [THIS FILE] Main agent system prompt
├── collaboration_mode/
│   ├── default.md                   # Default mode instructions
│   ├── execute.md                   # Execute mode instructions
│   ├── pair_programming.md          # Pair programming mode
│   └── plan.md                      # Plan mode instructions
├── compact/
│   ├── prompt.md                    # Compaction system prompt
│   └── summary_prefix.md            # Compaction summary prefix
├── memories/
│   ├── consolidation.md             # Phase 2 consolidation instructions
│   ├── read_path.md                 # Memory read path template
│   ├── stage_one_input.md           # Phase 1 input template
│   └── stage_one_system.md          # Phase 1 system prompt
├── model_instructions/
│   └── gpt-5.2-codex_instructions_template.md
├── personalities/
│   ├── gpt-5.2-codex_friendly.md
│   └── gpt-5.2-codex_pragmatic.md
├── review/
│   ├── exit_interrupted.xml         # Review interrupted template
│   ├── exit_success.xml             # Review success template
│   ├── history_message_completed.md
│   └── history_message_interrupted.md
├── search_tool/
│   ├── tool_description.md          # Tool search description
│   └── tool_suggest_description.md  # Tool suggest description
└── tools/
    └── presentation_artifact.md
```

### 7.2 Template Loading Patterns

| Pattern | Example Files | Use Case |
|---------|---------------|----------|
| `include_str!` | Most `.md` files | Compile-time embedding |
| Runtime file read | `orchestrator.md` (likely) | Dynamic configuration |
| JSON templates | `consequential_tool_message_templates.json` | Structured data |

---

## 8. Conclusion

The `codex-rs/core/templates/agents/orchestrator.md` file is a **critical system component** that defines the foundational behavior of the Codex agent. While it appears simple (a single Markdown file), it orchestrates complex interactions between:

- The user and the primary agent
- The primary agent and sub-agents
- The agent and its tool ecosystem
- Different collaboration modes

Understanding this template is essential for anyone modifying agent behavior, adding new collaboration modes, or debugging agent communication patterns.

**Key Takeaway**: This template is the "constitution" of the Codex agent - it defines not just what the agent can do, but how it should approach problems, communicate with users, and delegate work to specialized sub-agents.
