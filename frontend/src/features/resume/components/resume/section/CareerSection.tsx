import { Checkbox, DatePicker, TextField } from "@/components/ui";
import { useResumeStore } from "@/features/resume";
import { stringListToBulletList } from "@/utils";
import { Box, FormControlLabel } from "@mui/material";
import type { Dayjs } from "dayjs";
import dayjs from "dayjs";

/**
 * 新規作成時のデフォルト名
 */
const DEFAULT_NAME = "新しい職歴";

/**
 * 職歴セクション
 */
export const CareerSection = () => {
    // ストアから必要な状態を取得
    const resume = useResumeStore((state) => state.resume);
    const activeEntryId = useResumeStore((state) => state.activeEntryId);
    const updateEntry = useResumeStore((state) => state.updateEntry);
    const getEntryErrors = useResumeStore((state) => state.getEntryErrors);

    // 現在アクティブなエントリー
    const currentCareer = resume?.careers?.find((career) => career.id === activeEntryId) ?? null;

    // エントリーが選択されていない場合
    if (!currentCareer) {
        return <Box sx={{ p: 2, color: "text.secondary" }}>一覧から職歴を選択してください。</Box>;
    }

    // 現在のエントリーのエラーを取得
    const errors = getEntryErrors(currentCareer.id);

    // 入社年月ハンドラー
    const handleStartDateChange = (newValue: Dayjs | null) => {
        if (!currentCareer) return;
        updateEntry("careers", currentCareer.id, {
            startDate: newValue ? newValue.format("YYYY-MM") : "",
        });
    };

    // 退職年月ハンドラー
    const handleEndDateChange = (newValue: Dayjs | null) => {
        if (!currentCareer || currentCareer.active) return;
        updateEntry("careers", currentCareer.id, {
            endDate: newValue ? newValue.format("YYYY-MM") : null,
        });
    };

    // チェックボックスハンドラー
    const handleIsActiveChange = () => {
        if (!currentCareer) return;
        const newActive = !currentCareer.active;
        updateEntry("careers", currentCareer.id, {
            active: newActive,
            endDate: newActive ? null : currentCareer.endDate,
        });
    };

    /**
     * フォーカス時にデフォルト名をクリア
     */
    const handleCompanyNameFocus = () => {
        if (currentCareer.companyName === DEFAULT_NAME) {
            updateEntry("careers", currentCareer.id, { companyName: "" });
        }
    };

    return (
        <>
            {/* 会社名 */}
            <TextField
                label="会社名"
                fullWidth
                required
                placeholder="（例）株式会社ABC"
                value={currentCareer.companyName}
                onChange={(e) => {
                    updateEntry("careers", currentCareer.id, { companyName: e.target.value });
                }}
                onFocus={handleCompanyNameFocus}
                error={!!errors.companyName?.length}
                helperText={stringListToBulletList(errors.companyName)}
                slotProps={{
                    inputLabel: { shrink: true },
                    formHelperText: { sx: { whiteSpace: "pre-line" } },
                }}
                sx={{ mb: 4 }}
            />
            {/* 入社年月 */}
            <DatePicker
                label="入社年月"
                value={currentCareer.startDate ? dayjs(currentCareer.startDate, "YYYY-MM") : null}
                onChange={handleStartDateChange}
                views={["year", "month"]}
                format="YYYY/MM"
                slotProps={{
                    textField: {
                        fullWidth: true,
                        required: true,
                        sx: { mb: 2 },
                        InputLabelProps: { shrink: true },
                        error: !!errors.startDate?.length,
                        helperText: stringListToBulletList(errors.startDate),
                        FormHelperTextProps: { sx: { whiteSpace: "pre-line" } },
                    },
                    calendarHeader: { format: "YYYY/MM" },
                }}
            />
            {/* 在職中チェックボックス */}
            <Box sx={{ display: "flex", justifyContent: "flex-end" }}>
                <FormControlLabel
                    control={<Checkbox checked={currentCareer.active} onChange={handleIsActiveChange} />}
                    label="在職中"
                    sx={{
                        color: "text.secondary",
                        m: 0,
                    }}
                />
            </Box>
            {/* 退職年月 */}
            <DatePicker
                label="退職年月"
                format="YYYY/MM"
                value={currentCareer.endDate ? dayjs(currentCareer.endDate, "YYYY-MM") : null}
                onChange={handleEndDateChange}
                disabled={currentCareer.active}
                slotProps={{
                    textField: {
                        fullWidth: true,
                        required: !currentCareer.active,
                        InputLabelProps: { shrink: true },
                        error: !!errors.endDate?.length,
                        helperText: stringListToBulletList(errors.endDate),
                        FormHelperTextProps: { sx: { whiteSpace: "pre-line" } },
                    },
                    calendarHeader: { format: "YYYY/MM" },
                }}
                views={["year", "month"]}
            />
        </>
    );
};
