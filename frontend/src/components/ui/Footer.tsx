import { env } from "@/config/env";
import { Box, Typography } from "@mui/material";
import { useLayoutEffect, useState } from "react";

/**
 * フッター
 */
export const Footer = () => {
    // スクロールするかしないか
    const [isFixed, setIsFixed] = useState(true);

    /**
     * 画面がスクロールするかどうかを検出する
     */
    useLayoutEffect(() => {
        const checkScroll = () => {
            const hasScroll = document.documentElement.scrollHeight > window.innerHeight;
            setIsFixed(!hasScroll);
        };

        checkScroll();
        window.addEventListener("resize", checkScroll);

        return () => window.removeEventListener("resize", checkScroll);
    }, []);

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
