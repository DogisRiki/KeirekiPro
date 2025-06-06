import { env } from "@/config/env";
import { LoginContainer } from "@/features/auth";
import { Typography } from "@mui/material";

/**
 * ログイン画面
 */
export const Login = () => {
    return (
        <>
            <Typography variant="h5" gutterBottom>
                {env.APP_NAME}
            </Typography>
            <LoginContainer />
        </>
    );
};
