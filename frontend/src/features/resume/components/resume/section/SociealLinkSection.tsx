import { TextField } from "@/components/ui";
import { env } from "@/config/env";

/**
 * ソーシャルリンクセクション
 */
export const SociealLinkSection = () => {
    return (
        <>
            {/* ソーシャル名 */}
            <TextField
                label="ソーシャル名"
                fullWidth
                required
                placeholder="（例）GitHub"
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
            />
        </>
    );
};
