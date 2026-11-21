# Shared helpers for the factory workflows. Source it from a step:
#   source .github/factory/lib.sh
# Requires GH_TOKEN and GITHUB_REPOSITORY.
#
# The board: every work item (issue) and change request (PR) carries exactly one
# stage label, mirroring Mastra Factory's default stages.
set -euo pipefail

FACTORY_STAGES="factory:intake factory:triage factory:planning factory:building factory:self-review factory:review factory:done"
FACTORY_TMP=.factory-tmp

# set_stage <issue|pr> <number> <stage-label>
set_stage() {
  local kind=$1 n=$2 stage=$3 s args=()
  for s in $FACTORY_STAGES; do [ "$s" = "$stage" ] || args+=(--remove-label "$s"); done
  gh "$kind" edit "$n" -R "$GITHUB_REPOSITORY" --add-label "$stage" "${args[@]}" >/dev/null
}

add_label()    { gh "$1" edit "$2" -R "$GITHUB_REPOSITORY" --add-label "$3" >/dev/null; }
remove_label() { local kind=$1 n=$2; shift 2; local l; for l in "$@"; do gh "$kind" edit "$n" -R "$GITHUB_REPOSITORY" --remove-label "$l" >/dev/null 2>&1 || true; done; }
say()          { gh "$1" comment "$2" -R "$GITHUB_REPOSITORY" --body "$3" >/dev/null; }

# post_file <issue|pr> <number> <file>: post an agent-written comment if it exists.
post_file() { if [ -s "$3" ]; then gh "$1" comment "$2" -R "$GITHUB_REPOSITORY" --body-file "$3" >/dev/null; fi; }

# escalate <issue|pr> <number> <message>: hand the item to a human and fail the job.
escalate() {
  remove_label "$1" "$2" factory:running
  add_label "$1" "$2" factory:needs-human
  say "$1" "$2" "🏭 Factory: $3 人間の確認が必要です（\`factory:needs-human\`）。"
  echo "::error::$3"
  exit 1
}

# accept_handoff <issue|pr> <number> <allowed verdict>...
# Typed handoff: validate .factory-tmp/result.json and export VERDICT. Bad data stops
# here, at the boundary, instead of flowing into the next stage.
accept_handoff() {
  local kind=$1 n=$2 v a; shift 2
  [ -s "$FACTORY_TMP/result.json" ] || escalate "$kind" "$n" "エージェントが引き継ぎ（result.json）を出力しませんでした。"
  v=$(jq -er '.verdict | strings' "$FACTORY_TMP/result.json" 2>/dev/null) \
    || escalate "$kind" "$n" "引き継ぎ（result.json）の形式が不正です。"
  for a in "$@"; do
    if [ "$v" = "$a" ]; then VERDICT=$v; export VERDICT; echo "verdict=$v"; return 0; fi
  done
  escalate "$kind" "$n" "想定外の判定 \`$v\` です（許可: $*）。"
}

# field <name>: read a field from result.json ('' if missing).
field() { jq -r --arg k "$1" '.[$k] // "" | tostring' "$FACTORY_TMP/result.json"; }

# dispatch <workflow-file> key=value...: start the next stage. Events created with
# GITHUB_TOKEN do not trigger workflows, but workflow_dispatch is the exception.
dispatch() {
  local wf=$1 args=() kv; shift
  for kv in "$@"; do args+=(-f "$kv"); done
  gh workflow run "$wf" -R "$GITHUB_REPOSITORY" --ref "${DEFAULT_BRANCH:?}" "${args[@]}"
}
