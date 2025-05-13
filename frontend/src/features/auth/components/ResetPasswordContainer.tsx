import { paths } from "@/config/paths";
import { ResetPasswordForm, useResetPassword, useVerifyPasswordResetToken } from "@/features/auth";
import { useState } from "react";
import { useNavigate, useParams } from "react-router";

/**
 * パスワードリセットコンテナ
 */
export const ResetPasswordContainer = () => {
    const [password, setPassword] = useState("");
    const [confirmPassword, setConfirmPassword] = useState("");
    const { token } = useParams<{ token: string }>();

    const resetPasswordMutation = useResetPassword();
    const { isError } = useVerifyPasswordResetToken(token ?? "");

    const navigate = useNavigate();

    if (!token) {
        navigate(paths.login, { replace: true });
        return;
    }

    if (isError) {
        navigate(paths.password.resetRequest, { replace: true });
        return;
    }

    return (
        <ResetPasswordForm
            password={password}
            confirmPassword={confirmPassword}
            onPasswordChange={(v) => {
                setPassword(v);
            }}
            onConfirmPasswordChange={(v) => {
                setConfirmPassword(v);
            }}
            onSubmit={() => resetPasswordMutation.mutate({ token, password, confirmPassword })}
            loading={resetPasswordMutation.isPending}
        />
    );
};
