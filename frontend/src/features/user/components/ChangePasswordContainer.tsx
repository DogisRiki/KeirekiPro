import { paths } from "@/config/paths";
import { ChangePasswordForm } from "@/features/user";
import { useChangePassword } from "@/features/user/hooks/useChangePassword";
import { useUserAuthStore } from "@/stores";
import { useState } from "react";
import { Navigate } from "react-router";

/**
 * パスワード変更コンテナ
 */
export const ChangePasswordContainer = () => {
    const [nowPassword, setNowPassword] = useState("");
    const [newPassword, setNewPassword] = useState("");

    const { user } = useUserAuthStore();
    const changePasswordMutation = useChangePassword();

    if (user && !user.hasPassword) {
        return <Navigate to={paths.login} replace />;
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
