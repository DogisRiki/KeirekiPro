import { Checkbox, DatePicker, TextField } from "@/components/ui";
import { useResumeStore } from "@/features/resume";
import { Box, FormControlLabel } from "@mui/material";
import type { Dayjs } from "dayjs";
import { useState } from "react";

/**
 * 職歴セクション
 */
export const CareerSection = () => {
    // ストアから必要な状態を取得
    const { resume, activeEntryId, updateEntry } = useResumeStore();

    // 現在アクティブな職歴エントリー
    const currentCareer = resume?.careers.find((career) => career.id === activeEntryId) ?? null;

    // 入社年月
    const [startDate, setStartDate] = useState<Dayjs | null>(null);
    // 退職年月
    const [endDate, setEndDate] = useState<Dayjs | null>(null);
    // 在職中チェックボックス
    const [isEmployed, setIsEmployed] = useState(false);

    // 入社年月ハンドラー
    const handleStartDateChange = (newValue: Dayjs | null) => {
        setStartDate(newValue);
    };

    // 退職年月ハンドラー
    const handleEndDateChange = (newValue: Dayjs | null) => {
        if (!isEmployed) {
            setEndDate(newValue);
        }
    };

    // チェックボックスハンドラー
    const handleIsAssignedChange = () => {
        setIsEmployed((prev) => !prev);
        if (!isEmployed) {
            setEndDate(null);
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
                value={currentCareer?.companyName ?? ""}
                onChange={(e) => {
                    if (!currentCareer) return;
                    updateEntry("careers", currentCareer.id, { companyName: e.target.value });
                }}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 4 }}
            />
            {/* 入社年月 */}
            <DatePicker
                label="入社年月"
                value={startDate}
                onChange={handleStartDateChange}
                views={["year", "month"]}
                format="YYYY/MM"
                slotProps={{
                    textField: {
                        fullWidth: true,
                        required: true,
                        sx: { mb: 2 },
                        InputLabelProps: { shrink: true },
                    },
                    calendarHeader: { format: "YYYY/MM" },
                }}
            />
            {/* 在職中チェックボックス */}
            <Box sx={{ display: "flex", justifyContent: "flex-end" }}>
                <FormControlLabel
                    control={<Checkbox />}
                    label="在職中"
                    checked={isEmployed}
                    onChange={handleIsAssignedChange}
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
                value={endDate}
                onChange={handleEndDateChange}
                disabled={isEmployed}
                slotProps={{
                    textField: {
                        fullWidth: true,
                        required: !isEmployed,
                        InputLabelProps: { shrink: true },
                    },
                    calendarHeader: { format: "YYYY/MM" },
                }}
                views={["year", "month"]}
            />
        </>
    );
};
