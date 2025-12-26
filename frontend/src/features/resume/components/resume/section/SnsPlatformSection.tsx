import { Autocomplete, TextField } from "@/components/ui";
import { env } from "@/config/env";
import { useResumeStore, useSnsPlatformList } from "@/features/resume";
import { stringListToBulletList } from "@/utils";
import { Box } from "@mui/material";
import { useState } from "react";

/**
 * 新規作成時のデフォルト名
 */
const DEFAULT_NAME = "新しいSNSプラットフォーム";

/**
 * SNSプラットフォームリンクセクション
 */
export const SnsPlatformSection = () => {
    // ストアから必要な状態を取得
    const resume = useResumeStore((state) => state.resume);
    const activeEntryId = useResumeStore((state) => state.activeEntryId);
    const updateEntry = useResumeStore((state) => state.updateEntry);
    const getEntryErrors = useResumeStore((state) => state.getEntryErrors);

    // SNSプラットフォーム一覧を取得
    const { data: snsPlatformData } = useSnsPlatformList();
    const snsPlatformOptions = snsPlatformData?.names ?? [];

    // 入力値の状態管理（フォーカス時クリア用）
    const [inputValue, setInputValue] = useState<string | null>(null);

    // 現在アクティブなエントリー
    const currentSnsPlatform = resume?.snsPlatforms?.find((s) => s.id === activeEntryId) ?? null;

    // エントリーが選択されていない場合
    if (!currentSnsPlatform) {
        return <Box sx={{ p: 2, color: "text.secondary" }}>左のリストからSNSを選択してください。</Box>;
    }

    // 現在のエントリーのエラーを取得
    const errors = getEntryErrors(currentSnsPlatform.id);

    // プラットフォーム名変更ハンドラー
    const handleNameChange = (_: React.SyntheticEvent, newValue: string | string[] | null) => {
        const value = Array.isArray(newValue) ? (newValue[0] ?? "") : (newValue ?? "");
        updateEntry("snsPlatforms", currentSnsPlatform.id, { name: value });
        setInputValue(null); // 選択後はinputValueをリセット
    };

    // プラットフォーム名入力ハンドラー
    const handleNameInputChange = (_: React.SyntheticEvent, newInputValue: string) => {
        setInputValue(newInputValue);
        if (newInputValue !== currentSnsPlatform.name) {
            updateEntry("snsPlatforms", currentSnsPlatform.id, { name: newInputValue });
        }
    };

    /**
     * フォーカス時にデフォルト名をクリア
     */
    const handleNameFocus = () => {
        if (currentSnsPlatform.name === DEFAULT_NAME) {
            updateEntry("snsPlatforms", currentSnsPlatform.id, { name: "" });
            setInputValue("");
        }
    };

    return (
        <>
            {/* プラットフォーム名 */}
            <Autocomplete
                freeSolo
                options={snsPlatformOptions}
                value={currentSnsPlatform.name}
                inputValue={inputValue ?? currentSnsPlatform.name}
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
                        onFocus={handleNameFocus}
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
                value={currentSnsPlatform.link}
                onChange={(e) => updateEntry("snsPlatforms", currentSnsPlatform.id, { link: e.target.value })}
                error={!!errors.link?.length}
                helperText={stringListToBulletList(errors.link)}
                slotProps={{ inputLabel: { shrink: true }, formHelperText: { sx: { whiteSpace: "pre-line" } } }}
            />
        </>
    );
};
