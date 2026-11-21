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
  board_sync "$kind" "$n" "$stage"
}

# board_sync <issue|pr> <number> <stage-label>
# Mirror the stage onto the GitHub Projects board (Mastra's kanban). Optional: runs only
# when FACTORY_PROJECT_TOKEN and FACTORY_PROJECT_NUMBER are set. Labels stay the source of
# truth, so a board failure is only a warning.
board_sync() {
  [ -n "${FACTORY_PROJECT_TOKEN:-}" ] && [ -n "${FACTORY_PROJECT_NUMBER:-}" ] || return 0
  _board_sync "$@" || echo "::warning::Project board sync failed for $1 #$2 ($3). Labels are still correct."
}

_board_sync() {
  local kind=$1 n=$2 stage=$3 option path url item meta pid fid oid
  local owner=${FACTORY_PROJECT_OWNER:-${GITHUB_REPOSITORY%%/*}} num=$FACTORY_PROJECT_NUMBER
  case "$stage" in
    factory:intake) option=Intake ;;        factory:triage) option=Triage ;;
    factory:planning) option=Planning ;;    factory:building) option=Building ;;
    factory:self-review) option=Self-review ;; factory:review) option=Review ;;
    factory:done) option=Done ;;            *) return 1 ;;
  esac
  [ "$kind" = pr ] && path=pull || path=issues
  url="https://github.com/$GITHUB_REPOSITORY/$path/$n"
  item=$(GH_TOKEN=$FACTORY_PROJECT_TOKEN gh project item-add "$num" --owner "$owner" --url "$url" --format json --jq .id) || return 1
  pid=$(GH_TOKEN=$FACTORY_PROJECT_TOKEN gh project view "$num" --owner "$owner" --format json --jq .id) || return 1
  meta=$(GH_TOKEN=$FACTORY_PROJECT_TOKEN gh project field-list "$num" --owner "$owner" --format json) || return 1
  fid=$(jq -r '.fields[] | select(.name == "Stage") | .id' <<<"$meta")
  oid=$(jq -r --arg o "$option" '.fields[] | select(.name == "Stage") | .options[] | select(.name == $o) | .id' <<<"$meta")
  [ -n "$fid" ] && [ -n "$oid" ] || return 1
  GH_TOKEN=$FACTORY_PROJECT_TOKEN gh project item-edit --id "$item" --project-id "$pid" \
    --field-id "$fid" --single-select-option-id "$oid" >/dev/null
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
