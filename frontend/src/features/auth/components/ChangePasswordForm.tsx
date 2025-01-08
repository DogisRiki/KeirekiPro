import { Button, PasswordTextField } from "@/components/ui";
import { Box } from "@mui/material";

/**
 * パスワード変更フォーム
 */
export const ChangePasswordForm = () => {
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
            <PasswordTextField
                label="現在のパスワード"
                fullWidth
                required
                placeholder="現在のパスワード"
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 4 }}
            />
            <PasswordTextField
                label="新しいパスワード"
                fullWidth
                required
                placeholder="新しいパスワード"
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 4 }}
            />
            <Button type="submit" sx={{ width: 240, mx: "auto" }}>
                変更
            </Button>
        </Box>
    );
};
