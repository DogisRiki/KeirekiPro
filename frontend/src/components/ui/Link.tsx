import type { LinkProps as MuiLinkProps } from "@mui/material";
import { Link as MuiLink } from "@mui/material";
import type { LinkProps as RouterLinkProps } from "react-router";
import { Link as RouterLink } from "react-router";
/**
 * リンク
 */
export const Link = (props: MuiLinkProps & RouterLinkProps) => {
    const { sx, to, ...otherProps } = props;

    return (
        <MuiLink component={RouterLink} to={to} sx={sx} {...otherProps}>
            {props.children}
        </MuiLink>
    );
};
