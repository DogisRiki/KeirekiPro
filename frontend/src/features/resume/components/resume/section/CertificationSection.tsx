import { DatePicker, TextField } from "@/components/ui";
import { useResumeStore } from "@/features/resume";
import { Box } from "@mui/material";
import type { Dayjs } from "dayjs";
import dayjs from "dayjs";

/**
 * 資格セクション
 */
export const CertificationSection = () => {
    // ストアから必要な状態を取得
    const resume = useResumeStore((state) => state.resume);
    const activeEntryId = useResumeStore((state) => state.activeEntryId);
    const updateEntry = useResumeStore((state) => state.updateEntry);

    // 現在アクティブな資格エントリー
    const currentCertification = resume?.certifications?.find((cert) => cert.id === activeEntryId) ?? null;

    // エントリーが選択されていない場合
    if (!currentCertification) {
        return <Box sx={{ p: 2, color: "text.secondary" }}>左のリストから資格を選択してください。</Box>;
    }

    // 取得年月ハンドラー
    const handleDateChange = (newValue: Dayjs | null) => {
        if (!currentCertification) return;
        updateEntry("certifications", currentCertification.id, {
            date: newValue ? newValue.format("YYYY-MM") : "",
        });
    };

    return (
        <>
            {/* 資格名 */}
            <TextField
                label="資格名"
                fullWidth
                required
                placeholder="（例）基本情報処理技術者"
                value={currentCertification.name}
                onChange={(e) => {
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
                value={currentCertification.date ? dayjs(currentCertification.date, "YYYY-MM") : null}
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
