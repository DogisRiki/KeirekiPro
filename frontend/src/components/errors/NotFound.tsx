import ArrowBackIosNewIcon from "@mui/icons-material/ArrowBackIosNew";
import { Box, Button, Typography } from "@mui/material";

/**
 * 404
 */
export const NotFound = () => {
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
            <Typography variant="h3" fontWeight={"bold"} sx={{ mb: 4 }}>
                404&nbsp;&nbsp;Not&nbsp;&nbsp;Found
            </Typography>
            <Button
                variant="text"
                startIcon={<ArrowBackIosNewIcon />}
                onClick={() => window.location.assign(window.location.origin)}
            >
                トップページへ戻る
            </Button>
        </Box>
    );
};
