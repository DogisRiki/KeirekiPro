import { Outlet } from "react-router";

/**
 * ログイン時のみアクセス可能な画面の共通レイアウト
 */
export const ProtectedLayout = () => {
    return (
        <div>
            <Outlet />
        </div>
    );
};
