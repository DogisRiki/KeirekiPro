import { UserRegisterForm, useUserRegister } from "@/features/auth";
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

    return (
        <UserRegisterForm
            email={email}
            username={username}
            password={password}
            confirmPassword={confirmPassword}
            onEmailChange={(v) => {
                setEmail(v);
            }}
            onUsernameChange={(v) => {
                setUsername(v);
            }}
            onPasswordChange={(v) => {
                setPassword(v);
            }}
            onConfirmPasswordChange={(v) => {
                setConfirmPassword(v);
            }}
            onSubmit={() => registerMutation.mutate({ email, username, password, confirmPassword })}
            loading={registerMutation.isPending}
        />
    );
};
