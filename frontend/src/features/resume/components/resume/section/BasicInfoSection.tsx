import { DatePicker, TextField } from "@/components/ui";
import { useResumeStore } from "@/features/resume";
import type { Dayjs } from "dayjs";
import dayjs from "dayjs";

/**
 * 基本情報セクション
 */
export const BasicInfoSection = () => {
    // ストアから必要な状態を取得
    const resume = useResumeStore((state) => state.resume);
    const updateResume = useResumeStore((state) => state.updateResume);

    // resumeがnullの場合は何も表示しない
    if (!resume) {
        return null;
    }

    // 日付ハンドラー
    const handleDateChange = (newValue: Dayjs | null) => {
        updateResume({
            date: newValue ? newValue.format("YYYY-MM-DD") : "",
        });
    };

    return (
        <>
            {/* 職務経歴書名 */}
            <TextField
                label="職務経歴書名"
                fullWidth
                required
                placeholder="（例）KeirekiPro"
                value={resume.resumeName}
                onChange={(e) => {
                    updateResume({ resumeName: e.target.value });
                }}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 4 }}
            />
            {/* 日付 */}
            <DatePicker
                label="日付"
                value={resume.date ? dayjs(resume.date, "YYYY-MM-DD") : null}
                onChange={handleDateChange}
                format="YYYY/MM/DD"
                slotProps={{
                    textField: {
                        fullWidth: true,
                        required: true,
                        sx: { mb: 4 },
                        InputLabelProps: { shrink: true },
                    },
                }}
            />
            {/* 姓 */}
            <TextField
                label="姓"
                fullWidth
                required
                placeholder="（例）山田"
                value={resume.lastName ?? ""}
                onChange={(e) => {
                    updateResume({ lastName: e.target.value });
                }}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 4 }}
            />
            {/* 名 */}
            <TextField
                label="名"
                fullWidth
                required
                placeholder="（例）太郎"
                value={resume.firstName ?? ""}
                onChange={(e) => {
                    updateResume({ firstName: e.target.value });
                }}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
            />
        </>
    );
};
