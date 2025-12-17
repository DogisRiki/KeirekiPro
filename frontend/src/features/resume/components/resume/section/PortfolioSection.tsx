import { TextField } from "@/components/ui";
import { env } from "@/config/env";
import { useResumeStore } from "@/features/resume";
import { stringListToBulletList } from "@/utils";
import { Box } from "@mui/material";

/**
 * ポートフォリオセクション
 */
export const PortfolioSection = () => {
    // ストアから必要な状態を取得
    const resume = useResumeStore((state) => state.resume);
    const activeEntryId = useResumeStore((state) => state.activeEntryId);
    const updateEntry = useResumeStore((state) => state.updateEntry);
    const getEntryErrors = useResumeStore((state) => state.getEntryErrors);

    // 現在アクティブなエントリー
    const currentPortfolio = resume?.portfolios?.find((p) => p.id === activeEntryId) ?? null;

    // エントリーが選択されていない場合
    if (!currentPortfolio) {
        return <Box sx={{ p: 2, color: "text.secondary" }}>左のリストからポートフォリオを選択してください。</Box>;
    }

    // 現在のエントリーのエラーを取得
    const errors = getEntryErrors(currentPortfolio.id);

    return (
        <>
            {/* ポートフォリオ名 */}
            <TextField
                label="ポートフォリオ名"
                fullWidth
                required
                placeholder="（例）TaskFlow - タスク管理アプリケーション"
                value={currentPortfolio.name}
                onChange={(e) => updateEntry("portfolios", currentPortfolio.id, { name: e.target.value })}
                error={!!errors.name?.length}
                helperText={stringListToBulletList(errors.name)}
                slotProps={{ inputLabel: { shrink: true }, formHelperText: { sx: { whiteSpace: "pre-line" } } }}
                sx={{ mb: 4 }}
            />
            {/* ポートフォリオ概要 */}
            <TextField
                label="ポートフォリオ概要"
                fullWidth
                required
                multiline
                minRows={8}
                placeholder="（例）個人の生産性向上のためのタスク管理アプリケーション。 React Hooksを活用した効率的なステート管理と、 Firebaseを用いたリアルタイムデータ同期を実装。"
                value={currentPortfolio.overview}
                onChange={(e) => updateEntry("portfolios", currentPortfolio.id, { overview: e.target.value })}
                error={!!errors.overview?.length}
                helperText={stringListToBulletList(errors.overview)}
                slotProps={{ inputLabel: { shrink: true }, formHelperText: { sx: { whiteSpace: "pre-line" } } }}
                sx={{ mb: 4 }}
            />
            {/* リンク */}
            <TextField
                type="url"
                label="リンク"
                fullWidth
                required
                placeholder={`（例）${env.APP_URL}`}
                value={currentPortfolio.link}
                onChange={(e) => updateEntry("portfolios", currentPortfolio.id, { link: e.target.value })}
                error={!!errors.link?.length}
                helperText={stringListToBulletList(errors.link)}
                slotProps={{ inputLabel: { shrink: true }, formHelperText: { sx: { whiteSpace: "pre-line" } } }}
                sx={{ mb: 4 }}
            />
            {/* 技術スタック */}
            <TextField
                label="技術スタック"
                fullWidth
                required
                multiline
                minRows={4}
                placeholder="（例）React, TypeScript, Firebase"
                value={currentPortfolio.techStack}
                onChange={(e) => updateEntry("portfolios", currentPortfolio.id, { techStack: e.target.value })}
                error={!!errors.techStack?.length}
                helperText={stringListToBulletList(errors.techStack)}
                slotProps={{ inputLabel: { shrink: true }, formHelperText: { sx: { whiteSpace: "pre-line" } } }}
            />
        </>
    );
};
