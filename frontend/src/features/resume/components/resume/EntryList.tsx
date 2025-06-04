import { NoData } from "@/components/errors";
import { Button } from "@/components/ui";
import { EntryListItem, getResumeKey, sections, useResumeStore } from "@/features/resume";
import { DndContext, DragEndEvent, closestCenter } from "@dnd-kit/core";
import { SortableContext, arrayMove, verticalListSortingStrategy } from "@dnd-kit/sortable";
import { Add as AddIcon } from "@mui/icons-material";
import { Box, Divider, List, Typography } from "@mui/material";

/**
 * エントリーリスト
 */
export const EntryList = () => {
    // ストアから必要な状態を取り出す
    const { activeSection, setActiveEntryId, updateSection } = useResumeStore();

    // エントリーデータ取得
    const entries = useResumeStore((state) => {
        const key = getResumeKey(state.activeSection);
        return key ? state.resume?.[key] ?? [] : [];
    });

    // タイトル取得
    const title = sections.find((section) => section.key === activeSection)?.label + "一覧";

    /**
     * 新規追加
     */
    const handleNewClick = () => {
        setActiveEntryId(null);
    };

    /**
     * ドラッグ終了時の処理
     */
    const handleDragEnd = ({ active, over }: DragEndEvent) => {
        if (over && active.id !== over.id) {
            const oldIndex = (entries as any[]).findIndex((entry) => entry.id === (active.id as string));
            const newIndex = (entries as any[]).findIndex((entry) => entry.id === (over.id as string));
            const newEntries = arrayMove(entries as any[], oldIndex, newIndex);

            // orderNoを再計算
            const updatedEntries = newEntries.map((entry, index) => ({
                ...entry,
                orderNo: index,
            }));

            // ストアのデータを更新
            const sectionKey = getResumeKey(activeSection);
            if (sectionKey) {
                updateSection(sectionKey, updatedEntries);
            }
        }
    };

    return (
        <Box sx={{ bgcolor: "background.paper", borderRadius: 2, boxShadow: "0px 1px 3px 0px rgba(0, 0, 0, 0.2)" }}>
            {/* ヘッダー */}
            <Box
                sx={{
                    display: "flex",
                    justifyContent: "space-between",
                    alignItems: "center",
                    p: 2,
                }}
            >
                <Typography variant="h6">{title}</Typography>
                {/* 新規追加ボタン */}
                <Button size="small" startIcon={<AddIcon />} onClick={handleNewClick}>
                    新規追加
                </Button>
            </Box>
            <Divider />
            {/* エントリーリスト */}
            <Box sx={{ p: 2 }}>
                {entries.length > 0 ? (
                    <DndContext collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
                        <SortableContext
                            items={entries.map((entry: { id: string }) => entry.id)}
                            strategy={verticalListSortingStrategy}
                        >
                            <List sx={{ width: "100%" }}>
                                {/* エントリーアイテム */}
                                {entries.map((entry: { id: string }) => (
                                    <EntryListItem key={entry.id} entry={entry} />
                                ))}
                            </List>
                        </SortableContext>
                    </DndContext>
                ) : (
                    <Box sx={{ my: 20 }}>
                        <NoData variant="body1" message={"表示するデータがありません。"} />
                    </Box>
                )}
            </Box>
        </Box>
    );
};
