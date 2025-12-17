import type { SelectProps } from "@mui/material";
import { Select as MUISelect } from "@mui/material";

/**
 * セレクトボックス
 */
export const Select = (props: SelectProps<any>) => {
    return <MUISelect {...props} />;
};
