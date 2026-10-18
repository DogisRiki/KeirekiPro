# 場面の記録

この文書は、場面が頼る Claude Code の機能を試した結果と、場面ごとの結果を残す。会話の出来事の記録そのものは scratchpad の `scenes/logs/` に残し、この文書にはコミットしない。

## 頼る機能の試し

Claude は、ホストの `claude -p "ok と1語で答えて"` が「ok」と答えたことで、所有者のログインを確かめた(2026-10-19)。続けて、Claude は、`run-scene.sh probe` で、使い捨ての写しの中で各機能を1回ずつ試した。日時は日本時間である。

| 番号 | 機能 | 試した日時 | 結果 | 根拠 |
|---|---|---|---|---|
| 1 | `-p` のプロンプトの先頭の `/<スキル名>` を展開してスキルを動かす | 2026-10-19T00:06:05+09:00 | 動いた | `/verify-frontend` の会話を保存した記録に、写しの中の道(`scenes\work\probe\repo\.claude\skills\verify-frontend`)を持つ「Base directory for this skill:」の行が出た |
| 2 | `--resume <セッションID>` で同じ会話を続ける | 2026-10-19T00:07:10+09:00 | 動いた | 2回目の答えが、1回目に覚えさせた「kumquat-6395」を含んだ |
| 3 | `-p --resume <ID> "/compact"` で会話を圧縮する | 2026-10-19T00:07:24+09:00 | 動いた | `/compact` のあとの `instructions.log` に、SessionStart の `source` が `compact` の出来事が出た |
| 4 | `-p` で `/loop` を1回だけ動かす | 2026-10-19T00:07:57+09:00 | 動いた | `/loop` の会話が結果を出して終わり、`ScheduleWakeup` と `CronCreate` の呼び出しが無かった |
| 5 | `--strict-mcp-config` と空の `--mcp-config` で、MCP のサーバーとコネクタをつながない | 2026-10-19T00:06:05+09:00 | 動いた | `system/init` の `mcp_servers` が空だった |
| 6 | フックの出力の `continue: false` で会話を止める | 2026-10-19T00:08:17+09:00 | 動いた | `stop-before-write.sh` が止めた書き込みの記録があり、写しに止めたファイルもそのあとのファイルも無かった |
| 7 | InstructionsLoaded の `load_reason` が `compact`、SessionStart の `source` が `compact` | 2026-10-19T00:07:24+09:00 | 動いた | `/compact` のあとの `instructions.log` に、SessionStart の `source` が `compact` の出来事が出た |
| 8 | `--settings` で禁止の規則とフックと `env` を足す | 2026-10-19T00:08:51+09:00 | 動いた | `settings-scene.json` の禁止の規則だけで禁じた `WebFetch` が、`system/init` の道具に無かった |
