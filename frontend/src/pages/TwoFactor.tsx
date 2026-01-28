import { Button } from "@/components/ui";
import { paths } from "@/config/paths";
import { TwoFactorContainer } from "@/features/auth";
import ArrowBackIosNewIcon from "@mui/icons-material/ArrowBackIosNew";
import { Box, Typography } from "@mui/material";

/**
 * 2段階認証画面
 */
export const TwoFactor = () => {
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
                2段階認証
            </Typography>
            <Box sx={{ mb: 4 }}>
                <Typography variant="body1" sx={{ fontSize: { xs: "0.7rem", sm: "1rem" } }}>
                    登録されたメールアドレスに認証コードを送信しました。
                </Typography>
                <Typography variant="body1" sx={{ fontSize: { xs: "0.7rem", sm: "1rem" } }}>
                    メールをご確認のうえ認証コードを入力してください。
                </Typography>
            </Box>
            <TwoFactorContainer />
        </>
    );
};
