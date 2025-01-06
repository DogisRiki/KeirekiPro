import { NotFound } from "@/components/errors";
import { ProtectedLayout, PublicLayout } from "@/components/layouts";
import { paths } from "@/config/paths";
import {
    Contact,
    Login,
    Register,
    ResetPassword,
    ResetRequestPassword,
    Resume,
    ResumeList,
    SettingUser,
    Top,
    TwoFactor,
} from "@/pages";
import { ProtectedLoader, PublicLoader } from "@/routes/AppLoader";
import { createBrowserRouter, RouterProvider } from "react-router";

/**
 * ルーティング
 */
const router = createBrowserRouter([
    {
        path: paths.top,
        element: <Top />,
        loader: PublicLoader,
    },
    {
        element: <PublicLayout />,
        loader: PublicLoader,
        children: [
            {
                path: paths.login,
                element: <Login />,
            },
            {
                path: paths.register,
                element: <Register />,
            },
            {
                path: paths.password.resetRquest,
                element: <ResetRequestPassword />,
            },
            {
                path: paths.password.reset,
                element: <ResetPassword />,
            },
        ],
    },
    {
        element: <ProtectedLayout />,
        loader: ProtectedLoader,
        children: [
            {
                path: paths.twoFactor,
                element: <TwoFactor />,
            },
            {
                path: paths.resume.list,
                element: <ResumeList />,
            },
            {
                path: paths.resume.new,
                element: <Resume />,
            },
            {
                path: paths.resume.edit,
                element: <ResumeList />,
            },
            {
                path: paths.user,
                element: <SettingUser />,
            },
            {
                path: paths.contact,
                element: <Contact />,
            },
        ],
    },
    {
        path: "*",
        element: <NotFound />,
    },
]);

/**
 * ルータープロバイダー
 */
export const AppRouter = () => {
    return <RouterProvider router={router} />;
};
