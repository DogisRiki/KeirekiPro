import { env } from "@/config/env";
import { Box, Typography } from "@mui/material";
import { useEffect, useState } from "react";

/**
 * フッター
 */
export const Footer = () => {
    // スクロールするかしないか
    const [isFixed, setIsFixed] = useState(true);

    /**
     * 画面がスクロールするかどうかを検出する
     */
    useEffect(() => {
        const checkScroll = () => {
            // 少し余裕を持たせて判定（1pxの誤差を許容）
            const hasScroll = document.documentElement.scrollHeight > window.innerHeight + 1;
            setIsFixed(!hasScroll);
        };

        // 初回チェック
        checkScroll();

        // ウィンドウリサイズ時のチェック
        window.addEventListener("resize", checkScroll);

        // ResizeObserverの設定
        const resizeObserver = new ResizeObserver(() => {
            // requestAnimationFrameで次フレームに遅延させて正確な高さを取得
            requestAnimationFrame(() => {
                checkScroll();
            });
        });

        // document.bodyを監視
        resizeObserver.observe(document.body);

        // MutationObserverでDOM変更も監視
        const mutationObserver = new MutationObserver(() => {
            requestAnimationFrame(() => {
                checkScroll();
            });
        });

        mutationObserver.observe(document.body, {
            childList: true,
            subtree: true,
            attributes: true,
        });

        // クリーンアップ
        return () => {
            window.removeEventListener("resize", checkScroll);
            resizeObserver.disconnect();
            mutationObserver.disconnect();
        };
    }, []);

    return (
        <Box
            component="footer"
            sx={{
                position: isFixed ? "fixed" : "static",
                bottom: isFixed ? 0 : "auto",
                left: 0,
                right: 0,
                width: "100%",
                textAlign: "center",
                py: 1,
                bgcolor: "background.default",
            }}
        >
            <Typography variant="body2" color="text.secondary">
                {`© 2026 ${env.APP_NAME}. All rights reserved.`}
            </Typography>
        </Box>
    );
};
