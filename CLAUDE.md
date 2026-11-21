# エージェント向けプロジェクトガイド

ファクトリーのすべてのスキル（triage / plan / build / self-review / review / fix）がこのファイルを読みます。
短く正確に保ってください。ファクトリーの出力の質を一番左右するファイルです。

## 規約
- 変更は小さく、Issue に関係することだけにする。
- 振る舞いを変えたら必ずテストを書く。
- ファクトリーの手順は `.claude/skills/factory-*/SKILL.md` にある。手順を変えるときはスキルを PR で変更する。

## チェック
Building / Self-review / Review / Fix が実行するコマンドを書いてください。
<!-- 例:
- `npm ci`
- `npm run lint`
- `npm test`
-->
- （まだコードが無いため、実行するチェックはありません）
