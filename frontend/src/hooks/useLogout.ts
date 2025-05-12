import { paths } from "@/config/paths";
import { protectedApiClient } from "@/lib";
import { useUserAuthStore } from "@/stores";
import { useNavigate } from "react-router";

/**
 * ログアウトフック
 */
export const useLogout = () => {
    const { setLogout } = useUserAuthStore();
    const navigate = useNavigate();

    const logout = async () => {
        await protectedApiClient.post("/auth/logout");
        setLogout();
        navigate(paths.login, { replace: true });
    };

    return logout;
};
