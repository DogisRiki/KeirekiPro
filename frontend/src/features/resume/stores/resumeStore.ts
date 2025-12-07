import type { Resume } from "@/features/resume";
import { create } from "zustand";
import { devtools } from "zustand/middleware";

/**
 * Resume型から配列を持つプロパティのみを抽出
 */
type ResumeArrayKeys = "careers" | "projects" | "certifications" | "portfolios" | "socialLinks" | "selfPromotions";

/**
 * ストアの型
 */
interface ResumeStoreState {
    // 現在のセクション
    activeSection: "basicInfo" | "career" | "project" | "certification" | "portfolio" | "socialLink" | "selfPromotion";

    // 選択されているエントリーID
    activeEntryId: string | null;

    // 職務経歴書全体のデータ
    resume: Resume | null;

    // アクション
    setActiveSection: (section: ResumeStoreState["activeSection"]) => void;
    setActiveEntryId: (entryId: string | null) => void;
    setResume: (resume: Resume) => void;
    updateSection: (section: ResumeArrayKeys, data: Resume[ResumeArrayKeys]) => void;
    updateEntry: (
        section: ResumeArrayKeys,
        entryId: string,
        updatedData: Partial<Resume[ResumeArrayKeys][number]>,
    ) => void;
}

/**
 * 職務経歴書を管理するストア
 */
export const useResumeStore = create<ResumeStoreState>()(
    devtools((set) => ({
        // 初期状態
        activeSection: "basicInfo",
        activeEntryId: null,
        resume: null,

        // アクション: セクションの切り替え
        setActiveSection: (section) => set({ activeSection: section }),

        // アクション: エントリーIDの設定
        setActiveEntryId: (entryId) => set({ activeEntryId: entryId }),

        // アクション: 職務経歴書全体の設定
        setResume: (resume) => set({ resume }),

        // アクション: セクションデータの更新
        updateSection: (section, data) =>
            set((state) => ({
                resume: {
                    ...state.resume!,
                    [section]: data,
                },
            })),

        // アクション: 特定エントリーの更新
        updateEntry: (section, entryId, updatedData) =>
            set((state) => {
                const sectionData = state.resume![section];
                return {
                    resume: {
                        ...state.resume!,
                        [section]: sectionData.map((entry) =>
                            entry.id === entryId ? { ...entry, ...updatedData } : entry,
                        ),
                    },
                };
            }),
    })),
);
