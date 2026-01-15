import { createTheme } from "@mui/material";

/**
 * メインカラー
 */
const mainColor = "#2C3E50" as const;
/**
 * バックグランドカラー
 */
const BgColor = "#F5F5F5" as const;

const baseTheme = {
    typography: {
        fontFamily: 'Noto Sans JP, Roboto, "Helvetica Neue", Arial, sans-serif',
    },
};

/**
 * デフォルトテーマ
 */
export const lightTheme = createTheme({
    ...baseTheme,
    palette: {
        mode: "light",
        primary: {
            main: mainColor,
            light: "#2A3A48",
        },
        background: {
            default: BgColor,
        },
    },
    components: {
        MuiOutlinedInput: {
            styleOverrides: {
                root: {
                    "&.Mui-focused .MuiOutlinedInput-notchedOutline": {
                        borderColor: mainColor,
                    },
                },
                // ブラウザ標準のオートフィル時のハイライトを上書き
                input: {
                    "&:-webkit-autofill": {
                        WebkitBoxShadow: "0 0 0 1000px #fff inset",
                        WebkitTextFillColor: "inherit",
                        transition: "background-color 9999s ease-out 0s",
                    },
                    "&:-webkit-autofill:hover": {
                        WebkitBoxShadow: "0 0 0 1000px #fff inset",
                        WebkitTextFillColor: "inherit",
                        transition: "background-color 9999s ease-out 0s",
                    },
                    "&:-webkit-autofill:focus": {
                        WebkitBoxShadow: "0 0 0 1000px #fff inset",
                        WebkitTextFillColor: "inherit",
                        transition: "background-color 9999s ease-out 0s",
                    },
                },
            },
        },
        MuiFormLabel: {
            styleOverrides: {
                asterisk: {
                    color: "#D32F2F",
                    "&.Mui-error": {
                        color: "#D32F2F",
                    },
                },
            },
        },
        MuiFormControlLabel: {
            styleOverrides: {
                asterisk: {
                    color: "#D32F2F",
                    "&.Mui-error": {
                        color: "#D32F2F",
                    },
                },
            },
        },
    },
});

/**
 * ダークモード用テーマ
 */
export const darkTheme = createTheme({
    ...baseTheme,
    palette: {
        mode: "dark",
        primary: {
            main: "#CA9B7C",
            light: "#E0BFA8",
        },
        background: {
            default: "#2F2F2F",
            paper: "#393939",
        },
        text: {
            primary: "#ECECEC",
            secondary: "#A0A0A0",
        },
    },
    components: {
        MuiOutlinedInput: {
            styleOverrides: {
                root: {
                    "&.Mui-focused .MuiOutlinedInput-notchedOutline": {
                        borderColor: "#CA9B7C",
                    },
                },
                // ブラウザ標準のオートフィル時のハイライトを上書き
                input: {
                    "&:-webkit-autofill": {
                        WebkitBoxShadow: "0 0 0 1000px #393939 inset",
                        WebkitTextFillColor: "#ECECEC",
                        transition: "background-color 9999s ease-out 0s",
                    },
                    "&:-webkit-autofill:hover": {
                        WebkitBoxShadow: "0 0 0 1000px #393939 inset",
                        WebkitTextFillColor: "#ECECEC",
                        transition: "background-color 9999s ease-out 0s",
                    },
                    "&:-webkit-autofill:focus": {
                        WebkitBoxShadow: "0 0 0 1000px #393939 inset",
                        WebkitTextFillColor: "#ECECEC",
                        transition: "background-color 9999s ease-out 0s",
                    },
                },
            },
        },
        MuiFormLabel: {
            styleOverrides: {
                asterisk: {
                    color: "#f44336",
                    "&.Mui-error": {
                        color: "#f44336",
                    },
                },
            },
        },
        MuiFormControlLabel: {
            styleOverrides: {
                asterisk: {
                    color: "#f44336",
                    "&.Mui-error": {
                        color: "#f44336",
                    },
                },
            },
        },
    },
});
