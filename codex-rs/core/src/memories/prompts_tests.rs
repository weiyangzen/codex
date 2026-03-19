use super::*;
use crate::models_manager::model_info::model_info_from_slug;
use pretty_assertions::assert_eq;
use tempfile::tempdir;
use tokio::fs;

#[test]
fn build_stage_one_input_message_truncates_rollout_using_model_context_window() {
    let input = format!("{}{}{}", "a".repeat(700_000), "middle", "z".repeat(700_000));
    let mut model_info = model_info_from_slug("gpt-5.2-codex");
    model_info.context_window = Some(123_000);
    let expected_rollout_token_limit = usize::try_from(
        ((123_000_i64 * model_info.effective_context_window_percent) / 100)
            * phase_one::CONTEXT_WINDOW_PERCENT
            / 100,
    )
    .unwrap();
    let expected_truncated = truncate_text(
        &input,
        TruncationPolicy::Tokens(expected_rollout_token_limit),
    );
    let message = build_stage_one_input_message(
        &model_info,
        Path::new("/tmp/rollout.jsonl"),
        Path::new("/tmp"),
        &input,
    )
    .unwrap();

    assert!(expected_truncated.contains("tokens truncated"));
    assert!(expected_truncated.starts_with('a'));
    assert!(expected_truncated.ends_with('z'));
    assert!(message.contains(&expected_truncated));
}

#[test]
fn build_stage_one_input_message_uses_default_limit_when_model_context_window_missing() {
    let input = format!("{}{}{}", "a".repeat(700_000), "middle", "z".repeat(700_000));
    let mut model_info = model_info_from_slug("gpt-5.2-codex");
    model_info.context_window = None;
    let expected_truncated = truncate_text(
        &input,
        TruncationPolicy::Tokens(phase_one::DEFAULT_STAGE_ONE_ROLLOUT_TOKEN_LIMIT),
    );
    let message = build_stage_one_input_message(
        &model_info,
        Path::new("/tmp/rollout.jsonl"),
        Path::new("/tmp"),
        &input,
    )
    .unwrap();

    assert!(message.contains(&expected_truncated));
}

#[test]
fn render_prompt_template_replaces_placeholders_without_touching_inserted_text() {
    let rendered = render_prompt_template(
        "first={{ first }} second={{ second }}",
        &[("first", "{{ second }}"), ("second", "done")],
    )
    .unwrap();

    assert_eq!(rendered, "first={{ second }} second=done");
}

#[tokio::test]
async fn build_memory_tool_developer_instructions_renders_template_values() {
    let codex_home = tempdir().expect("tempdir");
    let memory_root = memory_root(codex_home.path());
    fs::create_dir_all(&memory_root)
        .await
        .expect("create memory root");
    fs::write(memory_root.join("memory_summary.md"), "summary text")
        .await
        .expect("write memory summary");

    let instructions = build_memory_tool_developer_instructions(codex_home.path())
        .await
        .expect("memory instructions");

    assert!(instructions.contains("summary text"));
    assert!(instructions.contains(memory_root.to_string_lossy().as_ref()));
    assert!(!instructions.contains("{{"));
}
