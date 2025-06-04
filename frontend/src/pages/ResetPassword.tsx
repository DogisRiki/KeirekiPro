import { ResetPasswordContainer } from "@/features/auth";
import { Typography } from "@mui/material";

/**
 * パスワード再設定画面
 */
export const ResetPassword = () => {
    return (
        <>
            <Typography variant="h5" gutterBottom sx={{ mb: 4 }}>
                パスワード再設定
            </Typography>
            <Typography variant="body1" gutterBottom sx={{ mb: 4 }}>
                新しいパスワードを設定してください。
            </Typography>
            <ResetPasswordContainer />
        </>
    );
};
