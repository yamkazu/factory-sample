#!/usr/bin/env bash
# ファクトリーのラベル（ボードのステージ・人間ゲート・状態・確信度）を作成 / 更新する。
# 何度実行しても同じ結果になります（既存のラベルは色と説明を上書き）。
#
# 使い方: gh auth login 済みの環境で
#   scripts/setup-labels.sh              # カレントディレクトリのリポジトリ
#   scripts/setup-labels.sh owner/repo   # リポジトリを指定
set -euo pipefail

REPO=${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
echo "Creating factory labels in $REPO"

mk() { gh label create "$1" -R "$REPO" --color "$2" --description "$3" --force >/dev/null && echo "  ✓ $1"; }
# Stages (board columns; exactly one per issue / factory PR)
mk factory:backlog       ededed "Stage: Backlog (refinement)"
mk factory:implement     1d76db "Stage: Implement"
mk factory:verify        fbca04 "Stage: Verify (PR open: checks, merge confidence, human review)"
mk factory:done          0e8a16 "Stage: Done"
# Human actions
mk factory               5319e7 "Intake: hand this issue to the factory (starts refinement)"
mk factory:start         5319e7 "Dispatch: start implementing this issue"
# Status
mk factory:running       c5def5 "Status: an agent is working"
mk factory:needs-human   b60205 "Status: the factory stopped and needs a person"
mk factory:needs-review  d93f0b "Merge confidence: concerns a reviewer should look at"
mk factory:conflict      b60205 "The PR conflicts with the base branch (not auto-resolved)"
# Refinement confidence (the weakest of Clarity / Complexity / Verifiability)
mk confidence:1          e99695 "Confidence 1/3: not ready for an agent"
mk confidence:2          f9d0c4 "Confidence 2/3: an agent may need help"
mk confidence:3          c2e0c6 "Confidence 3/3: an agent can do this in one run"
