import type { SwitchProps } from "@mui/material";
import { Switch as MUISwitch } from "@mui/material";

/**
 * Switch
 */
export const Switch = (props: SwitchProps) => {
    return <MUISwitch {...props} />;
};
