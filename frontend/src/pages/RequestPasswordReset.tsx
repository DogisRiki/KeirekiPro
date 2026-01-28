import { Button } from "@/components/ui";
import { paths } from "@/config/paths";
import { RequestPasswordResetContainer } from "@/features/auth";
import ArrowBackIosNewIcon from "@mui/icons-material/ArrowBackIosNew";
import { Box, Typography } from "@mui/material";

/**
 * パスワードリセット要求
 */
export const RequestPasswordReset = () => {
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
            <Box sx={{ mb: 4 }}>
                <Typography variant="body1" sx={{ fontSize: { xs: "0.7rem", sm: "1rem" } }}>
                    ご登録されているメールアドレスを入力してください。
                </Typography>
                <Typography variant="body1" sx={{ fontSize: { xs: "0.7rem", sm: "1rem" } }}>
                    パスワードリセットのためのメールを送信します。
                </Typography>
            </Box>
            <RequestPasswordResetContainer />
        </>
    );
};
