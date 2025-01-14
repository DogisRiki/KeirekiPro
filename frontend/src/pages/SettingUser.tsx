import { Headline } from "@/components/ui";
import { SettingUserForm } from "@/features/user";
import { useUserAuthStore } from "@/stores/userAuthStore";
import { Box } from "@mui/material";
import { useEffect } from "react";

/**
 * ユーザー設定画面
 */
export const SettingUser = () => {
    const { setLogin } = useUserAuthStore();

    // 初期化
    useEffect(() => {
        setLogin({
            userId: "test",
            userName: "テストユーザー",
            hasPassword: false,
            twoFactorAuthEnabled: true,
            authProviders: ["email", "github", "google"],
            email: "test@keirekipro.click",
            profileImage: "https://cdn.pixabay.com/photo/2016/02/19/15/46/labrador-retriever-1210559_1280.jpg",
        });
    }, [setLogin]);
    return (
        <Box sx={{ maxWidth: 600, mx: "auto", py: 4 }}>
            {/* 見出し */}
            <Headline text="ユーザー設定" />
            {/* ユーザー設定フォーム */}
            <SettingUserForm />
        </Box>
    );
};
