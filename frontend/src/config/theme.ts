import { createTheme } from "@mui/material";

/**
 * メインカラー
 */
const mainColor = "#2C3E50" as const;
/**
 * バックグランドカラー
 */
const BgColor = "#F5F5F5" as const;

/**
 * MUI theme
 */
export const theme = createTheme({
    palette: {
        primary: {
            main: mainColor,
            light: "#2A3A48",
        },
        background: {
            default: BgColor,
        },
    },
    typography: {
        fontFamily: 'Noto Sans JP, Roboto, "Helvetica Neue", Arial, sans-serif',
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
                        WebkitBoxShadow: "0 0 0 1000px #fff inset", // TextField の背景色に合わせて調整
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
                    "&$error": {
                        color: "#D32F2F",
                    },
                },
            },
        },
        MuiFormControlLabel: {
            styleOverrides: {
                asterisk: {
                    color: "#D32F2F",
                    "&$error": {
                        color: "#D32F2F",
                    },
                },
            },
        },
    },
});
