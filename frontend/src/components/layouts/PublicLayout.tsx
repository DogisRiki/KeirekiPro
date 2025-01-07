import { Footer } from "@/components/ui";
import { Box, Container } from "@mui/material";
import { Outlet } from "react-router";

/**
 * 未ログイン時のみアクセス可能な画面の共通レイアウト
 */
export const PublicLayout = () => {
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
                        bgcolor: "#fff",
                        p: 10,
                        borderRadius: 1,
                        boxShadow: "0px 1px 3px 0px rgba(0, 0, 0, 0.2)",
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
