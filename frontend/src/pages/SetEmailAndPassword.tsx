import { Headline } from "@/components/ui";
import { SetEmailAndPasswordContainer } from "@/features/user";
import { Box, Typography } from "@mui/material";

/**
 * メールアドレス+パスワード設定画面
 */
export const SetEmailAndPassword = () => {
    return (
        <Box sx={{ maxWidth: 600, mx: "auto", py: 4 }}>
            <Headline text={"認証情報の設定"} />
            <Typography variant="body1" gutterBottom sx={{ my: 4, textAlign: "center" }}>
                以下の項目を入力し、設定してください。
            </Typography>
            <SetEmailAndPasswordContainer />
        </Box>
    );
};
