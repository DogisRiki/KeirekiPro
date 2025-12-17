import type { TypographyProps } from "@mui/material";
import { Typography } from "@mui/material";
import type { SxProps, Theme } from "@mui/system";

interface NoDataProps extends Omit<TypographyProps, "children"> {
    message: string;
}

/**
 * データがないときに表示する
 */
export const NoData = ({ message, sx, ...props }: NoDataProps) => {
    const defaultSx: SxProps<Theme> = {
        textAlign: "center",
    };

    const combinedSx: SxProps<Theme> = {
        ...(sx as object),
        ...defaultSx,
    };

    return (
        <Typography color="text.secondary" sx={combinedSx} {...props}>
            {message}
        </Typography>
    );
};
