import { UserRegisterForm, useUserRegister } from "@/features/auth";
import { useErrorMessageStore } from "@/stores";
import { useState } from "react";

/**
 * ユーザー新規登録コンテナ
 */
export const UserRegisterContainer = () => {
    const [email, setEmail] = useState("");
    const [username, setUsername] = useState("");
    const [password, setPassword] = useState("");
    const [confirmPassword, setConfirmPassword] = useState("");

    const registerMutation = useUserRegister();
    const { clearErrors } = useErrorMessageStore();

    return (
        <UserRegisterForm
            email={email}
            username={username}
            password={password}
            confirmPassword={confirmPassword}
            onEmailChange={(v) => {
                clearErrors();
                setEmail(v);
            }}
            onUsernameChange={(v) => {
                clearErrors();
                setUsername(v);
            }}
            onPasswordChange={(v) => {
                clearErrors();
                setPassword(v);
            }}
            onConfirmPasswordChange={(v) => {
                clearErrors();
                setConfirmPassword(v);
            }}
            onSubmit={() => registerMutation.mutate({ email, username, password, confirmPassword })}
            loading={registerMutation.isPending}
        />
    );
};
