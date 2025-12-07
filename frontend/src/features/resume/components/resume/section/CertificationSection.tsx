import { DatePicker, TextField } from "@/components/ui";
import { useResumeStore } from "@/features/resume";
import { Dayjs } from "dayjs";
import { useState } from "react";

/**
 * 資格セクション
 */
export const CertificationSection = () => {
    // ストアから必要な状態を取得
    const { resume, activeEntryId, updateEntry } = useResumeStore();

    // 現在アクティブな資格エントリー
    const currentCertification = resume?.certifications.find((cert) => cert.id === activeEntryId) ?? null;

    // 取得年月
    const [date, setDate] = useState<Dayjs | null>(null);

    // 取得年月ハンドラー
    const handleDateChange = (newValue: Dayjs | null) => {
        setDate(newValue);
    };

    return (
        <>
            {/* 資格名 */}
            <TextField
                label="資格名"
                fullWidth
                required
                placeholder="（例）基本情報処理技術者"
                value={currentCertification?.name ?? ""}
                onChange={(e) => {
                    if (!currentCertification) return;
                    updateEntry("certifications", currentCertification.id, { name: e.target.value });
                }}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 4 }}
            />
            {/* 取得年月 */}
            <DatePicker
                label="取得年月"
                value={date}
                onChange={handleDateChange}
                views={["year", "month"]}
                format="YYYY/MM"
                slotProps={{
                    textField: {
                        fullWidth: true,
                        required: true,
                        InputLabelProps: { shrink: true },
                    },
                    calendarHeader: { format: "YYYY/MM" },
                }}
            />
        </>
    );
};
