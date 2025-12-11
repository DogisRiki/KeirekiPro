import { Button, Select, TextField } from "@/components/ui";
import type { ResumeSummary } from "@/features/resume";
import { useErrorMessageStore } from "@/stores";
import { stringListToBulletList } from "@/utils";
import { Box, FormControl, FormHelperText, InputLabel, MenuItem } from "@mui/material";

export interface CreateResumeFormProps {
    resumeName: string;
    copySourceId: string;
    copySourceOptions: ResumeSummary[];
    onResumeNameChange: (v: string) => void;
    onCopySourceChange: (v: string) => void;
    onSubmit: () => void;
    loading?: boolean;
}

/**
 * 職務経歴書新規作成フォーム
 */
export const CreateResumeForm = ({
    resumeName,
    copySourceId,
    copySourceOptions,
    onResumeNameChange,
    onCopySourceChange,
    onSubmit,
    loading = false,
}: CreateResumeFormProps) => {
    const { errors } = useErrorMessageStore();

    return (
        <Box
            component="form"
            sx={{ display: "flex", flexDirection: "column", justifyContent: "center" }}
            onSubmit={(e) => {
                e.preventDefault();
                onSubmit();
            }}
        >
            {/* 職務経歴書名 */}
            <TextField
                label="職務経歴書名"
                fullWidth
                required
                value={resumeName}
                onChange={(e) => onResumeNameChange(e.target.value)}
                error={!!errors.resumeName?.length}
                helperText={stringListToBulletList(errors.resumeName)}
                placeholder="（例）株式会社ABC用の職務経歴書"
                slotProps={{
                    inputLabel: { shrink: true },
                    formHelperText: { sx: { whiteSpace: "pre-line" } },
                    htmlInput: {
                        maxLength: 50,
                    },
                }}
                sx={{ mb: 4 }}
            />

            {/* コピー元職務経歴書 */}
            <FormControl fullWidth sx={{ mb: 4 }} error={!!errors.resumeId?.length}>
                <InputLabel shrink>コピー元職務経歴書</InputLabel>
                <Select
                    value={copySourceId}
                    onChange={(e) => onCopySourceChange(e.target.value)}
                    label="コピー元職務経歴書"
                    displayEmpty
                    notched
                    renderValue={(selected) => {
                        // 未選択時（プレースホルダー表示）
                        if (!selected) {
                            return <Box sx={{ color: (theme) => theme.palette.text.disabled }}>未選択</Box>;
                        }
                        // 選択済み時
                        const option = copySourceOptions.find((resume) => resume.id === selected);
                        return option?.resumeName ?? "";
                    }}
                >
                    {/* プルダウン内の「未選択」行 */}
                    <MenuItem
                        value=""
                        sx={{
                            color: (theme) => theme.palette.text.disabled,
                            fontStyle: "italic",
                        }}
                    >
                        未選択
                    </MenuItem>
                    {copySourceOptions.map((resume) => (
                        <MenuItem key={resume.id} value={resume.id}>
                            {resume.resumeName}
                        </MenuItem>
                    ))}
                </Select>
                <FormHelperText sx={{ whiteSpace: "pre-line" }}>
                    {stringListToBulletList(errors.resumeId)}
                </FormHelperText>
            </FormControl>

            {/* 作成ボタン */}
            <Button type="submit" sx={{ width: 240, mx: "auto" }} disabled={loading}>
                作成
            </Button>
        </Box>
    );
};
