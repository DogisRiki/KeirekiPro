import { TextField } from "@/components/ui";
import { env } from "@/config/env";

/**
 * ポートフォリオセクション
 */
export const PortfolioSection = () => {
    return (
        <>
            {/* ポートフォリオ名 */}
            <TextField
                label="ポートフォリオ名"
                fullWidth
                required
                placeholder="（例）TaskFlow - タスク管理アプリケーション"
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
                slotProps={{
                    inputLabel: { shrink: true },
                }}
            />
        </>
    );
};
