import type { DatePickerProps } from "@mui/x-date-pickers";
import { DatePicker as MUIDatePicker } from "@mui/x-date-pickers";
import type { Dayjs } from "dayjs";
import * as React from "react";

/**
 * DatePicker
 * - キーボード入力（打鍵/貼り付け）を無効化
 * - フィールドのどこをクリックしてもpickerを開く
 */
export const DatePicker = (props: DatePickerProps<Dayjs>) => {
    const { slotProps, open: openProp, onOpen, onClose, ...rest } = props as any;

    const isControlled = openProp !== undefined;

    const [uncontrolledOpen, setUncontrolledOpen] = React.useState(false);
    const open = isControlled ? openProp : uncontrolledOpen;

    const handleOpen = (event?: any) => {
        if (!isControlled) setUncontrolledOpen(true);
        onOpen?.(event);
    };

    const handleClose = (event?: any) => {
        if (!isControlled) setUncontrolledOpen(false);
        onClose?.(event);
    };

    const textField = (slotProps?.textField ?? {}) as any;

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
                    onClick: (e: any) => {
                        textField.onClick?.(e);
                        handleOpen(e);
                    },

                    // キーボード入力（Tab以外）を抑止。Enter/Space は「開く」に寄せる
                    onKeyDown: (e: React.KeyboardEvent) => {
                        textField.onKeyDown?.(e);
                        if (e.key === "Tab") return;
                        if (e.key === "Enter" || e.key === " ") {
                            e.preventDefault();
                            handleOpen(e);
                            return;
                        }
                        e.preventDefault();
                    },

                    // 貼り付け抑止
                    onPaste: (e: React.ClipboardEvent) => {
                        textField.onPaste?.(e);
                        e.preventDefault();
                    },

                    // 入力欄を readOnly にして、IME/ソフトキーボード入力も抑止
                    inputProps: {
                        ...(textField.inputProps ?? {}),
                        readOnly: true,
                        inputMode: "none",
                    },
                },
            }}
        />
    );
};
