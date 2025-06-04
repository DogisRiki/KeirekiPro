import { Backdrop, CircularProgress } from "@mui/material";
import { useIsFetching, useIsMutating } from "@tanstack/react-query";

/**
 * ローディング
 */
export const Loading = () => {
    const fetching = useIsFetching();
    const mutating = useIsMutating();
    const open = fetching + mutating > 0;

    return (
        <Backdrop
            open={open}
            sx={{
                zIndex: (t) => t.zIndex.modal + 1,
                bgcolor: "rgba(0,0,0,0.4)",
            }}
        >
            <CircularProgress size={60} color="inherit" />
        </Backdrop>
    );
};
