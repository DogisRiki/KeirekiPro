import { DatePicker, TextField } from "@/components/ui";
import { useResumeStore } from "@/features/resume/stores/resumeStore";
import { Stack } from "@mui/material";
import dayjs, { Dayjs } from "dayjs";
import { useEffect, useState } from "react";

/**
 * 基本情報セクション
 */
export const BasicInfoSection = () => {
    // データを取り出す
    const { resume } = useResumeStore();

    // フォームの状態
    const [formState, setFormState] = useState<{
        resumeName: string;
        date: Dayjs | null;
        lastName: string;
        firstName: string;
    }>({
        resumeName: "",
        date: dayjs(),
        lastName: "",
        firstName: "",
    });

    // resumeの変更を監視してローカルステートを更新
    useEffect(() => {
        if (resume) {
            setFormState({
                resumeName: resume.resumeName || "",
                date: resume.date ? dayjs(resume.date) : null,
                lastName: resume.lastName ?? "",
                firstName: resume.firstName ?? "",
            });
        }
    }, [resume]);

    // 入力変更ハンドラー
    const handleInputChange = (key: keyof typeof formState, value: unknown) => {
        setFormState((prev) => ({ ...prev, [key]: value } as typeof prev));
    };

    return (
        <>
            {/* 職務経歴書名 */}
            <TextField
                label="職務経歴書名"
                value={formState.resumeName}
                onChange={(e) => handleInputChange("resumeName", e.target.value)}
                fullWidth
                required
                placeholder="（例）株式会社ABC用の職務経歴書"
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 4 }}
            />
            {/* 日付 */}
            <DatePicker
                label="作成日"
                value={formState.date}
                onChange={(newValue) => handleInputChange("date", newValue)}
                views={["year", "month", "day"]}
                format="YYYY/MM/DD"
                slotProps={{
                    textField: {
                        fullWidth: true,
                        required: true,
                        sx: { mb: 4 },
                        InputLabelProps: { shrink: true },
                    },
                    calendarHeader: { format: "YYYY/MM/DD" },
                }}
            />
            {/* 姓・名 */}
            <Stack direction={{ xs: "column", sm: "row" }} spacing={4}>
                <TextField
                    label="姓"
                    value={formState.lastName}
                    onChange={(e) => handleInputChange("lastName", e.target.value)}
                    fullWidth
                    required
                    placeholder="山田"
                    slotProps={{
                        inputLabel: { shrink: true },
                    }}
                />
                <TextField
                    label="名"
                    value={formState.firstName}
                    onChange={(e) => handleInputChange("firstName", e.target.value)}
                    fullWidth
                    required
                    placeholder="太郎"
                    slotProps={{
                        inputLabel: { shrink: true },
                    }}
                />
            </Stack>
        </>
    );
};
