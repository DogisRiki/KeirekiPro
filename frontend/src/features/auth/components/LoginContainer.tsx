import { LoginForm, useAuthorizeOidc, useLogin } from "@/features/auth";
import { useState } from "react";

/**
 * ログインコンテナ
 */
export const LoginContainer = () => {
    const [email, setEmail] = useState("");
    const [password, setPassword] = useState("");
    const loginMutation = useLogin();
    const oidcMutation = useAuthorizeOidc();

    return (
        <LoginForm
            email={email}
            password={password}
            onEmailChange={(v) => {
                setEmail(v);
            }}
            onPasswordChange={(v) => {
                setPassword(v);
            }}
            onSubmit={() => loginMutation.mutate({ email, password })}
            onOidcLogin={(provider) => oidcMutation.mutate(provider)}
            loading={loginMutation.isPending || oidcMutation.isPending}
        />
    );
};
