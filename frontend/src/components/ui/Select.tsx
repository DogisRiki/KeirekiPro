import { Select as MUISelect, SelectProps } from "@mui/material";

/**
 * セレクトボックス
 */
export const Select = (props: SelectProps<any>) => {
    return <MUISelect {...props} />;
};
