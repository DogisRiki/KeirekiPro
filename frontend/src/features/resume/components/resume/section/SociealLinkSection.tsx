import { TextField } from "@/components/ui";
import { env } from "@/config/env";
import { useResumeStore } from "@/features/resume";

/**
 * ソーシャルリンクセクション
 */
export const SociealLinkSection = () => {
    // ストアから必要な状態を取得
    const { resume, activeEntryId, updateEntry } = useResumeStore();

    // 現在アクティブなソーシャルリンクエントリー
    const currentSocialLink = resume?.socialLinks.find((socialLink) => socialLink.id === activeEntryId) ?? null;

    return (
        <>
            {/* ソーシャル名 */}
            <TextField
                label="ソーシャル名"
                fullWidth
                required
                placeholder="（例）GitHub"
                value={currentSocialLink?.name ?? ""}
                onChange={(e) => {
                    if (!currentSocialLink) return;
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
                value={currentSocialLink?.link ?? ""}
                onChange={(e) => {
                    if (!currentSocialLink) return;
                    updateEntry("socialLinks", currentSocialLink.id, { link: e.target.value });
                }}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
            />
        </>
    );
};
