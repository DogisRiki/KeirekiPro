import { paths } from "@/config/paths";
import { ChangePasswordForm, useChangePassword, UserState, useUserState } from "@/features/user";
import { useState } from "react";
import { Navigate } from "react-router";

/**
 * パスワード変更コンテナ
 */
export const ChangePasswordContainer = () => {
    const [nowPassword, setNowPassword] = useState("");
    const [newPassword, setNewPassword] = useState("");

    const userState = useUserState();
    const changePasswordMutation = useChangePassword();

    if (userState !== UserState.EMAIL_PASSWORD && userState !== UserState.EMAIL_PASSWORD_WITH_PROVIDER) {
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
            loading={changePasswordMutation.isPending}
        />
    );
};
