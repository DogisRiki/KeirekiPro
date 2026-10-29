import { Footer } from "@/components/ui";
import { EmailVerificationContainer } from "@/features/auth";
import { Box, Container, Typography } from "@mui/material";

/**
 * 確認のリンクの画面
 * ログインの有無に関係なく出すため、どのレイアウトにも属さない
 */
export const VerifyEmail = () => {
    return (
        <Box sx={{ display: "flex", flexDirection: "column", minHeight: "100vh" }}>
            <Container
                sx={{
                    display: "flex",
                    justifyContent: "center",
                    alignItems: "center",
                    flex: 1,
                    py: { xs: 3, sm: 4 },
                    px: { xs: 2, sm: 3 },
                }}
            >
                <Box
                    sx={{
                        bgcolor: "background.paper",
                        p: { xs: 3, sm: 6, md: 10 },
                        borderRadius: 1,
                        boxShadow: 1,
                        width: "100%",
                        maxWidth: 600,
                        textAlign: "center",
                    }}
                >
                    <Typography variant="h5" gutterBottom sx={{ mb: 4 }}>
                        メールアドレスの確認
                    </Typography>
                    <EmailVerificationContainer />
                </Box>
            </Container>
            <Footer />
        </Box>
    );
};
