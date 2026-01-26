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

        // ResizeObserverの設定
        const resizeObserver = new ResizeObserver(() => {
            checkScroll();
        });

        // document.bodyを監視
        resizeObserver.observe(document.body);

        // クリーンアップ
        return () => {
            resizeObserver.disconnect();
        };
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
            }}
        >
            <Typography variant="body2" color="text.secondary">
                {`© 2026 ${env.APP_NAME}. All rights reserved.`}
            </Typography>
        </Box>
    );
};
