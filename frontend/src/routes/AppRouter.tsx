import { ErrorFallback, NotFound } from "@/components/errors";
import { ProtectedLayout, PublicLayout } from "@/components/layouts";
import { paths } from "@/config/paths";
import {
    ChangePassword,
    Contact,
    Login,
    Privacy,
    Register,
    RequestPasswordReset,
    ResetPassword,
    Resume,
    ResumeList,
    SettingUser,
    Terms,
    Top,
    TwoFactor,
} from "@/pages";
import { SetEmailAndPassword } from "@/pages/SetEmailAndPassword";
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
        errorElement: <ErrorFallback />,
    },
    {
        element: <PublicLayout />,
        loader: PublicLoader,
        errorElement: <ErrorFallback />,
        children: [
            { path: paths.login, element: <Login /> },
            { path: paths.twoFactor, element: <TwoFactor /> },
            { path: paths.register, element: <Register /> },
            { path: paths.password.resetRequest, element: <RequestPasswordReset /> },
            { path: paths.password.reset, element: <ResetPassword /> },
        ],
    },
    {
        element: <ProtectedLayout />,
        loader: ProtectedLoader,
        errorElement: <ErrorFallback />,
        children: [
            { path: paths.resume.list, element: <ResumeList /> },
            { path: paths.resume.new, element: <Resume /> },
            { path: paths.resume.edit, element: <ResumeList /> },
            { path: paths.user, element: <SettingUser /> },
            { path: paths.password.change, element: <ChangePassword /> },
            { path: paths.emailPassword.set, element: <SetEmailAndPassword /> },
            { path: paths.contact, element: <Contact /> },
        ],
    },
    { path: paths.terms, element: <Terms />, errorElement: <ErrorFallback /> },
    { path: paths.privacy, element: <Privacy />, errorElement: <ErrorFallback /> },
    { path: "*", element: <NotFound />, errorElement: <ErrorFallback /> },
]);

/**
 * ルータープロバイダー
 */
export const AppRouter = () => {
    return <RouterProvider router={router} />;
};
