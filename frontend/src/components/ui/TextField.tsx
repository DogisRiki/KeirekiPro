import type { TextFieldProps } from "@mui/material";
import { TextField as MUITextField } from "@mui/material";

/**
 * テキストフィールド
 */
export const TextField = (props: TextFieldProps) => {
    return <MUITextField {...props} />;
};
