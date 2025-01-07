import { Button } from "@/components/ui";
import RefreshIcon from "@mui/icons-material/Refresh";
import { Box, Typography } from "@mui/material";

/**
 * 非同期処理以外のエラー発生時のフォールバックページ
 */
export const ErrorFallback = () => {
    return (
        <Box
            display={"flex"}
            flexDirection={"column"}
            alignItems={"center"}
            justifyContent={"center"}
            height={"100vh"}
            width={"100vw"}
            textAlign={"center"}
            role={"alert"}
        >
            <Typography variant="h6" fontWeight={"bold"} sx={{ mb: 2 }}>
                Ooops, something went wrong :(
            </Typography>
            <Button startIcon={<RefreshIcon />} onClick={() => window.location.assign(window.location.origin)}>
                Refresh
            </Button>
        </Box>
    );
};
