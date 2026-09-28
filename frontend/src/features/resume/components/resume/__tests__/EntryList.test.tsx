import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: {
        get: vi.fn(),
        post: vi.fn(),
        put: vi.fn(),
        delete: vi.fn(),
    },
}));

import type { Resume, SectionName } from "@/features/resume";
import { EntryList, useResumeStore } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { createAxiosResponse, renderWithProviders, resetStoresAndMocks } from "@/test";
import { screen, waitFor, within } from "@testing-library/react";
import { Route, Routes } from "react-router";

import { cloneResume, emptyTechStack } from "../../__tests__/resumeTestData";

/** 一覧型セクションの、職務経歴書上のキー(ストアの型は公開されていないため、updateSection の引数から取る) */
type ResumeArrayKeys = Parameters<ReturnType<typeof useResumeStore.getState>["updateSection"]>[0];

/** 各セクションに既存の項目を1件ずつ持つ職務経歴書 */
const fullResume = (): Resume =>
    cloneResume({
        certifications: [{ id: "certification-1", name: "基本情報技術者", date: "2020-04" }],
        portfolios: [
            { id: "portfolio-1", name: "Portfolio A", overview: "概要", techStack: null, link: "https://a.example" },
        ],
        snsPlatforms: [{ id: "sns-1", name: "GitHub", link: "https://github.com/example" }],
        selfPromotions: [{ id: "self-1", title: "強み", content: "内容" }],
    });

const sectionCases: {
    section: Exclude<SectionName, "basicInfo">;
    key: ResumeArrayKeys;
    title: string;
    existingId: string;
    existingLabel: string;
    apiPath: string;
    newEntry: Record<string, unknown>;
}[] = [
    {
        section: "career",
        key: "careers",
        title: "職歴一覧",
        existingId: "career-1",
        existingLabel: "Company A",
        apiPath: "careers",
        newEntry: { companyName: "新しい職歴", startDate: "", endDate: null, active: false },
    },
    {
        section: "project",
        key: "projects",
        title: "プロジェクト一覧",
        existingId: "project-1",
        existingLabel: "Project A",
        apiPath: "projects",
        newEntry: {
            companyName: "",
            startDate: "",
            endDate: null,
            active: false,
            name: "新しいプロジェクト",
            overview: "",
            teamComp: "",
            role: "",
            achievement: "",
            process: {
                requirements: false,
                basicDesign: false,
                detailedDesign: false,
                implementation: false,
                integrationTest: false,
                systemTest: false,
                maintenance: false,
            },
            techStack: emptyTechStack,
        },
    },
    {
        section: "certification",
        key: "certifications",
        title: "保有資格一覧",
        existingId: "certification-1",
        existingLabel: "基本情報技術者",
        apiPath: "certifications",
        newEntry: { name: "新しい資格", date: "" },
    },
    {
        section: "portfolio",
        key: "portfolios",
        title: "ポートフォリオ一覧",
        existingId: "portfolio-1",
        existingLabel: "Portfolio A",
        apiPath: "portfolios",
        newEntry: { name: "新しいポートフォリオ", overview: "", techStack: "", link: "" },
    },
    {
        section: "snsPlatform",
        key: "snsPlatforms",
        title: "SNS一覧",
        existingId: "sns-1",
        existingLabel: "GitHub",
        apiPath: "sns-platforms",
        newEntry: { name: "新しいSNSプラットフォーム", link: "" },
    },
    {
        section: "selfPromotion",
        key: "selfPromotions",
        title: "自己PR一覧",
        existingId: "self-1",
        existingLabel: "強み",
        apiPath: "self-promotions",
        newEntry: { title: "新しい自己PR", content: "" },
    },
];

/** 編集画面のURL(職務経歴書のIDを含む)で一覧を描画する */
const renderList = ({ section = "career" as SectionName, resume = fullResume() } = {}) => {
    const store = useResumeStore.getState();
    store.setResume(resume);
    store.setActiveSection(section);
    return renderWithProviders(
        <Routes>
            <Route path="/resume/:id" element={<EntryList />} />
        </Routes>,
        { route: "/resume/resume-1" },
    );
};

const listOf = (key: ResumeArrayKeys) => (useResumeStore.getState().resume?.[key] ?? []) as { id: string }[];

