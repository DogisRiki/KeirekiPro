import { Button, PasswordTextField } from "@/components/ui";
import { Box } from "@mui/material";

/**
 * パスワードリセットフォーム
 */
export const ResetPasswordForm = () => {
    // 送信処理
    const handlePasswordReset = (e: React.FormEvent) => {
        e.preventDefault();
        // TODO: API呼び出し
        alert("パスワードリセット");
    };

    return (
        <Box component="form" onSubmit={handlePasswordReset}>
            <PasswordTextField
                label="新しいパスワード"
                placeholder="新しいパスワード"
                fullWidth
                required
                margin="normal"
            />
            <PasswordTextField
                label="新しいパスワード(確認用)"
                placeholder="新しいパスワード(確認用)"
                fullWidth
                required
                margin="normal"
            />
            <Button type="submit" sx={{ mt: 2 }}>
                パスワードを変更
            </Button>
        </Box>
    );
};
