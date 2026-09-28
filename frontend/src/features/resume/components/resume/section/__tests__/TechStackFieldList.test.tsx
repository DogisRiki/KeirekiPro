import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { get: vi.fn() },
}));

import type { Project, TechStack } from "@/features/resume";
import { TechStackFieldList, techStackInfo, useResumeStore } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { createAxiosResponse, renderWithProviders, resetStoresAndMocks } from "@/test";
import { screen, waitFor } from "@testing-library/react";

import { cloneResume, emptyTechStack } from "../../../__tests__/resumeTestData";

/** 候補のマスタ。カテゴリごとに見分けられる値を入れる */
const masterTechStack: TechStack = {
    ...structuredClone(emptyTechStack),
    frontend: { ...emptyTechStack.frontend, languages: ["TypeScript", "JavaScript"] },
    backend: { ...emptyTechStack.backend, languages: ["Java", "Kotlin"] },
};

/** 選択中のプロジェクトを1件持つ状態で描画する */
const renderList = ({
    project = {},
    activeEntryId = "project-1",
}: { project?: Partial<Project>; activeEntryId?: string | null } = {}) => {
    const base = cloneResume();
    const store = useResumeStore.getState();
    store.setResume({ ...base, projects: [{ ...base.projects[0], ...project }] });
    store.setActiveSection("project");
    store.setActiveEntryId(activeEntryId);
    return renderWithProviders(<TechStackFieldList />);
};

const currentTechStack = () => useResumeStore.getState().resume?.projects[0].techStack;

/**
 * カテゴリの見出しを押して開く
 * (閉じたカテゴリの欄は隠れるため、開いたカテゴリの欄だけが操作の対象になる)
 */
const openCategory = async (user: ReturnType<typeof renderList>["user"], title: string) => {
    const summary = screen.getByRole("button", { name: title });
    await user.click(summary);
    await waitFor(() => expect(summary).toHaveAttribute("aria-expanded", "true"));
};

describe("TechStackFieldList", () => {
    beforeEach(() => {
        resetStoresAndMocks([() => vi.mocked(protectedApiClient.get).mockReset()]);
        vi.mocked(protectedApiClient.get).mockResolvedValue(createAxiosResponse(masterTechStack));
    });

    it.each(techStackInfo)("$title を開くと、そのカテゴリの入力欄を表示すること", async ({ title, fields }) => {
        const { user } = renderList();

        await openCategory(user, title);

        expect(screen.getAllByRole("combobox")).toHaveLength(fields.length);
        fields.forEach((field) => {
            expect(screen.getByRole("combobox", { name: field.label })).toBeInTheDocument();
        });
    });

    it("プロジェクトで選んでいる値を、対応する欄に表示すること", async () => {
        const { user } = renderList({
            project: {
                techStack: {
                    ...structuredClone(emptyTechStack),
                    backend: { ...emptyTechStack.backend, languages: ["Java"] },
                },
            },
        });

        await openCategory(user, "フロントエンド");
        expect(screen.queryByRole("button", { name: "Java" })).not.toBeInTheDocument();

        await openCategory(user, "バックエンド");
        expect(screen.getByRole("button", { name: "Java" })).toBeInTheDocument();
    });

    it("欄の候補には、マスタの同じ項目の値を出すこと", async () => {
        const { user } = renderList();

        await openCategory(user, "バックエンド");
        await user.click(screen.getByRole("combobox", { name: "言語" }));

        const optionNames = (await screen.findAllByRole("option")).map((option) => option.textContent);
        expect(optionNames).toEqual(["Java", "Kotlin"]);
    });

    it("欄に値を足すと、プロジェクトのその項目だけを更新すること", async () => {
        const original = {
            ...structuredClone(emptyTechStack),
            frontend: { ...emptyTechStack.frontend, languages: ["TypeScript"] },
            tools: { ...emptyTechStack.tools, editors: ["VSCode"] },
        };
        const { user } = renderList({ project: { techStack: original } });

        await openCategory(user, "バックエンド");
        await user.type(screen.getByRole("combobox", { name: "言語" }), "java{Enter}");

        expect(currentTechStack()).toEqual({
            ...original,
            backend: { ...original.backend, languages: ["Java"] },
        });
        expect(useResumeStore.getState().dirtyEntryIds.has("project-1")).toBe(true);
    });

    it("プロジェクトが選ばれていないときは、値を足してもストアを変えないこと", async () => {
        const { user } = renderList({ activeEntryId: null });
        const before = useResumeStore.getState().resume;

        await openCategory(user, "バックエンド");
        await user.type(screen.getByRole("combobox", { name: "言語" }), "Java{Enter}");

        expect(useResumeStore.getState().resume).toBe(before);
        expect(useResumeStore.getState().dirtyEntryIds.size).toBe(0);
    });

    it("プロジェクトに技術スタックが無いときは、値を足してもストアを変えないこと", async () => {
        const { user } = renderList({ project: { techStack: null as unknown as TechStack } });

        await openCategory(user, "バックエンド");
        await user.type(screen.getByRole("combobox", { name: "言語" }), "Java{Enter}");

        expect(currentTechStack()).toBeNull();
        expect(useResumeStore.getState().dirtyEntryIds.size).toBe(0);
    });
});
