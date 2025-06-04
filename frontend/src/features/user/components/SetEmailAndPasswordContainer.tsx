import { paths } from "@/config/paths";
import { SetEmailAndPasswordForm, UserState, useSetEmailAndPassword, useUserState } from "@/features/user";
import { useState } from "react";
import { Navigate } from "react-router";

/**
 * メールアドレス+パスワード設定コンテナ
 */
export const SetEmailAndPasswordContainer = () => {
    const [email, setEmail] = useState("");
    const [password, setPassword] = useState("");
    const [confirmPassword, setConfirmPassword] = useState("");

    const userState = useUserState();
    const setEmailAndPasswordMutation = useSetEmailAndPassword();

    // メールアドレス設定可能なのはPROVIDER_ONLYのみ
    const showEmailField = userState === UserState.PROVIDER_ONLY;

    // EMAIL_WITH_PROVIDER / その他はアクセス不可
    if (userState !== UserState.EMAIL_WITH_PROVIDER && userState !== UserState.PROVIDER_ONLY) {
        return <Navigate to={paths.login} replace />;
    }

    /**
     * フォーム送信ハンドラ
     */
    const handleSubmit = () => {
        // PROVIDER_ONLYのときのみemailを含める
        const payload = {
            ...(showEmailField ? { email } : {}),
            password,
            confirmPassword,
        };
        setEmailAndPasswordMutation.mutate(payload);
    };

    return (
        <SetEmailAndPasswordForm
            showEmailField={showEmailField}
            email={email}
            password={password}
            confirmPassword={confirmPassword}
            onEmailChange={(v) => {
                setEmail(v);
            }}
            onPasswordChange={(v) => {
                setPassword(v);
            }}
            onConfirmPasswordChange={(v) => {
                setConfirmPassword(v);
            }}
            onSubmit={handleSubmit}
            loading={setEmailAndPasswordMutation.isPending}
        />
    );
};
