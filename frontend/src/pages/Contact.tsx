import { Headline } from "@/components/ui";
import { ContactForm } from "@/features/contact";
import { Box, Typography } from "@mui/material";
import { useEffect } from "react";

/**
 * お問い合わせ画面
 */
export const Contact = () => {
    useEffect(() => {
        alert("現在、この機能は準備中です。");
        window.history.back();
    }, []);

    return (
        <Box sx={{ maxWidth: 600, mx: "auto", py: 4 }}>
            {/* 見出し */}
            <Headline text="お問い合わせ" />
            {/* 説明文 */}
            <Typography variant="body1" gutterBottom sx={{ my: 4 }}>
                以下フォームよりお問い合わせください。
                <br />
                お問い合わせ内容の確認後、管理人よりご連絡させていただきます。
            </Typography>
            {/* お問い合わせフォーム */}
            <ContactForm />
        </Box>
    );
};
