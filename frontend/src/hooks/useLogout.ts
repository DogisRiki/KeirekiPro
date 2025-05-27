import { paths } from "@/config/paths";
import { protectedApiClient } from "@/lib";
import { useUserAuthStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import { AxiosError, AxiosResponse } from "axios";
import { useNavigate } from "react-router";

/**
 * ログアウトフック
 * @returns ログアウトミューテーション
 */
export const useLogout = () => {
    const { setLogout } = useUserAuthStore();
    const navigate = useNavigate();

    return useMutation<AxiosResponse<void>, AxiosError, void>({
        mutationFn: () => protectedApiClient.post("/auth/logout"),
        onSuccess: () => {
            setLogout();
            navigate(paths.login, { replace: true });
        },
    });
};
