import { RequestPasswordResetForm, useRequestPasswordReset } from "@/features/auth";
import { useState } from "react";

/**
 * パスワードリセット要求コンテナ
 */
export const RequestPasswordResetContainer = () => {
    const [email, setEmail] = useState("");
    const requestResetMutation = useRequestPasswordReset();

    return (
        <RequestPasswordResetForm
            email={email}
            onEmailChange={(v) => {
                setEmail(v);
            }}
            onSubmit={() => requestResetMutation.mutate({ email })}
            loading={requestResetMutation.isPending}
        />
    );
};
