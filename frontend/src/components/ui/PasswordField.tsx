import { Visibility, VisibilityOff } from "@mui/icons-material";
import { IconButton, InputAdornment, TextField, TextFieldProps } from "@mui/material";
import { useState } from "react";

/**
 * パスワード入力用のカスタムコンポーネント
 */
export const PasswordTextField = (props: TextFieldProps) => {
    const [showPassword, setShowPassword] = useState(false);
    const { slotProps, ...otherProps } = props;

    const handleTogglePasswordVisibility = () => {
        setShowPassword((prev) => !prev);
    };

    const defaultSlotProps = {
        inputLabel: {
            shrink: true,
            ...slotProps?.inputLabel,
        },
        input: {
            ...slotProps?.input,
            endAdornment: (
                <InputAdornment
                    position="end"
                    sx={{
                        marginRight: "0px", // デフォルトのマージンをリセット
                        transform: "translateX(-8px)", // アイコンを左に8px移動
                    }}
                >
                    <IconButton onClick={handleTogglePasswordVisibility} edge="end">
                        {showPassword ? <VisibilityOff /> : <Visibility />}
                    </IconButton>
                </InputAdornment>
            ),
        },
    };

    return <TextField type={showPassword ? "text" : "password"} slotProps={defaultSlotProps} {...otherProps} />;
};
