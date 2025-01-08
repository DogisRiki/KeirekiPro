import { Box, Divider, Typography } from "@mui/material";

interface HeadlineProps {
    text: string;
}

/**
 * 見出し
 */
export const Headline = ({ text }: HeadlineProps) => {
    return (
        <Box sx={{ textAlign: "center" }}>
            <Typography variant="h4" gutterBottom>
                {text}
            </Typography>
            <Divider
                sx={{
                    width: 80,
                    height: 3,
                    backgroundColor: "primary.main",
                    mx: "auto",
                    mt: 1,
                }}
            />
        </Box>
    );
};
