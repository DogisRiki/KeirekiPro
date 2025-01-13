import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { ReactNode } from "react";

/**
 * ドラッグ可能なリストアイテム
 */
interface SortableItemProps {
    id: string;
    children: ReactNode;
}

/**
 * dnd-kitのドラッグ可能なコンポーネント
 */
export const SortableItem = ({ id, children }: SortableItemProps) => {
    const { attributes, listeners, setNodeRef, transform, transition } = useSortable({ id });

    const style = {
        transform: CSS.Transform.toString(transform),
        transition,
    };

    return (
        <div ref={setNodeRef} style={style} {...attributes} {...listeners}>
            {children}
        </div>
    );
};
