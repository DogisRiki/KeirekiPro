import { Button } from "@/components/ui";
import { Box, Typography } from "@mui/material";

/**
 * 500サーバーエラー
 */
export const ServerError = () => {
    return (
        <Box
            display="flex"
            flexDirection="column"
            alignItems="center"
            justifyContent="center"
            height="100vh"
            textAlign="center"
        >
            <Typography variant="h4" gutterBottom>
                サーバーで問題が発生しました
            </Typography>
            <Typography variant="body1" sx={{ mb: 4 }}>
                大変恐れ入りますが、時間を置いて再度お試しください。
            </Typography>
            <Button
                onClick={() => {
                    // 前のページに戻る
                    window.history.back();
                }}
            >
                再読み込み
            </Button>
        </Box>
    );
};
