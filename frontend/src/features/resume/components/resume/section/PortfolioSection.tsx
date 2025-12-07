import { TextField } from "@/components/ui";
import { env } from "@/config/env";
import { useResumeStore } from "@/features/resume";

/**
 * ポートフォリオセクション
 */
export const PortfolioSection = () => {
    // ストアから必要な状態を取得
    const { resume, activeEntryId, updateEntry } = useResumeStore();

    // 現在アクティブなポートフォリオエントリー
    const currentPortfolio = resume?.portfolios.find((portfolio) => portfolio.id === activeEntryId) ?? null;

    return (
        <>
            {/* ポートフォリオ名 */}
            <TextField
                label="ポートフォリオ名"
                fullWidth
                required
                placeholder="（例）TaskFlow - タスク管理アプリケーション"
                value={currentPortfolio?.name ?? ""}
                onChange={(e) => {
                    if (!currentPortfolio) return;
                    updateEntry("portfolios", currentPortfolio.id, { name: e.target.value });
                }}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
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
                value={currentPortfolio?.overview ?? ""}
                onChange={(e) => {
                    if (!currentPortfolio) return;
                    updateEntry("portfolios", currentPortfolio.id, { overview: e.target.value });
                }}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 4 }}
            />
            {/* リンク */}
            <TextField
                type="url"
                label="リンク"
                fullWidth
                required
                placeholder={`（例）${env.APP_URL}`}
                value={currentPortfolio?.link ?? ""}
                onChange={(e) => {
                    if (!currentPortfolio) return;
                    updateEntry("portfolios", currentPortfolio.id, { link: e.target.value });
                }}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
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
                value={currentPortfolio?.techStack ?? ""}
                onChange={(e) => {
                    if (!currentPortfolio) return;
                    updateEntry("portfolios", currentPortfolio.id, { techStack: e.target.value });
                }}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
            />
        </>
    );
};
