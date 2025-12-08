import type { DatePickerProps } from "@mui/x-date-pickers";
import { DatePicker as MUIDatePicker } from "@mui/x-date-pickers";
import type { Dayjs } from "dayjs";

/**
 * DatePicker
 */
export const DatePicker = (props: DatePickerProps<Dayjs>) => {
    return <MUIDatePicker {...props} />;
};
