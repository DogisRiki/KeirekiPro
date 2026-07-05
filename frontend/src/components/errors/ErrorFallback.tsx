import { Button } from "@/components/ui";
import RefreshIcon from "@mui/icons-material/Refresh";
import { Box, Typography } from "@mui/material";

/**
 * 非同期処理以外のエラー発生時のフォールバックページ
 */
export const ErrorFallback = () => {
    return (
        <Box
            role={"alert"}
            sx={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                justifyContent: "center",
                height: "100vh",
                width: "100vw",
                textAlign: "center",
            }}
        >
            <Typography variant="h6" sx={{ mb: 2, fontWeight: "bold" }}>
                Ooops, something went wrong :(
            </Typography>
            <Button startIcon={<RefreshIcon />} onClick={() => window.location.assign(window.location.origin)}>
                Refresh
            </Button>
        </Box>
    );
};
