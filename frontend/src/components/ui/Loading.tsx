import { Box, CircularProgress } from "@mui/material";
import type { SxProps, Theme } from "@mui/material/styles";
import { alpha } from "@mui/material/styles";

type LoadingVariant = "content" | "inline" | "overlay";

interface LoadingProps {
    active: boolean;
    variant?: LoadingVariant;
    size?: number;
    sx?: SxProps<Theme>;
}

const mergeSx = (baseSx: SxProps<Theme>, sx?: SxProps<Theme>): SxProps<Theme> => {
    if (!sx) return baseSx;
    return {
        ...(baseSx as object),
        ...(sx as object),
    };
};

/**
 * ローディング
 */
export const Loading = ({ active, variant = "content", size = 40, sx }: LoadingProps) => {
    if (!active) return null;

    if (variant === "inline") {
        return <CircularProgress size={size} sx={sx} />;
    }

    const progress = <CircularProgress size={size} />;

    if (variant === "overlay") {
        return (
            <Box
                sx={mergeSx(
                    {
                        position: "absolute",
                        inset: 0,
                        zIndex: 1,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        bgcolor: (theme) => alpha(theme.palette.background.paper, 0.72),
                    },
                    sx,
                )}
            >
                {progress}
            </Box>
        );
    }

    return (
        <Box
            sx={mergeSx(
                {
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    width: "100%",
                    minHeight: 240,
                },
                sx,
            )}
        >
            {progress}
        </Box>
    );
};
