import { paths } from "@/config/paths";
import { protectedApiClient } from "@/lib";
import { useUserAuthStore } from "@/stores";
import { User } from "@/types";
import { redirect } from "react-router";

const fetchCurrentUser = async (): Promise<User | null> => {
    try {
        const { data } = await protectedApiClient.get<User>("/api/users/me");
        return data;
    } catch {
        return null;
    }
};

/**
 * 未認証ローダー
 */
export const PublicLoader = async () => {
    const { isAuthenticated } = useUserAuthStore.getState();

    // 既に認証済みなら一覧ページへ
    if (isAuthenticated) {
        throw redirect(paths.resume.list);
    }

    // Cookie にトークンはあるがストアが空の場合のみフェッチ
    const user = await fetchCurrentUser();
    if (user) {
        useUserAuthStore.getState().setLogin(user);
        throw redirect(paths.resume.list);
    }
    return null;
};

/**
 * 認証済みローダー
 */
export const ProtectedLoader = async () => {
    const { isAuthenticated } = useUserAuthStore.getState();

    if (isAuthenticated) return null; // 既に認証済み

    const user = await fetchCurrentUser();
    if (user) {
        useUserAuthStore.getState().setLogin(user);
        return null;
    }

    // 取得できなければログインへ
    throw redirect(paths.login);
};
