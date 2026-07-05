import type { DatePickerProps } from "@mui/x-date-pickers";
import { DatePicker as MUIDatePicker } from "@mui/x-date-pickers";
import type { Dayjs } from "dayjs";
import * as React from "react";

type DatePickerSlotProps = NonNullable<DatePickerProps<Dayjs>["slotProps"]>;
type DatePickerTextFieldSlotProps = Exclude<DatePickerSlotProps["textField"], (...args: never[]) => unknown>;

/**
 * DatePicker
 * - キーボード入力（打鍵/貼り付け）を無効化
 * - フィールドのどこをクリックしてもpickerを開く
 */
export const DatePicker = (props: DatePickerProps<Dayjs>) => {
    const { slotProps, open: openProp, onOpen, onClose, ...rest } = props;

    const isControlled = openProp !== undefined;

    const [uncontrolledOpen, setUncontrolledOpen] = React.useState(false);
    const open = isControlled ? openProp : uncontrolledOpen;

    const handleOpen = () => {
        if (!isControlled) setUncontrolledOpen(true);
        onOpen?.();
    };

    const handleClose = () => {
        if (!isControlled) setUncontrolledOpen(false);
        onClose?.();
    };

    const textField: DatePickerTextFieldSlotProps | undefined =
        typeof slotProps?.textField === "function" ? undefined : slotProps?.textField;
    const textFieldSlotProps = textField?.slotProps;
    const htmlInput = typeof textFieldSlotProps?.htmlInput === "function" ? undefined : textFieldSlotProps?.htmlInput;

    return (
        <MUIDatePicker
            {...rest}
            open={open}
            onOpen={handleOpen}
            onClose={handleClose}
            slotProps={{
                ...slotProps,
                textField: {
                    ...textField,

                    // どこを触っても開く
                    onClick: (e: React.MouseEvent<HTMLDivElement>) => {
                        textField?.onClick?.(e);
                        handleOpen();
                    },

                    // キーボード入力（Tab以外）を抑止。Enter/Space は「開く」に寄せる
                    onKeyDown: (e: React.KeyboardEvent<HTMLDivElement>) => {
                        textField?.onKeyDown?.(e);
                        if (e.key === "Tab") return;
                        if (e.key === "Enter" || e.key === " ") {
                            e.preventDefault();
                            handleOpen();
                            return;
                        }
                        e.preventDefault();
                    },

                    // 貼り付け抑止
                    onPaste: (e: React.ClipboardEvent<HTMLDivElement>) => {
                        textField?.onPaste?.(e);
                        e.preventDefault();
                    },

                    // 入力欄を readOnly にして、IME/ソフトキーボード入力も抑止
                    slotProps: {
                        ...textFieldSlotProps,
                        htmlInput: {
                            ...htmlInput,
                            readOnly: true,
                            inputMode: "none",
                        },
                    },
                },
            }}
        />
    );
};
