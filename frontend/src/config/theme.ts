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
    },
});
