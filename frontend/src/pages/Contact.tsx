import { ContactForm } from "@/features/contact";
import { Box, Divider, Typography } from "@mui/material";

/**
 * お問い合わせ画面
 */
export const Contact = () => {
    return (
        <Box sx={{ maxWidth: 600, mx: "auto", py: 4 }}>
            {/* ヘッダー部分 */}
            <Box sx={{ textAlign: "center", mb: 4 }}>
                <Typography variant="h4" gutterBottom>
                    お問い合わせ
                </Typography>
                <Divider
                    sx={{
                        width: 80,
                        height: 3,
                        backgroundColor: "primary.main",
                        mx: "auto",
                        mt: 1,
                    }}
                />
            </Box>
            {/* 説明文 */}
            <Typography variant="body1" gutterBottom sx={{ mb: 4 }}>
                以下フォームよりお問い合わせください。
                <br />
                お問い合わせ内容の確認後、管理人よりご連絡させていただきます。
            </Typography>
            {/* お問い合わせフォーム */}
            <ContactForm />
        </Box>
    );
};
