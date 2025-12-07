import { TextField } from "@/components/ui";
import { useResumeStore } from "@/features/resume";

/**
 * 自己PRセクション
 */
export const SelfPromotionSection = () => {
    // ストアから必要な状態を取得
    const { resume, activeEntryId, updateEntry } = useResumeStore();

    // 現在アクティブな自己PRエントリー
    const currentSelfPromotion =
        resume?.selfPromotions.find((selfPromotion) => selfPromotion.id === activeEntryId) ?? null;

    return (
        <>
            {/* タイトル */}
            <TextField
                label="タイトル"
                fullWidth
                required
                placeholder="（例）技術的な課題解決能力"
                value={currentSelfPromotion?.title ?? ""}
                onChange={(e) => {
                    if (!currentSelfPromotion) return;
                    updateEntry("selfPromotions", currentSelfPromotion.id, { title: e.target.value });
                }}
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
                value={currentSelfPromotion?.content ?? ""}
                onChange={(e) => {
                    if (!currentSelfPromotion) return;
                    updateEntry("selfPromotions", currentSelfPromotion.id, { content: e.target.value });
                }}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
            />
        </>
    );
};