describe("EntryList", () => {
    let scrollTo: ReturnType<typeof vi.spyOn>;

    beforeEach(() => {
        resetStoresAndMocks([() => vi.mocked(protectedApiClient.delete).mockReset()]);
        vi.mocked(protectedApiClient.delete).mockResolvedValue(createAxiosResponse(undefined));
        scrollTo = vi.spyOn(Element.prototype, "scrollTo").mockImplementation(() => {});
    });

    it.each(sectionCases)(
        "$section では、見出しを「$title」にし、項目を並べること",
        ({ section, title, existingLabel }) => {
            renderList({ section });

            expect(screen.getByRole("heading", { name: title })).toBeInTheDocument();
            expect(screen.getByRole("button", { name: `${existingLabel}を削除` })).toBeInTheDocument();
        },
    );

    it("項目が無いときは、データが無いことを表示すること", () => {
        renderList({ section: "certification", resume: cloneResume() });

        expect(screen.getByText("表示するデータがありません。")).toBeInTheDocument();
        expect(screen.queryByRole("list")).not.toBeInTheDocument();
    });

    it.each(sectionCases)(
        "$section で新規追加を押すと、一時IDを付けた初期値の項目を先頭に足して選択すること",
        async ({ section, key, existingId, newEntry }) => {
            vi.spyOn(crypto, "randomUUID").mockReturnValue("0000-1111-2222-3333-444455556666");
            const { user } = renderList({ section });

            await user.click(screen.getByRole("button", { name: "新規追加" }));

            const list = listOf(key);
            expect(list).toHaveLength(2);
            expect(list[0]).toEqual({ id: "temp_0000-1111-2222-3333-444455556666", ...newEntry });
            expect(list[1].id).toBe(existingId);
            expect(useResumeStore.getState().activeEntryId).toBe("temp_0000-1111-2222-3333-444455556666");
        },
    );

    it("乱数のIDを作れない環境でも、一時IDの接頭辞を付けて追加すること", async () => {
        vi.stubGlobal("crypto", {});
        try {
            const { user } = renderList({ section: "career" });

            await user.click(screen.getByRole("button", { name: "新規追加" }));

            expect(listOf("careers")[0].id).toMatch(/^temp_\d+-[0-9a-f]+$/);
        } finally {
            vi.unstubAllGlobals();
        }
    });

    it("新規追加したら、一覧を先頭までスクロールすること", async () => {
        const { user } = renderList({ section: "career" });

        await user.click(screen.getByRole("button", { name: "新規追加" }));

        expect(scrollTo).toHaveBeenCalledWith({ top: 0, behavior: "smooth" });
    });

    it("プロジェクトを複製したら、一覧を先頭までスクロールすること", async () => {
        const { user } = renderList({ section: "project" });

        await user.click(screen.getByRole("button", { name: "Project Aを複製" }));

        expect(listOf("projects")).toHaveLength(2);
        expect(scrollTo).toHaveBeenCalledWith({ top: 0, behavior: "smooth" });
    });

    it("基本情報のセクションでは、新規追加を押しても何も足さないこと", async () => {
        const { user } = renderList({ section: "basicInfo" });
        const before = useResumeStore.getState().resume;

        await user.click(screen.getByRole("button", { name: "新規追加" }));

        expect(useResumeStore.getState().resume).toBe(before);
        expect(useResumeStore.getState().activeEntryId).toBeNull();
    });

    it("保存前の項目を削除すると、APIを呼ばずにストアからだけ消し、選択を外すこと", async () => {
        const { user } = renderList({ section: "career" });
        await user.click(screen.getByRole("button", { name: "新規追加" }));
        expect(listOf("careers")).toHaveLength(2);

        await user.click(screen.getByRole("button", { name: "新しい職歴を削除" }));

        expect(listOf("careers").map((entry) => entry.id)).toEqual(["career-1"]);
        expect(useResumeStore.getState().activeEntryId).toBeNull();
        expect(protectedApiClient.delete).not.toHaveBeenCalled();
    });

    it("選択していない保存前の項目を削除しても、選択は外さないこと", async () => {
        const { user } = renderList({ section: "career" });
        await user.click(screen.getByRole("button", { name: "新規追加" }));
        useResumeStore.getState().setActiveEntryId("career-1");

        await user.click(screen.getByRole("button", { name: "新しい職歴を削除" }));

        expect(useResumeStore.getState().activeEntryId).toBe("career-1");
    });

    it.each(sectionCases)(
        "$section の既存の項目は、確認で「はい」を選ぶと削除のAPIを呼ぶこと",
        async ({ section, key, existingId, existingLabel, apiPath }) => {
            const { user } = renderList({ section });
            useResumeStore.getState().setActiveEntryId(existingId);

            await user.click(screen.getByRole("button", { name: `${existingLabel}を削除` }));
            await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "はい" }));

            expect(useResumeStore.getState().activeEntryId).toBeNull();
            await waitFor(() =>
                expect(protectedApiClient.delete).toHaveBeenCalledWith(`/resumes/resume-1/${apiPath}/${existingId}`),
            );
            expect(protectedApiClient.delete).toHaveBeenCalledTimes(1);
            await waitFor(() => expect(listOf(key)).toHaveLength(0));
        },
    );

    it("選択していない既存の項目を削除しても、選択は外さないこと", async () => {
        const resume = cloneResume({
            careers: [
                ...cloneResume().careers,
                { id: "career-2", companyName: "Company B", startDate: "2015-04", endDate: "2019-12", active: false },
            ],
        });
        // 削除の完了後はフックが選択を外すため、応答を返さないままにして一覧側の扱いだけを見る
        vi.mocked(protectedApiClient.delete).mockReturnValue(new Promise(() => {}));
        const { user } = renderList({ section: "career", resume });
        useResumeStore.getState().setActiveEntryId("career-2");

        await user.click(screen.getByRole("button", { name: "Company Aを削除" }));
        await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "はい" }));

        await waitFor(() =>
            expect(protectedApiClient.delete).toHaveBeenCalledWith("/resumes/resume-1/careers/career-1"),
        );
        expect(useResumeStore.getState().activeEntryId).toBe("career-2");
    });

    it("既存の項目は、確認で「いいえ」を選ぶと削除しないこと", async () => {
        const { user } = renderList({ section: "career" });
        useResumeStore.getState().setActiveEntryId("career-1");

        await user.click(screen.getByRole("button", { name: "Company Aを削除" }));
        await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "いいえ" }));

        expect(protectedApiClient.delete).not.toHaveBeenCalled();
        expect(listOf("careers")).toHaveLength(1);
        expect(useResumeStore.getState().activeEntryId).toBe("career-1");
    });
});
