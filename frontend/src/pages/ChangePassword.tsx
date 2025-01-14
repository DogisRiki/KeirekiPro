import { Headline } from "@/components/ui";
import { ChangePasswordForm } from "@/features/auth";
import { useUserAuthStore } from "@/stores";
import { Box, Typography } from "@mui/material";

/**
 * パスワード変更画面
 */
export const ChangePassword = () => {
    const { user } = useUserAuthStore();
    return (
        <Box sx={{ maxWidth: 600, mx: "auto", py: 4 }}>
            {/* 見出し */}
            <Headline text={user?.hasPassword ? "パスワード変更" : "パスワード設定"} />
            {/* 説明文 */}
            <Typography variant="body1" gutterBottom sx={{ my: 4, textAlign: "center" }}>
                {user?.hasPassword
                    ? "以下の項目を入力し、変更してください。"
                    : "以下の項目を入力し、設定してください。"}
            </Typography>
            {/* パスワード変更フォーム */}
            <ChangePasswordForm />
        </Box>
    );
};
