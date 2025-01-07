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
        change: "/password/change",
    },
    twoFactor: "/two-factor",
    resume: {
        list: "/resume/list",
        new: "/resume/new",
        edit: "/resume/:id",
    },
    user: "/user",
    contact: "/contact",
    terms: "/terms",
    privacy: "/privacy",
};
