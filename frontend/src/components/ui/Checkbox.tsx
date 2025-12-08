import type { CheckboxProps } from "@mui/material";
import { Checkbox as MUICheckbox } from "@mui/material";

/**
 * チェックボックス
 */
export const Checkbox = (props: CheckboxProps) => {
    return <MUICheckbox {...props} />;
};
