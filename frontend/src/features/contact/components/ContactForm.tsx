import { Button, TextField } from "@/components/ui";
import { Box } from "@mui/material";

/**
 * お問い合わせフォーム
 */
export const ContactForm = () => {
    // 送信処理
    const handleSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        // TODO: API呼び出し
        alert("送信");
    };
    return (
        <Box
            component="form"
            sx={{ display: "flex", flexDirection: "column", justifyContent: "center" }}
            onSubmit={handleSubmit}
        >
            <TextField
                label="件名"
                fullWidth
                required
                placeholder="ここに件名をご記載ください。"
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 4 }}
            />
            <TextField
                label="内容"
                fullWidth
                required
                multiline
                minRows={8}
                placeholder="ここにお問い合わせ内容をご記載ください。"
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 4 }}
            />
            <Button type="submit" sx={{ width: 240, mx: "auto" }}>
                送信
            </Button>
        </Box>
    );
};
