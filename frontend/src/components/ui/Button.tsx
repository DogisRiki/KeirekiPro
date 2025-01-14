import { ButtonProps, Button as MuiButton } from "@mui/material";
import { SxProps, Theme } from "@mui/system";

/**
 * ボタン
 */
export const Button = (props: ButtonProps) => {
    const { sx, ...otherProps } = props;

    const defaultSx: SxProps<Theme> = {
        textTransform: "none",
    };

    const combinedSx: SxProps<Theme> = {
        ...(sx as object),
        ...defaultSx,
    };

    return (
        <MuiButton variant="contained" sx={combinedSx} {...otherProps}>
            {props.children}
        </MuiButton>
    );
};
