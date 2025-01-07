import { TextField as MUITextField, TextFieldProps } from "@mui/material";

/**
 * テキストフィールド
 */
export const TextField = (props: TextFieldProps) => {
    return <MUITextField {...props} />;
};
