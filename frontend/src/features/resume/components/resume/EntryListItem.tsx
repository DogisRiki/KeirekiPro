import { DraggableIcon } from "@/components/dnd/DraggableIcon";
import { getEntryText, useResumeStore } from "@/features/resume";
import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { ListItem, ListItemButton, ListItemText } from "@mui/material";

/**
 * エントリーリストアイテムのProps
 */
interface EntryListItemProps {
    entry: { id: string };
}

/**
 * エントリーリストアイテム
 */
export const EntryListItem = ({ entry }: EntryListItemProps) => {
    // ストアから必要な状態を取り出す
    const { activeSection, activeEntryId, setActiveEntryId } = useResumeStore();

    // sortableの設定
    const { attributes, listeners, setNodeRef, transform, transition } = useSortable({ id: entry.id });

    // スタイル
    const style = {
        transform: CSS.Transform.toString(transform),
        transition,
    };

    return (
        <div ref={setNodeRef} style={style}>
            <ListItem disablePadding sx={{ mb: 1 }}>
                <ListItemButton
                    selected={activeEntryId === entry.id}
                    onClick={() => setActiveEntryId(entry.id)}
                    sx={{
                        display: "flex",
                        justifyContent: "space-between",
                        alignItems: "center",
                    }}
                >
                    <ListItemText
                        primary={getEntryText(activeSection, entry)?.primary || ""}
                        secondary={getEntryText(activeSection, entry)?.secondary || ""}
                        slotProps={{
                            primary: {
                                sx: {
                                    fontWeight: activeEntryId === entry.id ? "bold" : "normal",
                                    whiteSpace: "nowrap",
                                    overflow: "hidden",
                                    textOverflow: "ellipsis",
                                },
                            },
                            secondary: {
                                sx: {
                                    whiteSpace: "nowrap",
                                    overflow: "hidden",
                                    textOverflow: "ellipsis",
                                },
                            },
                        }}
                    />
                    {/* ドラッグアイコン */}
                    <DraggableIcon dragHandleProps={{ ...attributes, ...listeners }} />
                </ListItemButton>
            </ListItem>
        </div>
    );
};
