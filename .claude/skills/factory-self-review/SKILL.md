---
name: factory-self-review
description: ソフトウェアファクトリーの Self-review ステージ。PR を作る前に、プッシュ済みの作業ブランチを実装とは別のセッションでレビューし、approve か request-changes を判定する。
---

# factory-self-review: PR 作成前のセルフレビュー

あなたは実装とは**別のセッション**で、PR を作る前の作業ブランチをレビューします。コードは変更しません。

## 入力
- Issue 番号、作業ブランチ、ベースブランチはプロンプトで渡されます。作業ブランチはチェックアウト済みです。
- 計画は `.artifacts/plans/issue-<n>.md`、または Issue の最新の `<!-- factory:plan -->` コメントです。
- 実装の説明は `.factory-tmp/pr-body.md` です。主張は鵜呑みにせず、自分で確かめます。

## 手順
1. 計画を読み、自分ならどう実装するかを先に考えてから、`git diff origin/<base>...HEAD` を読む。
2. `CLAUDE.md` と計画にあるテスト・型チェックなどを自分で実行する。
3. 指摘を2種類に分ける。
   - **必須（差し戻す）**: 正しさの欠陥、安全性の問題、修正内容に対するテスト不足、問題と関係のない差分の増加
   - **今後の課題（差し戻さない）**: それ以外すべて（好み、改善提案、別 Issue にすべきこと）

## 出力（引き継ぎ）
`.factory-tmp/` はコミットしません。

### `.factory-tmp/self-review.md`
```
## 結果
1〜3文の要約

## 確認
実行したコマンドと結果

## 必要な修正
番号付き、ファイル:行 と具体的な直し方。なければ「なし」

## 今後の課題
箇条書き。なければ「なし」
```

### `.factory-tmp/result.json`
```json
{ "verdict": "approve", "required_changes": 0, "rationale": "..." }
```
「必要な修正」が1つでもあれば `request-changes`、なければ `approve`。
