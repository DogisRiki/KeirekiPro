import { Button, PasswordTextField } from "@/components/ui";
import { useUserAuthStore } from "@/stores";
import { Box } from "@mui/material";

/**
 * パスワード変更/設定フォーム
 */
export const ChangePasswordForm = () => {
    const { user } = useUserAuthStore();

    // 送信処理
    const handleSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        // TODO: API呼び出し
        alert("送信");
    };
    return (
        <Box
            component="form"
            sx={{ display: "flex", flexDirection: "column", justifyContent: "center" }}
            onSubmit={handleSubmit}
        >
            <PasswordTextField
                label={user?.hasPassword ? "現在のパスワード" : "パスワード"}
                fullWidth
                required
                placeholder={user?.hasPassword ? "現在のパスワード" : "パスワード"}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 4 }}
            />
            {user?.hasPassword && (
                <PasswordTextField
                    label="新しいパスワード"
                    fullWidth
                    required
                    placeholder="新しいパスワード"
                    slotProps={{
                        inputLabel: { shrink: true },
                    }}
                    sx={{ mb: 4 }}
                />
            )}
            <Button type="submit" sx={{ width: 240, mx: "auto" }}>
                {user?.hasPassword ? "変更" : "設定"}
            </Button>
        </Box>
    );
};
