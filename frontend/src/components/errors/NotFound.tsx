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
            role={"alert"}
            sx={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                justifyContent: "center",
                minHeight: isContent ? "calc(100dvh - 128px)" : "100dvh",
                width: "100%",
                textAlign: "center",
            }}
        >
            <Typography variant="h3" sx={{ mb: 4, fontWeight: "bold" }}>
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
