import { DatePicker, TextField } from "@/components/ui";
import { Dayjs } from "dayjs";
import { useState } from "react";

/**
 * 資格セクション
 */
export const CertificationSection = () => {
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
