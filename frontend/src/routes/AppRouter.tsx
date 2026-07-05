import { ErrorFallback, NotFound, ServerError } from "@/components/errors";
import { ProtectedLayout, PublicLayout } from "@/components/layouts";
import { paths } from "@/config/paths";
import { ProtectedLoader, PublicLoader } from "@/routes/AppLoader";
import { Box, CircularProgress } from "@mui/material";
import { lazy, Suspense } from "react";
import { createBrowserRouter, RouterProvider } from "react-router";

const Backup = lazy(() => import("@/pages/Backup").then((module) => ({ default: module.Backup })));
const ChangePassword = lazy(() =>
    import("@/pages/ChangePassword").then((module) => ({ default: module.ChangePassword })),
);
const Contact = lazy(() => import("@/pages/Contact").then((module) => ({ default: module.Contact })));
const LandingPage = lazy(() => import("@/pages/LandingPage").then((module) => ({ default: module.LandingPage })));
const Login = lazy(() => import("@/pages/Login").then((module) => ({ default: module.Login })));
const Maintenance = lazy(() => import("@/pages/Maintenance").then((module) => ({ default: module.Maintenance })));
const Privacy = lazy(() => import("@/pages/Privacy").then((module) => ({ default: module.Privacy })));
const Register = lazy(() => import("@/pages/Register").then((module) => ({ default: module.Register })));
const RequestPasswordReset = lazy(() =>
    import("@/pages/RequestPasswordReset").then((module) => ({ default: module.RequestPasswordReset })),
);
const ResetPassword = lazy(() => import("@/pages/ResetPassword").then((module) => ({ default: module.ResetPassword })));
const Resume = lazy(() => import("@/pages/Resume").then((module) => ({ default: module.Resume })));
const ResumeList = lazy(() => import("@/pages/ResumeList").then((module) => ({ default: module.ResumeList })));
const ResumeNew = lazy(() => import("@/pages/ResumeNew").then((module) => ({ default: module.ResumeNew })));
const SetEmailAndPassword = lazy(() =>
    import("@/pages/SetEmailAndPassword").then((module) => ({ default: module.SetEmailAndPassword })),
);
const SettingUser = lazy(() => import("@/pages/SettingUser").then((module) => ({ default: module.SettingUser })));
const Terms = lazy(() => import("@/pages/Terms").then((module) => ({ default: module.Terms })));
const TwoFactor = lazy(() => import("@/pages/TwoFactor").then((module) => ({ default: module.TwoFactor })));

const routeFallback = (
    <Box sx={{ display: "flex", justifyContent: "center", alignItems: "center", minHeight: 240 }}>
        <CircularProgress size={40} />
    </Box>
);

/**
 * ルーティング
 */
const router = createBrowserRouter([
    {
        path: paths.top,
        element: <LandingPage />,
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
            { path: paths.resume.new, element: <ResumeNew /> },
            { path: paths.resume.edit, element: <Resume /> },
            { path: paths.backup, element: <Backup /> },
            { path: paths.user, element: <SettingUser /> },
            { path: paths.password.change, element: <ChangePassword /> },
            { path: paths.emailPassword.set, element: <SetEmailAndPassword /> },
            { path: paths.contact, element: <Contact /> },
        ],
    },

    { path: paths.terms, element: <Terms />, errorElement: <ErrorFallback /> },
    { path: paths.privacy, element: <Privacy />, errorElement: <ErrorFallback /> },
    { path: paths.serverError, element: <ServerError />, errorElement: <ErrorFallback /> },
    { path: paths.maintenance, element: <Maintenance />, errorElement: <ErrorFallback /> },
    { path: "*", element: <NotFound />, errorElement: <ErrorFallback /> },
]);

/**
 * ルータープロバイダー
 */
export const AppRouter = () => {
    return (
        <Suspense fallback={routeFallback}>
            <RouterProvider router={router} />
        </Suspense>
    );
};
