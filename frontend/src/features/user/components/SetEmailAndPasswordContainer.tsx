import { paths } from "@/config/paths";
import { SetEmailAndPasswordForm, UserState, useSetEmailAndPassword, useUserState } from "@/features/user";
import { useState } from "react";
import { Navigate } from "react-router";

/**
 * メールアドレス+パスワード設定コンテナ
 */
export const SetEmailAndPasswordContainer = () => {
    const [email, setEmail] = useState("");
    const [currentPassword, setCurrentPassword] = useState("");
    const [password, setPassword] = useState("");
    const [confirmPassword, setConfirmPassword] = useState("");

    const userState = useUserState();
    const setEmailAndPasswordMutation = useSetEmailAndPassword();

    // メールアドレス設定可能なのはPROVIDER_ONLYと、メールアドレスが設定待ちのPASSWORD_WITH_PROVIDER
    const showEmailField = userState === UserState.PROVIDER_ONLY || userState === UserState.PASSWORD_WITH_PROVIDER;
    // パスワードを持つアカウントが設定待ちのメールアドレスを置き換えるときは、今のパスワードを求める
    const showCurrentPasswordField = userState === UserState.PASSWORD_WITH_PROVIDER;

    // EMAIL_WITH_PROVIDER / PROVIDER_ONLY / PASSWORD_WITH_PROVIDER 以外はアクセス不可
    if (
        userState !== UserState.EMAIL_WITH_PROVIDER &&
        userState !== UserState.PROVIDER_ONLY &&
        userState !== UserState.PASSWORD_WITH_PROVIDER
    ) {
        return <Navigate to={paths.login} replace />;
    }

    /**
     * フォーム送信ハンドラ
     */
    const handleSubmit = () => {
        // メールアドレスの入力欄を出したときのみemailを、今のパスワードの入力欄を出したときのみcurrentPasswordを含める
        const payload = {
            ...(showEmailField ? { email } : {}),
            ...(showCurrentPasswordField ? { currentPassword } : {}),
            password,
            confirmPassword,
        };
        setEmailAndPasswordMutation.mutate(payload);
    };

    return (
        <SetEmailAndPasswordForm
            showEmailField={showEmailField}
            showCurrentPasswordField={showCurrentPasswordField}
            email={email}
            currentPassword={currentPassword}
            password={password}
            confirmPassword={confirmPassword}
            onEmailChange={(v) => {
                setEmail(v);
            }}
            onCurrentPasswordChange={(v) => {
                setCurrentPassword(v);
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
