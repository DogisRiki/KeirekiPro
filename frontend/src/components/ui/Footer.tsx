import { env } from "@/config/env";
import { Box, Typography } from "@mui/material";

interface FooterProps {
    isFixed: boolean;
}

/**
 * フッター
 */
export const Footer = ({ isFixed }: FooterProps) => {
    return (
        <Box
            component="footer"
            sx={{
                position: isFixed ? "fixed" : "static",
                bottom: 0,
                width: "100%",
                textAlign: "center",
                py: 1,
                backgroundColor: "background.paper",
            }}
        >
            <Typography variant="body2" color="text.secondary">
                {`© 2025 ${env.APP_NAME}. All rights reserved.`}
            </Typography>
        </Box>
    );
};
