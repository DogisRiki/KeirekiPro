import { Link as MuiLink, LinkProps as MuiLinkProps } from "@mui/material";
import { Link as RouterLink, LinkProps as RouterLinkProps } from "react-router";

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
