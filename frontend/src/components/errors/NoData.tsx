import { Box, Typography } from "@mui/material";

interface NoDataProps {
    message: string;
}

/**
 * データがないときに表示する
 */
export const NoData = ({ message }: NoDataProps) => {
    return (
        <Box sx={{ display: "flex", justifyContent: "center", alignItems: "center", minHeight: "80vh" }}>
            <Typography
                variant="h6"
                color="text.secondary"
                sx={{
                    textAlign: "center",
                    my: 4,
                }}
            >
                {message}
            </Typography>
        </Box>
    );
};
