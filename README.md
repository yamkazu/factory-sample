# factory-sample

**GitHub Actions だけで動くソフトウェアファクトリー**のサンプルです。
流れと仕組みは [SuperPlane](https://github.com/superplanehq/superplane)（オープンソースのソフトウェアファクトリー）の公式実装に合わせています。

Issue をバックログでリファインメント（採点と仕様づくり）し、人が着手を決めると、エージェントが1回の実行で実装して PR を出します。
PR では CI を待って失敗を自動修正し（上限3回）、マージ確信度を報告します。マージするかは人が決めます。
各ステップは毎回新しいエージェント実行（[`anthropics/claude-code-action`](https://github.com/anthropics/claude-code-action)）で、
手順は [`.claude/skills/`](.claude/skills) のスキル（日本語）に書かれています。

## 流れ

```
Issue に factory ラベル                         ◆ 人: ファクトリーに渡す
  ▼
Backlog    factory-refine: Clarity / Complexity / Verifiability を 1〜3 で採点し、仕様を書く
  │        確信度 = 3つの最小値（confidence:1〜3 ラベル）。必要なときだけ質問する
  │        `/factory ...` コメントで回答・相談・計画の更新（毎回新しい実行が Issue の計画を読み直す）
  │
  │  ◆ 人: factory:start を付けて着手（FACTORY_AUTO_DISPATCH=true なら確信度 3・質問なしで自動）
  ▼
Implement  factory-implement: 仕様どおりに factory/issue-N で実装・テスト・プッシュ（1回の実行）
  │        ワークフローが PR を作成（Closes #N を付与）
  ▼
Verify     PR が開く・コミットが増えるたびに:
  │        ├ merge-confidence: risk / security / drift / reversibility / performance を 1〜5 で採点し、
  │        │  1つのコメントとコミットステータスで報告。競合は検知して報告のみ（自動解消しない）
  │        │  着手した人にレビューを依頼
  │        └ checks: CI の完了を待ち、失敗したら factory-fix-checks で自動修正（PR ごとに最大3回）
  │        `/factory ...` を PR のコメント・レビューに書くと factory-pr-feedback が対応（メンション時のみ）
  │
  │  ◆ 人: レビューしてマージ
  ▼
Done       PR と Issue に factory:done（マージせずに閉じたら Issue は Backlog に戻る）
```

## SuperPlane との対応

| SuperPlane（公式ソース） | このリポジトリ |
| --- | --- |
| ボードの列 Backlog / Implement / Verify / Done | ステージラベル `factory:backlog` 〜 `factory:done`、任意で GitHub Projects ボード（表示専用） |
| Ingest: `factory` ラベルで Work Order を作成 | `factory` ラベルで Backlog に入り、リファインメント開始 |
| Backlog リファインメント（Clarity / Complexity / Verifiability、確信度は最小値、質問は人にしか決められないことだけ） | `factory-refine` スキル。計画ターン / 回答ターンの区別も同じ |
| Dispatch → Implement line（1回の実行、質問しない、前提は PR に書く） | `factory:start` → `factory-implement` スキル |
| Fix pull request checks（チェックを待ち、失敗したら1回の修正実行。上限は既定3回、待機は回数を消費しない） | `factory-verify.yml` の checks ジョブ → `factory-fix-checks.yml` |
| Address PR feedback（`@superplaneagent` メンション時のみ） | `/factory` で始まるコメント・レビューのみ（GitHub のメンション通知を避けるためスラッシュ形式） |
| Merge confidence（PR が開く・更新されるたびに risk / performance / security / drift / reversibility） | `factory-merge-confidence` スキル。古いヘッドの結果は公開しない |
| 競合はマージ可否の判定でブロックするだけ | `factory:conflict` ラベルとレポートで知らせるだけ |
| Review request（レビュアーを選ぶ） | 着手した人（`factory:start` を付けた人）にレビューを依頼する簡略版 |
| 人がマージ、PR closure で Work Order を閉じる | 人がマージ、`factory-closure.yml` で Done |
| 毎回新しい会話。経緯は Work Order のコメント・成果物・ブランチ・PR から渡す | 同じ。Issue の計画コメント、PR 本文、ブランチ、失敗ログ、レビューコメントを渡す |
| 構造化された結果を読み取りステップで検証 | エージェントは `.factory-tmp/result.json` を書くだけ。ワークフローが [`lib.sh`](.github/factory/lib.sh) で検証してから GitHub を更新 |

### 以前の Mastra 寄りの設計から残したもの・やめたもの

- **残した**: スキルを `.claude/skills/` に置く形、型付きの引き継ぎ（エージェントは GitHub に書き込まない）、ラベル = 状態の正、表示専用のボード同期。
- **やめた**: Triage と Planning の分離（SuperPlane のリファインメント1つに統合）、Self-review ステージ、エージェント同士の Review ⇄ Fix ループ（CI の自動修正とマージ確信度の報告に置き換え、判断は人）、bug 以外の受け入れゲート（確信度と `factory:start` に置き換え）、`@claude` 汎用アシスト（`/factory` に統一）。

## ラベル

| 種類 | ラベル |
| --- | --- |
| ステージ | `factory:backlog` `factory:implement` `factory:verify` `factory:done` |
| 人の操作 | `factory`（ファクトリーに渡す）、`factory:start`（着手） |
| 状態 | `factory:running` `factory:needs-human` `factory:needs-review` `factory:conflict` |
| 確信度 | `confidence:1` `confidence:2` `confidence:3` |

## ワークフロー

| ファイル | きっかけ | 役割 |
| --- | --- | --- |
| `factory-refine.yml` | `factory` ラベル、Backlog の Issue への `/factory` コメント | Backlog のリファインメント |
| `factory-implement.yml` | `factory:start`、自動ディスパッチ | 実装して PR を作る |
| `factory-verify.yml` | PR の作成・更新、ファクトリーのプッシュ後 | マージ確信度、CI 待ちと自動修正の起動 |
| `factory-fix-checks.yml` | verify から起動 | 失敗したチェックの修正 |
| `factory-pr-feedback.yml` | PR の `/factory` コメント・レビュー | フィードバック対応 |
| `factory-closure.yml` | ファクトリーの PR が閉じた | Done / Backlog に戻す |

## セットアップ

1. リポジトリのシークレットに `ANTHROPIC_API_KEY` か `CLAUDE_CODE_OAUTH_TOKEN`（`claude setup-token` で取得）を追加する。
2. Settings → Actions → General → Workflow permissions を **Read and write** にし、
   **Allow GitHub Actions to create and approve pull requests** にチェックを入れる。
3. `gh auth login` 済みの手元で `scripts/setup-labels.sh` を実行してラベルを作る（何度実行しても大丈夫）。
4. **GitHub App のトークン（推奨）**: `GITHUB_TOKEN` で行ったプッシュや PR では CI が動かないため、CI の結果を待って直すには App が必要です。
   1. Settings → Developer settings → GitHub Apps → New GitHub App で App を作る（Webhook はオフで可）。
      Repository permissions: **Contents: Read and write**、**Pull requests: Read and write**、**Issues: Read and write**、**Workflows: Read and write**（ワークフローファイルを変更する場合のみ）。
   2. App をこのリポジトリにインストールする。
   3. リポジトリ変数 `FACTORY_APP_ID` に App ID、シークレット `FACTORY_APP_PRIVATE_KEY` に秘密鍵（.pem の中身）を設定する。

   設定しない場合も動きますが、ファクトリーのプッシュでは CI が走らないため、CI の自動修正は実質働きません（マージ確信度はワークフローから直接起動します）。
5. （任意）カンバンを使う場合は、下の「カンバン（GitHub Projects）」の手順を行う。
6. [`CLAUDE.md`](CLAUDE.md) の「チェック」にテストなどのコマンドを書き、`factory-implement.yml` / `factory-fix-checks.yml` / `factory-pr-feedback.yml` にツールチェーンのセットアップを追加する。

任意のリポジトリ変数:

| 変数 | 既定値 | 用途 |
| --- | --- | --- |
| `FACTORY_AUTO_DISPATCH` | `false` | `true` なら確信度 3 で質問のない計画は自動で実装開始 |
| `FACTORY_MAX_FIX_ATTEMPTS` | `3` | PR ごとの CI 自動修正の上限 |
| `FACTORY_CHECKS_TIMEOUT_MINUTES` | `60` | CI の完了を待つ時間 |
| `FACTORY_REQUIRED_CHECKS` | すべて | 待つ・直す対象のチェック名（カンマ区切り）。`Factory:` で始まるワークフローは常に除外 |
| `FACTORY_APP_ID` | なし | GitHub App の ID（上記） |
| `FACTORY_MODEL` | ステージ別の既定 | 全ステップのモデル |
| `FACTORY_MODEL_REFINE` / `_IMPLEMENT` / `_VERIFY` | `claude-opus-5-5` | ステップ別のモデル |
| `FACTORY_CHECK_TOOLS` | npm / pytest / make など | エージェントが実行してよいチェック用コマンド |
| `FACTORY_PROJECT_NUMBER` / `FACTORY_PROJECT_OWNER` | なし | カンバン用（下記） |

## カンバン（GitHub Projects）

ステージが変わるたびに、ワークフローが Issue / PR を GitHub Projects のボードに追加し、`Stage` 列（Backlog / Implement / Verify / Done）を更新します。
ボードは**表示専用（読み取り専用）**で、正しい状態はラベルです。更新に失敗してもファクトリーは止まりません（警告だけ）。
**ボード上でカードを動かしてもステージは進みません。** 操作はラベル（`factory` / `factory:start`）とマージで行います。

1. `gh auth refresh -s project` で、手元の `gh` に project スコープを付ける。
2. `scripts/setup-board.sh` を実行する（プロジェクト「Factory」と `Stage` フィールドを作り、リポジトリにリンク）。
3. 表示された番号をリポジトリ変数 `FACTORY_PROJECT_NUMBER` に設定する。
4. シークレット `FACTORY_PROJECT_TOKEN` を追加する（`GITHUB_TOKEN` では Projects を操作できないため）。
   - 個人アカウントのプロジェクト: **classic PAT** に `project` と `repo` スコープ
   - Organization のプロジェクト: fine-grained PAT（Organization の Projects: Read and write、リポジトリの Issues / Pull requests: Read）か GitHub App のトークン
5. プロジェクトのビューを **Board** にして **Column by: Stage** を選ぶ。

トークンはラベルを操作するステップにだけ渡し、エージェントのステップには渡しません。

## 使い方

1. Issue を作り、`factory` ラベルを付ける。リファインメントの結果（スコアと仕様）がコメントされる。
2. 質問があれば `/factory 〇〇にしてください` のようにコメントで答える。相談だけなら回答が返り、決定を伝えれば計画が更新される。
3. 計画に納得したら `factory:start` を付ける。
4. PR ができたら、マージ確信度のレポートと CI を見てレビューする。直してほしい点は `/factory 〇〇を直して` とコメントする。
5. マージする。

### 例

README にライセンスの節を足す小さな Issue を、ファクトリーに通す例です。`gh` のコマンドで書いていますが、Web UI で同じ操作をしてもかまいません。

Issue を作り、`factory` ラベルを付けます。

```sh
gh issue create --title "README にライセンスの節を追加する" \
  --body "README の末尾に、MIT ライセンスであることを書いた節を追加したい。" \
  --label factory
```

数分で、リファインメントのコメントが付きます。スコアの表と仕様が書かれ、確信度のラベル（この例では `confidence:3`）が付きます。

```
## リファインメント

| Clarity | Complexity | Verifiability |
| --- | --- | --- |
| 3 | 3 | 3 |

# README にライセンスの節を追加する
...
```

質問があれば、`/factory` で始まるコメントで答えます。決定を伝えると、計画が更新されます。

```sh
gh issue comment 12 --body "/factory 節の見出しは「ライセンス」にしてください"
```

計画に納得したら、`factory:start` を付けて着手します。

```sh
gh issue edit 12 --add-label factory:start
```

エージェントがブランチ `factory/issue-12` で実装し、PR を作ります。PR にはマージ確信度のコメントが付きます。
直してほしい点があれば、PR に `/factory` で始まるコメントを書きます。

```sh
gh pr comment factory/issue-12 --body "/factory 見出しのレベルを ## にそろえて"
```

レビューしてマージすると、Issue と PR に `factory:done` が付きます。

## 注意点

- CI の完了待ちはランナー上でポーリングするため、待っている間も Actions の実行時間を使います。
- Issue や PR の本文はエージェントにとって信用しない入力です。ステップを動かすラベルや `/factory` は、書き込み権限のある人（リファインメントでは Issue の作成者も）しか使えません。各エージェントの使えるツールは絞ってあります。`FACTORY_CHECK_TOOLS` を広げるときは注意してください。
- 競合は解消しません。`factory:conflict` が付いたら、人が解消するか、`/factory main をマージして競合を解消して` と依頼してください。
- フロントエンドの見た目の確認（SuperPlane の visual evidence）は入れていません。
