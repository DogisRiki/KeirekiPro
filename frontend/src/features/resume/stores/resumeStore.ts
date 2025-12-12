import type { Resume, SectionName } from "@/features/resume";
import { create } from "zustand";
import { devtools } from "zustand/middleware";

/**
 * Resume型から配列を持つプロパティのみを抽出
 */
type ResumeArrayKeys = "careers" | "projects" | "certifications" | "portfolios" | "socialLinks" | "selfPromotions";

/**
 * リスト型セクション名（エントリーを持つセクション）
 */
type ListSectionName = Exclude<SectionName, "basicInfo">;

/**
 * セクションごとのアクティブエントリーID
 */
type ActiveEntryIdsBySection = Record<ListSectionName, string | null>;

/**
 * アクティブエントリーIDの初期値
 */
const initialActiveEntryIdsBySection: ActiveEntryIdsBySection = {
    career: null,
    project: null,
    certification: null,
    portfolio: null,
    socialLink: null,
    selfPromotion: null,
};

/**
 * ストアの型
 */
interface ResumeStoreState {
    // 現在のセクション
    activeSection: SectionName;

    // セクションごとの選択されているエントリーID
    activeEntryIdsBySection: ActiveEntryIdsBySection;

    // 現在のセクションのアクティブエントリーID（派生値として取得）
    activeEntryId: string | null;

    // 職務経歴書全体のデータ
    resume: Resume | null;

    // 未保存の変更があるかどうか
    isDirty: boolean;

    // 編集されたエントリーIDのSet
    dirtyEntryIds: Set<string>;

    // アクション
    setActiveSection: (section: SectionName) => void;
    setActiveEntryId: (entryId: string | null) => void;
    setResume: (resume: Resume) => void;
    initializeResume: (resume: Resume) => void;
    updateResume: (patch: Partial<Resume>) => void;
    updateSection: (section: ResumeArrayKeys, data: Resume[ResumeArrayKeys]) => void;
    updateEntry: (
        section: ResumeArrayKeys,
        entryId: string,
        updatedData: Partial<Resume[ResumeArrayKeys][number]>,
    ) => void;
    clearResume: () => void;
    setDirty: (isDirty: boolean) => void;
    clearDirtyEntryIds: (entryIds: string[]) => void;
}

/**
 * 現在のセクションのアクティブエントリーIDを取得するヘルパー
 */
const getActiveEntryId = (
    activeSection: SectionName,
    activeEntryIdsBySection: ActiveEntryIdsBySection,
): string | null => {
    if (activeSection === "basicInfo") {
        return null;
    }
    return activeEntryIdsBySection[activeSection];
};

/**
 * 職務経歴書を管理するストア
 */
export const useResumeStore = create<ResumeStoreState>()(
    devtools(
        (set) => ({
            // 初期状態
            activeSection: "basicInfo",
            activeEntryIdsBySection: { ...initialActiveEntryIdsBySection },
            activeEntryId: null,
            resume: null,
            isDirty: false,
            dirtyEntryIds: new Set(),

            // アクション: セクションの切り替え
            setActiveSection: (section) =>
                set(
                    (state) => ({
                        activeSection: section,
                        activeEntryId: getActiveEntryId(section, state.activeEntryIdsBySection),
                    }),
                    false,
                    "setActiveSection",
                ),

            // アクション: エントリーIDの設定（現在のセクションに対して設定）
            setActiveEntryId: (entryId) =>
                set(
                    (state) => {
                        const { activeSection } = state;
                        if (activeSection === "basicInfo") {
                            return { activeEntryId: null };
                        }
                        return {
                            activeEntryIdsBySection: {
                                ...state.activeEntryIdsBySection,
                                [activeSection]: entryId,
                            },
                            activeEntryId: entryId,
                        };
                    },
                    false,
                    "setActiveEntryId",
                ),

            // アクション: 職務経歴書全体の設定（保存成功時に使用、isDirtyをfalseに）
            setResume: (resume) => set({ resume, isDirty: false }, false, "setResume"),

            // アクション: 職務経歴書の初期化（画面初期表示時に使用、activeSection/activeEntryIdもリセット）
            initializeResume: (resume) =>
                set(
                    {
                        resume,
                        isDirty: false,
                        activeSection: "basicInfo",
                        activeEntryIdsBySection: { ...initialActiveEntryIdsBySection },
                        activeEntryId: null,
                        dirtyEntryIds: new Set(),
                    },
                    false,
                    "initializeResume",
                ),

            // アクション: 職務経歴書の部分更新（変更時はdirtyをtrueに）
            updateResume: (patch) =>
                set(
                    (state) => ({
                        resume: state.resume ? { ...state.resume, ...patch } : null,
                        isDirty: true,
                    }),
                    false,
                    "updateResume",
                ),

            // アクション: セクションデータの更新（変更時はdirtyをtrueに、新規エントリーをdirtyEntryIdsに追加）
            updateSection: (section, data) =>
                set(
                    (state) => {
                        const currentIds = new Set(state.resume?.[section]?.map((item) => item.id) ?? []);
                        const newIds = data.map((item) => item.id).filter((id) => !currentIds.has(id));
                        const newDirtyEntryIds = new Set(state.dirtyEntryIds);
                        newIds.forEach((id) => newDirtyEntryIds.add(id));

                        return {
                            resume: state.resume
                                ? {
                                      ...state.resume,
                                      [section]: data,
                                  }
                                : null,
                            isDirty: true,
                            dirtyEntryIds: newDirtyEntryIds,
                        };
                    },
                    false,
                    "updateSection",
                ),

            // アクション: 特定エントリーの更新（変更時はdirtyをtrueに、entryIdをdirtyEntryIdsに追加）
            updateEntry: (section, entryId, updatedData) =>
                set(
                    (state) => {
                        if (!state.resume) return { resume: null };
                        const sectionData = state.resume[section];
                        const newDirtyEntryIds = new Set(state.dirtyEntryIds);
                        newDirtyEntryIds.add(entryId);

                        return {
                            resume: {
                                ...state.resume,
                                [section]: sectionData.map((entry) =>
                                    entry.id === entryId ? { ...entry, ...updatedData } : entry,
                                ),
                            },
                            isDirty: true,
                            dirtyEntryIds: newDirtyEntryIds,
                        };
                    },
                    false,
                    "updateEntry",
                ),

            // アクション: ストアのクリア
            clearResume: () =>
                set(
                    {
                        resume: null,
                        activeSection: "basicInfo",
                        activeEntryIdsBySection: { ...initialActiveEntryIdsBySection },
                        activeEntryId: null,
                        isDirty: false,
                        dirtyEntryIds: new Set(),
                    },
                    false,
                    "clearResume",
                ),

            // アクション: dirty状態の設定
            setDirty: (isDirty) => set({ isDirty }, false, "setDirty"),

            // アクション: 指定されたエントリーIDをdirtyEntryIdsから削除
            clearDirtyEntryIds: (entryIds) =>
                set(
                    (state) => {
                        const newDirtyEntryIds = new Set(state.dirtyEntryIds);
                        entryIds.forEach((id) => newDirtyEntryIds.delete(id));
                        return { dirtyEntryIds: newDirtyEntryIds };
                    },
                    false,
                    "clearDirtyEntryIds",
                ),
        }),
        { name: "ResumeStore" },
    ),
);
