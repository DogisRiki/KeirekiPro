import { Button } from "@/components/ui";
import ArrowBackIosNewIcon from "@mui/icons-material/ArrowBackIosNew";
import { Box, Typography } from "@mui/material";

/**
 * 404
 */
type NotFoundProps = {
    variant?: "page" | "content";
};

export const NotFound = ({ variant = "page" }: NotFoundProps) => {
    const isContent = variant === "content";

    return (
        <Box
            display={"flex"}
            flexDirection={"column"}
            alignItems={"center"}
            justifyContent={"center"}
            minHeight={isContent ? "calc(100dvh - 128px)" : "100dvh"}
            width={"100%"}
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
