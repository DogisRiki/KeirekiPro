import { TextField } from "@/components/ui";
import { env } from "@/config/env";
import { useResumeStore } from "@/features/resume";
import { Box } from "@mui/material";

/**
 * ソーシャルリンクセクション
 */
export const SociealLinkSection = () => {
    // ストアから必要な状態を取得
    const resume = useResumeStore((state) => state.resume);
    const activeEntryId = useResumeStore((state) => state.activeEntryId);
    const updateEntry = useResumeStore((state) => state.updateEntry);

    // 現在アクティブなソーシャルリンクエントリー
    const currentSocialLink = resume?.socialLinks?.find((socialLink) => socialLink.id === activeEntryId) ?? null;

    // エントリーが選択されていない場合
    if (!currentSocialLink) {
        return <Box sx={{ p: 2, color: "text.secondary" }}>左のリストからSNSを選択してください。</Box>;
    }

    return (
        <>
            {/* ソーシャル名 */}
            <TextField
                label="ソーシャル名"
                fullWidth
                required
                placeholder="（例）GitHub"
                value={currentSocialLink.name}
                onChange={(e) => {
                    updateEntry("socialLinks", currentSocialLink.id, { name: e.target.value });
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
                value={currentSocialLink.link}
                onChange={(e) => {
                    updateEntry("socialLinks", currentSocialLink.id, { link: e.target.value });
                }}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
            />
        </>
    );
};
