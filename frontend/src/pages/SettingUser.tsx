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
            id: "test",
            username: "テストユーザー",
            hasPassword: false,
            twoFactorAuthEnabled: true,
            authProviders: [
                { id: "1", providerType: "github", providerUserId: "1" },
                { id: "2", providerType: "google", providerUserId: "2" },
            ],
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
