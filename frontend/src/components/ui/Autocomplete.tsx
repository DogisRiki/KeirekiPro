import { AutocompleteProps, Autocomplete as MUIAutocomplete } from "@mui/material";

/**
 * オートコンプリート
 */
export const Autocomplete = <Value,>(props: AutocompleteProps<Value, any, any, any>) => {
    return <MUIAutocomplete {...props} />;
};
