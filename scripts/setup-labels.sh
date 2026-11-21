#!/usr/bin/env bash
# ファクトリーのラベル（ボードのステージ・人間ゲート・状態・種類）を作成 / 更新する。
# 何度実行しても同じ結果になります（既存のラベルは色と説明を上書き）。
#
# 使い方: gh auth login 済みの環境で
#   scripts/setup-labels.sh              # カレントディレクトリのリポジトリ
#   scripts/setup-labels.sh owner/repo   # リポジトリを指定
set -euo pipefail

REPO=${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
echo "Creating factory labels in $REPO"

mk() { gh label create "$1" -R "$REPO" --color "$2" --description "$3" --force >/dev/null && echo "  ✓ $1"; }
# Stages (exactly one per issue / PR)
mk factory:intake            ededed "Stage: Intake (on the board, not started)"
mk factory:triage            c5def5 "Stage: Triage"
mk factory:planning          bfd4f2 "Stage: Planning"
mk factory:building          d4c5f9 "Stage: Building"
mk factory:self-review       d4c5f9 "Stage: Self-review (before the PR exists)"
mk factory:review            fef2c0 "Stage: Review (PR open)"
mk factory:done              0e8a16 "Stage: Done"
# Human gates: add these to move the work forward
mk factory:start             5319e7 "Gate: start the run (Intake -> Triage)"
mk factory:plan              5319e7 "Gate: accept the task / re-plan (-> Planning)"
mk factory:build             5319e7 "Gate: approve the plan (-> Building)"
# Status
mk factory:running           1d76db "Status: an agent is working"
mk factory:waiting           fbca04 "Status: waiting for a person (see the last comment)"
mk factory:needs-info        fbca04 "Status: waiting for the reporter to add details"
mk factory:needs-human       b60205 "Status: escalated, the factory needs a person"
mk factory:approved          0e8a16 "Review: agent approved, waiting for a human merge"
mk factory:changes-requested d93f0b "Review: agent requested changes"
mk factory                   5319e7 "PR opened by the factory"
# Triage classification
mk type:bug                  d73a4a "Type: bug"
mk type:feature              a2eeef "Type: feature"
mk type:chore                cfd3d7 "Type: chore"
mk type:docs                 0075ca "Type: docs"
