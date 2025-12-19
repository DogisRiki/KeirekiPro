import DragIndicatorIcon from "@mui/icons-material/DragIndicator";

interface DraggableIconProps {
    dragHandleProps?: Record<string, any>;
}

/**
 * ドラッグ可能なアイコン
 */
export const DraggableIcon = ({ dragHandleProps }: DraggableIconProps) => {
    return (
        <DragIndicatorIcon
            {...dragHandleProps}
            sx={{
                color: "text.secondary",
                cursor: "grab",
                // フォーカス時のアウトラインを消す
                "&:focus": {
                    outline: "none",
                },
                "&:focus-visible": {
                    outline: "none",
                },
                // Firefox用
                "&::-moz-focus-inner": {
                    border: 0,
                },
            }}
        />
    );
};
