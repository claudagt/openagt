# log — Knowledge変更履歴の現在セグメント

通常照会では読まない。永続変更は`tools/append-knowledge-log.sh`で記録し、過去行を削除しない。

形式: `YYYY-MM-DD  種別  対象  要約`
種別とローテーションは[KNOWLEDGE.md](../KNOWLEDGE.md)に従う。

---

2026-07-24  migration   knowledge/memory/  AIメモリ並列記録領域を新設（openai.md, anthropic.md）
2026-07-25  migration   knowledge/  DB禁止を「派生索引は許可・正本化は禁止」へ緩和、logの種別定義をKNOWLEDGE.mdへ一本化
2026-07-28  retire      knowledge/memory/  並列記録領域を廃止。製品側メモリを正本から派生するキャッシュへ再定義し、保存先を既存3層へ一本化
2026-08-02  migration   knowledge/  状態付きKnowledge、限定取得、小型index、logローテーション、派生catalogの契約を導入
2026-08-02  migration   knowledge/  log自動ローテーションと規模閾値でのSQLite FTS5自動切替を実装
