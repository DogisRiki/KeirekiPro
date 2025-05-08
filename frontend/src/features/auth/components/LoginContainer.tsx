import { LoginForm, useLogin } from "@/features/auth";
import { useErrorMessageStore } from "@/stores";
import { useState } from "react";

/**
 * ログインコンテナ
 */
export const LoginContainer = () => {
    const [email, setEmail] = useState("");
    const [password, setPassword] = useState("");
    const loginMutation = useLogin();
    const { clearErrors } = useErrorMessageStore();

    return (
        <LoginForm
            email={email}
            password={password}
            onEmailChange={(v) => {
                clearErrors();
                setEmail(v);
            }}
            onPasswordChange={(v) => {
                clearErrors();
                setPassword(v);
            }}
            onSubmit={() => loginMutation.mutate({ email, password })}
            loading={loginMutation.isPending}
        />
    );
};
