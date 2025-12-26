import { TextField } from "@/components/ui";
import { useResumeStore } from "@/features/resume";
import { stringListToBulletList } from "@/utils";
import { Box } from "@mui/material";

/**
 * 新規作成時のデフォルト名
 */
const DEFAULT_NAME = "新しい自己PR";

/**
 * 自己PRセクション
 */
export const SelfPromotionSection = () => {
    // ストアから必要な状態を取得
    const resume = useResumeStore((state) => state.resume);
    const activeEntryId = useResumeStore((state) => state.activeEntryId);
    const updateEntry = useResumeStore((state) => state.updateEntry);
    const getEntryErrors = useResumeStore((state) => state.getEntryErrors);

    // 現在アクティブなエントリー
    const currentSelfPromotion = resume?.selfPromotions?.find((s) => s.id === activeEntryId) ?? null;

    // エントリーが選択されていない場合
    if (!currentSelfPromotion) {
        return <Box sx={{ p: 2, color: "text.secondary" }}>左のリストから自己PRを選択してください。</Box>;
    }

    // 現在のエントリーのエラーを取得
    const errors = getEntryErrors(currentSelfPromotion.id);

    /**
     * フォーカス時にデフォルト名をクリア
     */
    const handleTitleFocus = () => {
        if (currentSelfPromotion.title === DEFAULT_NAME) {
            updateEntry("selfPromotions", currentSelfPromotion.id, { title: "" });
        }
    };

    return (
        <>
            {/* タイトル */}
            <TextField
                label="タイトル"
                fullWidth
                required
                placeholder="（例）技術的な課題解決能力"
                value={currentSelfPromotion.title}
                onChange={(e) => updateEntry("selfPromotions", currentSelfPromotion.id, { title: e.target.value })}
                onFocus={handleTitleFocus}
                error={!!errors.title?.length}
                helperText={stringListToBulletList(errors.title)}
                slotProps={{ inputLabel: { shrink: true }, formHelperText: { sx: { whiteSpace: "pre-line" } } }}
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
                value={currentSelfPromotion.content}
                onChange={(e) => updateEntry("selfPromotions", currentSelfPromotion.id, { content: e.target.value })}
                error={!!errors.content?.length}
                helperText={stringListToBulletList(errors.content)}
                slotProps={{ inputLabel: { shrink: true }, formHelperText: { sx: { whiteSpace: "pre-line" } } }}
            />
        </>
    );
};
