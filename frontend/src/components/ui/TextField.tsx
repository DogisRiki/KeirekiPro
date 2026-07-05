import type { TextFieldProps } from "@mui/material";
import { TextField as MUITextField } from "@mui/material";
import { forwardRef } from "react";

/**
 * テキストフィールド
 */
export const TextField = forwardRef<HTMLDivElement, TextFieldProps>((props, ref) => {
    return <MUITextField ref={ref} {...props} />;
});

TextField.displayName = "TextField";
