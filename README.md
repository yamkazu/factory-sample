# factory-sample

[Mastra Factory](https://factory.mastra.ai/what-is-factory)（[解説記事](https://mastra.ai/blog/software-factory)）の流れと仕組みを参考にした、
**GitHub Actions だけで動くソフトウェアファクトリー**のサンプルです。

Issue は Mastra Factory と同じステージ（Intake → Triage → Planning → Building → Self-review → Review → Done）を流れます。
各ステージは独立したエージェント実行（[`anthropics/claude-code-action`](https://github.com/anthropics/claude-code-action)）で、
手順は [`.claude/skills/`](.claude/skills) のスキル（日本語）に書かれています。人間が持つゲートは「開始」「受け入れ」「計画の承認」「マージ」です。

## 流れ

```
Issue 作成
  │  factory:intake        ボードに載るだけ。まだ何も動かない
  │
  │  ◆ 人間: factory:start を付ける（FACTORY_AUTO_START=true なら信頼できる作成者の Issue は自動）
  ▼
Triage                     factory-triage スキル: 履歴調査・根本原因・種類/深刻度/確信度/工数
  │  needs-info ─► 報告者がコメント ─► 再 Triage
  │  ready
  │  ├─ bug ─────────────────────────► 自動で Planning へ
  │  └─ それ以外 ◆ 人間: factory:plan を付けて受け入れる
  ▼
Planning                   factory-plan スキル: フェーズ別の計画・採用しなかった案・前提
  │  ◆ 人間: factory:build を付けて計画を承認（やり直しはコメント + factory:plan）
  ▼
Building                   factory-build スキル: 実装・回帰テスト・チェック・プッシュ（PR はまだ作らない）
  │  計画が誤っていた ─► Planning に差し戻し
  ▼
Self-review                factory-self-review スキル: 別セッションでブランチをレビュー
  │  request-changes ─► Building（修正モード）─► Self-review（1回まで）
  ▼
PR 作成（Issue のタイトル、Closes #N）
  ▼
Review                     factory-review スキル: 独立したセッションで PR をレビュー
  │  request-changes ─► factory-fix スキル ─► 再レビュー（FACTORY_MAX_FIX_ROUNDS 回まで、超えたら needs-human）
  │  approve
  │  ◆ 人間: マージ
  ▼
Done                       PR と Issue に factory:done（同じ Issue の PR が他に開いていれば待つ）
```

## Mastra Factory との対応

| Mastra Factory | このリポジトリ |
| --- | --- |
| Work board / Review board（カンバン画面） | GitHub Projects のボード（`Stage` 列）。ステージラベル `factory:intake` 〜 `factory:done` から自動で同期 |
| ステージごとのスキル（`factory-skills/factory-*/SKILL.md`） | [`.claude/skills/factory-*/SKILL.md`](.claude/skills)（triage / plan / build / self-review / review / fix） |
| `factory-phase` シグナル | 各エージェントへのプロンプト先頭の `factory-phase:` |
| 型付きの遷移（`factory_transition_work_item` / `factory_record_review_verdict`） | エージェントは `.factory-tmp/result.json` を書くだけ。ワークフローが [`lib.sh`](.github/factory/lib.sh) の `accept_handoff` で検証してからラベル・コメント・次ステージを動かす。不正なら境界で止めて `factory:needs-human` |
| セッションごとのサンドボックス | ステージごとに新しい GitHub ホストランナー |
| 作成とは別のレビューセッション | Self-review と Review はそれぞれ新しいエージェント実行 |
| レビューの指摘は作成側に戻る | `factory-fix` が直して再レビュー。`@claude` メンションで人間も直接指示できる |
| Review の結果に `Reviewed head` | `result.json` の `reviewed_head` が PR のヘッドと一致しないと受け付けない |
| 人間ゲート: 開始・受け入れ（bug 以外）・計画承認・マージ | `factory:start`・`factory:plan`・`factory:build`・通常のマージ |
| ステージの自動開始（条件を満たすアイテム） | `FACTORY_AUTO_START` / `FACTORY_AUTO_ACCEPT` |
| ステージごとのモデル指定 | `FACTORY_MODEL_TRIAGE` / `_PLAN` / `_BUILD` / `_REVIEW` |
| 計画の保存 `.artifacts/plans/issue-N.md` | Building が同じパスにコミット |
| エージェントの指示を承認する（すべての PR ではなく） | スキルはリポジトリ内にあり、変更は PR でレビュー |

省略しているもの: ボード上でカードを動かしてステージを進める操作（ラベルで行います）、Linear / Slack / Jira 連携、監視ループ（Sentry → Triage）、ドキュメントのずれ検出、アプリのプレビュー、画面を使った確認。

## カンバン（GitHub Projects）

Mastra Factory のボード画面の代わりに、GitHub Projects のボードを使います。
ステージが変わるたびに、ワークフローが Issue / PR をプロジェクトに追加し、`Stage` 列（Intake / Triage / Planning / Building / Self-review / Review / Done）を更新します。
ボードは表示用で、正しい状態はラベルです。ボードの更新に失敗してもファクトリーは止まりません（警告だけ出ます）。
ボード上でカードを動かしてもステージは変わりません。ステージを進めるのはゲートのラベルです。

セットアップ:

1. `gh auth refresh -s project` で、手元の `gh` に project スコープを付ける。
2. `scripts/setup-board.sh` を実行する。プロジェクト「Factory」と `Stage` フィールドを作り、リポジトリにリンクします（何度実行しても大丈夫です）。
3. 表示された番号をリポジトリ変数 `FACTORY_PROJECT_NUMBER` に設定する。
4. シークレット `FACTORY_PROJECT_TOKEN` を追加する。`GITHUB_TOKEN` では Projects を操作できないためです。
   - 個人アカウントのプロジェクト: **classic PAT** に `project` と `repo` スコープ
   - Organization のプロジェクト: fine-grained PAT（Organization の Projects: Read and write、リポジトリの Issues / Pull requests: Read）か GitHub App のトークン
5. プロジェクトを開き、ビューを **Board** にして **Column by: Stage** を選ぶ。
   Mastra のように Work board と Review board を分けるなら、フィルタ `is:issue` と `is:pr` のビューを2つ作る。

トークンはラベルを操作するステップにだけ渡し、エージェントのステップには渡しません。

## ラベル

| 種類 | ラベル |
| --- | --- |
| ステージ | `factory:intake` `factory:triage` `factory:planning` `factory:building` `factory:self-review` `factory:review` `factory:done` |
| 人間ゲート（付けると進む） | `factory:start` `factory:plan` `factory:build` |
| 状態 | `factory:running` `factory:waiting` `factory:needs-info` `factory:needs-human` `factory:approved` `factory:changes-requested` |
| 仕分け結果 | `type:bug` `type:feature` `type:chore` `type:docs` |
| ファクトリーが作った PR | `factory` |

エージェントは GitHub に書き込みません（読み取り系の `gh` だけ許可）。ラベルとコメントは、引き継ぎを検証したワークフローが付けます。

## ワークフロー

| ファイル | きっかけ | ステージ |
| --- | --- | --- |
| `factory-intake-triage.yml` | Issue 作成、`factory:start`、needs-info への返信 | Intake → Triage |
| `factory-plan.yml` | `factory:plan`、bug の自動受け入れ、Building からの差し戻し | Planning |
| `factory-build.yml` | `factory:build` | Building → Self-review → PR 作成 |
| `factory-review.yml` | Building / Fix からの起動、人間が開いた PR | Review |
| `factory-fix.yml` | Review からの起動 | Review（修正） |
| `factory-done.yml` | ファクトリーの PR がマージされた | Done |
| `factory-assist.yml` | コメントの `@claude` | 人間との対話 |

`GITHUB_TOKEN` で行った操作は他のワークフローを起動しないため、ステージ間は `workflow_dispatch` で明示的につないでいます。

## セットアップ

1. リポジトリのシークレットに `ANTHROPIC_API_KEY` か `CLAUDE_CODE_OAUTH_TOKEN`（`claude setup-token` で取得）のどちらかを追加する。
2. Settings → Actions → General → Workflow permissions を **Read and write** にし、
   **Allow GitHub Actions to create and approve pull requests** にチェックを入れる。
3. `gh auth login` 済みの手元の環境で `scripts/setup-labels.sh` を実行し、ラベルを作る（何度実行しても大丈夫です。別のリポジトリなら `scripts/setup-labels.sh owner/repo`）。
4. （任意）カンバンを使う場合は、上の「カンバン（GitHub Projects）」の手順を行う。
5. `@claude` メンションを使う場合は [Claude GitHub App](https://github.com/apps/claude) をインストールする。
6. [`CLAUDE.md`](CLAUDE.md) の「チェック」にテストなどのコマンドを書き、`factory-build.yml` / `factory-fix.yml` にツールチェーンのセットアップを追加する。

任意のリポジトリ変数:

| 変数 | 既定値 | 用途 |
| --- | --- | --- |
| `FACTORY_AUTO_START` | `false` | `true` なら OWNER / MEMBER / COLLABORATOR が作った Issue は自動で Triage 開始 |
| `FACTORY_AUTO_ACCEPT` | `false` | `true` なら bug 以外も受け入れゲートを飛ばして Planning へ |
| `FACTORY_MAX_FIX_ROUNDS` | `2` | Review ⇄ Fix の最大回数 |
| `FACTORY_MODEL` | ステージ別の既定 | 全ステージのモデル |
| `FACTORY_MODEL_TRIAGE` | `claude-sonnet-5-5` | Triage のモデル |
| `FACTORY_MODEL_PLAN` / `_BUILD` / `_REVIEW` | `claude-opus-5-5` | ステージ別のモデル |
| `FACTORY_PROJECT_NUMBER` | なし | カンバンにするプロジェクトの番号（設定するとボード同期が有効） |
| `FACTORY_PROJECT_OWNER` | リポジトリの持ち主 | プロジェクトの持ち主 |
| `FACTORY_CHECK_TOOLS` | npm / pytest / make など | エージェントが実行してよいチェック用コマンド |

## 使い方

1. Issue を作る（`factory:intake` が付く）。
2. 着手するなら `factory:start` を付ける。
3. 質問されたら（`factory:needs-info`）コメントで答える。
4. bug 以外は、仕分け結果を見て `factory:plan` で受け入れる。
5. 計画を読み、`factory:build` で承認する。
6. PR に `factory:approved` が付いたら、内容を確認してマージする。

## 注意点

- `GITHUB_TOKEN` によるプッシュや PR では、既存の CI などのワークフローが動きません。必須チェックを使う場合は GitHub App のトークン（`actions/create-github-app-token`）に切り替えてください。
- Issue や PR の本文はエージェントにとって信用しない入力です。ステージを進めるラベルは書き込み権限のある人しか付けられず、各エージェントの使えるツールは絞ってあります。`FACTORY_CHECK_TOOLS` を広げるときは注意してください。
- フロントエンドの見た目の確認はしません（Mastra も、テストだけでは足りない点として挙げています）。
