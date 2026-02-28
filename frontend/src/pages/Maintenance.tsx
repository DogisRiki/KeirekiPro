import BuildIcon from "@mui/icons-material/Build";
import { Box, Typography } from "@mui/material";

/**
 * メンテナンス画面
 */
export const Maintenance = () => {
    return (
        <Box
            display="flex"
            flexDirection="column"
            alignItems="center"
            justifyContent="center"
            height="100vh"
            textAlign="center"
        >
            <BuildIcon sx={{ fontSize: 64, color: "text.secondary", mb: 2 }} />
            <Typography variant="h4" gutterBottom>
                メンテナンス中
            </Typography>
            <Typography variant="body1" sx={{ mb: 4 }}>
                現在サービスは停止中です。平日 8:00〜20:00 に再度アクセスしてください。
            </Typography>
        </Box>
    );
};
