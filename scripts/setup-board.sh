#!/usr/bin/env bash
# Mastra Factory のカンバンに相当する GitHub Projects ボードを作成する。
# 何度実行しても同じ結果になります（同名のプロジェクト・フィールドがあれば再利用）。
#
# 前提: gh auth login 済みで、project スコープがあること
#   gh auth refresh -s project
#
# 使い方:
#   scripts/setup-board.sh                    # カレントディレクトリのリポジトリ、タイトル "Factory"
#   scripts/setup-board.sh owner/repo "Factory"
set -euo pipefail

REPO=${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
TITLE=${2:-Factory}
OWNER=${REPO%%/*}
STAGES="Intake,Triage,Planning,Building,Self-review,Review,Done"

num=$(gh project list --owner "$OWNER" --limit 200 --format json \
        --jq ".projects[] | select(.title == \"$TITLE\") | .number" | head -1)
if [ -z "$num" ]; then
  num=$(gh project create --owner "$OWNER" --title "$TITLE" --format json --jq .number)
  echo "✓ プロジェクト「$TITLE」を作成しました (#$num)"
else
  echo "✓ 既存のプロジェクト「$TITLE」を使います (#$num)"
fi

if gh project field-list "$num" --owner "$OWNER" --format json --jq '.fields[].name' | grep -qx Stage; then
  echo "✓ Stage フィールドは作成済みです"
  echo "  （選択肢は $STAGES の7つにしてください）"
else
  gh project field-create "$num" --owner "$OWNER" --name Stage \
    --data-type SINGLE_SELECT --single-select-options "$STAGES" >/dev/null
  echo "✓ Stage フィールドを作成しました ($STAGES)"
fi

gh project link "$num" --owner "$OWNER" --repo "$REPO" >/dev/null 2>&1 || true
echo "✓ $REPO にリンクしました"

url=$(gh project view "$num" --owner "$OWNER" --format json --jq .url)
cat <<MSG

次の設定をしてください:
  1. リポジトリ変数 FACTORY_PROJECT_NUMBER=$num を追加
       gh variable set FACTORY_PROJECT_NUMBER -R "$REPO" --body "$num"
     （プロジェクトの持ち主がリポジトリの持ち主と違う場合は FACTORY_PROJECT_OWNER も）
  2. シークレット FACTORY_PROJECT_TOKEN に、project と repo スコープを持つトークンを追加
       gh secret set FACTORY_PROJECT_TOKEN -R "$REPO"
  3. $url を開き、ビューを Board にして「Column by: Stage」を選ぶ
     （Mastra のように Work / Review を分けるなら、フィルタ is:issue と is:pr のビューを2つ作る）
MSG
