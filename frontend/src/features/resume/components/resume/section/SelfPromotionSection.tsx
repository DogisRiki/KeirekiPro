import { TextField } from "@/components/ui";

/**
 * 自己PRセクション
 */
export const SelfPromotionSection = () => {
    return (
        <>
            {/* タイトル */}
            <TextField
                label="タイトル"
                fullWidth
                required
                placeholder="（例）技術的な課題解決能力"
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 4 }}
            />
            {/* コンテンツ */}
            <TextField
                label="内容"
                fullWidth
                required
                multiline
                minRows={10}
                placeholder="（例）常に技術トレンドをキャッチアップし、適切な技術選定と実装を行うことができます。 特に、パフォーマンス最適化とスケーラブルなアーキテクチャ設計に強みがあり、 前職では機能改善により平均レスポンスタイムを60%削減した実績があります。"
                slotProps={{
                    inputLabel: { shrink: true },
                }}
            />
        </>
    );
};
