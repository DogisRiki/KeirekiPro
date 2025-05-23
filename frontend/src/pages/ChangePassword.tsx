import { Headline } from "@/components/ui";
import { ChangePasswordContainer } from "@/features/user";
import { Box, Typography } from "@mui/material";

/**
 * パスワード変更画面
 */
export const ChangePassword = () => {
    return (
        <Box sx={{ maxWidth: 600, mx: "auto", py: 4 }}>
            <Headline text={"パスワード変更"} />
            <Typography variant="body1" gutterBottom sx={{ my: 4, textAlign: "center" }}>
                以下の項目を入力し、変更してください。
            </Typography>
            <ChangePasswordContainer />
        </Box>
    );
};
