import KeyboardArrowUpIcon from "@mui/icons-material/KeyboardArrowUp";
import { Fab, Fade } from "@mui/material";
import { useEffect, useState } from "react";

/**
 * ページ上部へ戻るフローティングボタン
 */
export const ScrollToTopButton = () => {
    const [isVisible, setIsVisible] = useState(false);

    // スクロール位置を監視して表示/非表示を切り替え
    useEffect(() => {
        const toggleVisibility = () => {
            // 300px以上スクロールしたら表示
            setIsVisible(window.scrollY > 300);
        };

        window.addEventListener("scroll", toggleVisibility);
        return () => {
            window.removeEventListener("scroll", toggleVisibility);
        };
    }, []);

    // ページ上部へスムーズにスクロール
    const scrollToTop = () => {
        window.scrollTo({
            top: 0,
            behavior: "smooth",
        });
    };

    return (
        <Fade in={isVisible}>
            <Fab
                color="primary"
                size="medium"
                onClick={scrollToTop}
                aria-label="ページ上部へ戻る"
                sx={{
                    position: "fixed",
                    bottom: 100,
                    right: 40,
                    zIndex: 1000,
                }}
            >
                <KeyboardArrowUpIcon />
            </Fab>
        </Fade>
    );
};
