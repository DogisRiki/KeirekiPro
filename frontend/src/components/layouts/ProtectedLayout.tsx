import { Footer, MainMenu, ScrollToTopButton, ThemeSwitch, UserMenu } from "@/components/ui";
import { paths } from "@/config/paths";
import { useGoogleAnalytics } from "@/hooks";
import { useErrorMessageStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { AppBar, Box, Container, Toolbar, Typography } from "@mui/material";
import { useEffect, useRef } from "react";
import { Outlet, useLocation, useNavigate } from "react-router";

interface ProtectedNavigationState {
    errorResponse?: ErrorResponse;
}

/**
 * ログイン時のみアクセス可能な画面の共通レイアウト
 */
export const ProtectedLayout = () => {
    const { clearErrors, setErrors } = useErrorMessageStore();
    const { pathname, search, hash, state } = useLocation();
    const navigate = useNavigate();
    const navigationError = (state as ProtectedNavigationState | null)?.errorResponse;
    const currentLocation = `${pathname}${search}${hash}`;
    const consumedErrorLocationRef = useRef<string | null>(null);

    useEffect(() => {
        if (navigationError) {
            clearErrors();
            setErrors(navigationError);
            consumedErrorLocationRef.current = currentLocation;
            navigate({ pathname, search, hash }, { replace: true, state: null });
            return;
        }
        if (consumedErrorLocationRef.current === currentLocation) {
            consumedErrorLocationRef.current = null;
            return;
        }
        clearErrors();
    }, [currentLocation, navigationError, pathname, search, hash, clearErrors, navigate, setErrors]);

    useGoogleAnalytics();

    /**
     * ホームへ遷移
     */
    const handleLogoClick = () => {
        navigate(paths.resume.list);
    };

    return (
        <Box>
            <AppBar position="fixed">
                <Toolbar>
                    <MainMenu />
                    <Typography
                        variant="h6"
                        onClick={handleLogoClick}
                        sx={{
                            flexGrow: 1,
                            cursor: "pointer",
                            "&:hover": {
                                opacity: 0.7,
                            },
                        }}
                    >
                        KeirekiPro
                    </Typography>
                    <ThemeSwitch />
                    <UserMenu />
                </Toolbar>
            </AppBar>
            <Container sx={{ mt: 12, mb: 4 }}>
                <Outlet />
            </Container>
            <Footer />
            <ScrollToTopButton />
        </Box>
    );
};
