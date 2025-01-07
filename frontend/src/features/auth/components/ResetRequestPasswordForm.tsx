import { Button, TextField } from "@/components/ui";
import { env } from "@/config/env";
import { Box } from "@mui/material";

/**
 * リセットリンク送信フォーム
 */
export const ResetRequestPasswordForm = () => {
    // 登録処理
    const handleRegister = (e: React.FormEvent) => {
        e.preventDefault();
        // TODO: API呼び出し
        alert("送信");
    };
    return (
        <Box component="form" onSubmit={handleRegister}>
            {/* メールアドレス */}
            <TextField
                type="email"
                label="メールアドレス"
                fullWidth
                required
                placeholder={env.APP_EMAIL}
                margin="normal"
                slotProps={{
                    inputLabel: { shrink: true },
                }}
            />
            {/* 送信ボタン */}
            <Button type="submit" sx={{ mt: 2 }}>
                送信
            </Button>
        </Box>
    );
};
