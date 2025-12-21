import { Autocomplete, TextField } from "@/components/ui";
import { env } from "@/config/env";
import { useResumeStore, useSnsPlatformList } from "@/features/resume";
import { stringListToBulletList } from "@/utils";
import { Box } from "@mui/material";

/**
 * プラットフォームリンクセクション
 */
export const SociealLinkSection = () => {
    // ストアから必要な状態を取得
    const resume = useResumeStore((state) => state.resume);
    const activeEntryId = useResumeStore((state) => state.activeEntryId);
    const updateEntry = useResumeStore((state) => state.updateEntry);
    const getEntryErrors = useResumeStore((state) => state.getEntryErrors);

    // SNSプラットフォーム一覧を取得
    const { data: snsPlatformData } = useSnsPlatformList();
    const snsPlatformOptions = snsPlatformData?.names ?? [];

    // 現在アクティブなエントリー
    const currentSocialLink = resume?.socialLinks?.find((s) => s.id === activeEntryId) ?? null;

    // エントリーが選択されていない場合
    if (!currentSocialLink) {
        return <Box sx={{ p: 2, color: "text.secondary" }}>左のリストからSNSを選択してください。</Box>;
    }

    // 現在のエントリーのエラーを取得
    const errors = getEntryErrors(currentSocialLink.id);

    // プラットフォーム名変更ハンドラー
    const handleNameChange = (_: React.SyntheticEvent, newValue: string | string[] | null) => {
        const value = Array.isArray(newValue) ? (newValue[0] ?? "") : (newValue ?? "");
        updateEntry("socialLinks", currentSocialLink.id, { name: value });
    };

    // プラットフォーム名入力ハンドラー（値が変更された場合のみ更新）
    const handleNameInputChange = (_: React.SyntheticEvent, newInputValue: string) => {
        if (newInputValue !== currentSocialLink.name) {
            updateEntry("socialLinks", currentSocialLink.id, { name: newInputValue });
        }
    };

    return (
        <>
            {/* プラットフォーム名 */}
            <Autocomplete
                freeSolo
                options={snsPlatformOptions}
                value={currentSocialLink.name}
                onChange={handleNameChange}
                onInputChange={handleNameInputChange}
                renderInput={(params) => (
                    <TextField
                        {...params}
                        label="プラットフォーム名"
                        required
                        placeholder="（例）GitHub"
                        error={!!errors.name?.length}
                        helperText={stringListToBulletList(errors.name)}
                        slotProps={{
                            inputLabel: { shrink: true },
                            formHelperText: { sx: { whiteSpace: "pre-line" } },
                        }}
                    />
                )}
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
                onChange={(e) => updateEntry("socialLinks", currentSocialLink.id, { link: e.target.value })}
                error={!!errors.link?.length}
                helperText={stringListToBulletList(errors.link)}
                slotProps={{ inputLabel: { shrink: true }, formHelperText: { sx: { whiteSpace: "pre-line" } } }}
            />
        </>
    );
};
