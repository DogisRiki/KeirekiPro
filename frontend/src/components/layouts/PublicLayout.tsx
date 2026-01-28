import { Footer } from "@/components/ui";
import { useGoogleAnalytics } from "@/hooks";
import { useErrorMessageStore } from "@/stores";
import { Box, Container } from "@mui/material";
import { useEffect } from "react";
import { Outlet, useLocation } from "react-router";

/**
 * 未ログイン時のみアクセス可能な画面の共通レイアウト
 */
export const PublicLayout = () => {
    const { clearErrors } = useErrorMessageStore();
    const { pathname } = useLocation();

    useEffect(() => {
        clearErrors();
    }, [pathname, clearErrors]);

    useGoogleAnalytics();

    return (
        <Box
            sx={{
                display: "flex",
                flexDirection: "column",
                minHeight: "100vh",
            }}
        >
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
                    <Outlet />
                </Box>
            </Container>
            <Footer />
        </Box>
    );
};
