import { Autocomplete, DatePicker, TextField } from "@/components/ui";
import { useCertificationList, useResumeStore } from "@/features/resume";
import { stringListToBulletList } from "@/utils";
import { Box } from "@mui/material";
import type { Dayjs } from "dayjs";
import dayjs from "dayjs";
import { useState } from "react";

/**
 * 新規作成時のデフォルト名
 */
const DEFAULT_NAME = "新しい資格";

/**
 * 資格セクション
 */
export const CertificationSection = () => {
    // ストアから必要な状態を取得
    const resume = useResumeStore((state) => state.resume);
    const activeEntryId = useResumeStore((state) => state.activeEntryId);
    const updateEntry = useResumeStore((state) => state.updateEntry);
    const getEntryErrors = useResumeStore((state) => state.getEntryErrors);

    // 資格一覧を取得
    const { data: certificationData } = useCertificationList();
    const certificationOptions = certificationData?.names ?? [];

    // 入力値の状態管理（フォーカス時クリア用）
    const [inputValue, setInputValue] = useState<string | null>(null);

    // 現在アクティブなエントリー
    const currentCertification = resume?.certifications?.find((cert) => cert.id === activeEntryId) ?? null;

    // エントリーが選択されていない場合
    if (!currentCertification) {
        return <Box sx={{ p: 2, color: "text.secondary" }}>左のリストから資格を選択してください。</Box>;
    }

    // 現在のエントリーのエラーを取得
    const errors = getEntryErrors(currentCertification.id);

    // 取得年月ハンドラー
    const handleDateChange = (newValue: Dayjs | null) => {
        if (!currentCertification) return;
        updateEntry("certifications", currentCertification.id, {
            date: newValue ? newValue.format("YYYY-MM") : "",
        });
    };

    // 資格名変更ハンドラー
    const handleNameChange = (_: React.SyntheticEvent, newValue: string | string[] | null) => {
        const value = Array.isArray(newValue) ? (newValue[0] ?? "") : (newValue ?? "");
        updateEntry("certifications", currentCertification.id, { name: value });
        setInputValue(null); // 選択後はinputValueをリセット
    };

    // 資格名入力ハンドラー
    const handleNameInputChange = (_: React.SyntheticEvent, newInputValue: string) => {
        setInputValue(newInputValue);
        if (newInputValue !== currentCertification.name) {
            updateEntry("certifications", currentCertification.id, { name: newInputValue });
        }
    };

    /**
     * フォーカス時にデフォルト名をクリア
     */
    const handleNameFocus = () => {
        if (currentCertification.name === DEFAULT_NAME) {
            updateEntry("certifications", currentCertification.id, { name: "" });
            setInputValue("");
        }
    };

    return (
        <>
            {/* 資格名 */}
            <Autocomplete
                freeSolo
                options={certificationOptions}
                value={currentCertification.name}
                inputValue={inputValue ?? currentCertification.name}
                onChange={handleNameChange}
                onInputChange={handleNameInputChange}
                renderInput={(params) => (
                    <TextField
                        {...params}
                        label="資格名"
                        required
                        placeholder="（例）基本情報処理技術者"
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
            {/* 取得年月 */}
            <DatePicker
                label="取得年月"
                value={currentCertification.date ? dayjs(currentCertification.date, "YYYY-MM") : null}
                onChange={handleDateChange}
                views={["year", "month"]}
                format="YYYY/MM"
                slotProps={{
                    textField: {
                        fullWidth: true,
                        required: true,
                        InputLabelProps: { shrink: true },
                        error: !!errors.date?.length,
                        helperText: stringListToBulletList(errors.date),
                        FormHelperTextProps: { sx: { whiteSpace: "pre-line" } },
                    },
                    calendarHeader: { format: "YYYY/MM" },
                }}
            />
        </>
    );
};
