/**
 * パス設定
 */
export const paths = {
    top: "/",
    login: "/login",
    register: "/register",
    password: {
        resetRquest: "/password/reset",
        reset: "/password/reset/:token",
        verify: "/password/verify",
    },
    twoFactor: "/two-factor",
    resume: {
        list: "/resume/list",
        new: "/resume/new",
        edit: "/resume/:id",
    },
    user: "/user",
    contact: "/contact",
};
