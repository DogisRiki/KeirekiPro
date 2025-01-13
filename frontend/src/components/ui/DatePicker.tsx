import { DatePickerProps, DatePicker as MUIDatePicker } from "@mui/x-date-pickers";
import { Dayjs } from "dayjs";

/**
 * DatePicker
 */
export const DatePicker = (props: DatePickerProps<Dayjs>) => {
    return <MUIDatePicker {...props} />;
};
