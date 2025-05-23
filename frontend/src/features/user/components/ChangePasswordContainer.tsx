import { paths } from "@/config/paths";
import { ChangePasswordForm } from "@/features/user";
import { useChangePassword } from "@/features/user/hooks/useChangePassword";
import { useUserAuthStore } from "@/stores";
import { useState } from "react";
import { useNavigate } from "react-router";

/**
 * パスワード変更コンテナ
 */
export const ChangePasswordContainer = () => {
    const [nowPassword, setNowPassword] = useState("");
    const [newPassword, setNewPassword] = useState("");

    const { user } = useUserAuthStore();
    const changePasswordMutation = useChangePassword();
    const navigate = useNavigate();

    if (!user?.hasPassword) {
        navigate(paths.login, { replace: true });
    }

    /**
     * フォーム送信ハンドラ
     */
    const handleSubmit = () => {
        changePasswordMutation.mutate(
            { nowPassword, newPassword },
            {
                onSuccess: () => {
                    // 成功時にフォームをクリア
                    setNowPassword("");
                    setNewPassword("");
                },
            },
        );
    };

    return (
        <ChangePasswordForm
            nowPassword={nowPassword}
            newPassword={newPassword}
            onNowPasswordChange={(v) => {
                setNowPassword(v);
            }}
            onNewPasswordChange={(v) => {
                setNewPassword(v);
            }}
            onSubmit={handleSubmit}
        />
    );
};
