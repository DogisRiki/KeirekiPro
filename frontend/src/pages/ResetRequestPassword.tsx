import { Button } from "@/components/ui";
import { paths } from "@/config/paths";
import { ResetRequestPasswordForm } from "@/features/auth";
import ArrowBackIosNewIcon from "@mui/icons-material/ArrowBackIosNew";
import { Box, Typography } from "@mui/material";

/**
 * パスワードリセットリンク送信画面
 */
export const ResetRequestPassword = () => {
    return (
        <>
            <Box sx={{ width: "100%", textAlign: "left", mb: 4 }}>
                <Button
                    variant="text"
                    startIcon={<ArrowBackIosNewIcon />}
                    onClick={() => (window.location.href = paths.login)}
                    sx={{ typography: "body2" }}
                >
                    ログインへ戻る
                </Button>
            </Box>
            <Typography variant="h5" gutterBottom sx={{ mb: 4 }}>
                パスワードリセット
            </Typography>
            <Typography variant="body1" gutterBottom sx={{ mb: 4 }}>
                ご登録されているメールアドレスを入力してください。
                <br />
                パスワードリセットのためのメールを送信します。
            </Typography>
            <ResetRequestPasswordForm />
        </>
    );
};
