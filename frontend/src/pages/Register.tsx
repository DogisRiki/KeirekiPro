import { RegisterForm } from "@/features/auth";
import { Typography } from "@mui/material";

/**
 * ユーザー登録画面
 */
export const Register = () => {
    return (
        <>
            <Typography variant="h5" gutterBottom>
                新規登録
            </Typography>
            <RegisterForm />
        </>
    );
};
