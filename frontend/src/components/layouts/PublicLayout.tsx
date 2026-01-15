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
        <>
            <Container
                sx={{
                    display: "flex",
                    justifyContent: "center",
                    alignItems: "center",
                    height: "100vh",
                    m: "auto",
                    textAlign: "center",
                }}
            >
                <Box
                    sx={{
                        bgcolor: "background.paper",
                        p: 10,
                        borderRadius: 1,
                        boxShadow: 1,
                        width: "100%",
                        maxWidth: 600,
                    }}
                >
                    <Outlet />
                </Box>
            </Container>
            <Footer />
        </>
    );
};
