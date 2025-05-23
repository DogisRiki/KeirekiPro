import { Headline } from "@/components/ui";
import { SettingUserContainer } from "@/features/user";
import { Box } from "@mui/material";

/**
 * ユーザー設定画面
 */
export const SettingUser = () => {
    return (
        <Box sx={{ maxWidth: 600, mx: "auto", py: 4 }}>
            {/* 見出し */}
            <Headline text="ユーザー設定" />
            {/* ユーザー設定フォーム */}
            <SettingUserContainer />
        </Box>
    );
};
