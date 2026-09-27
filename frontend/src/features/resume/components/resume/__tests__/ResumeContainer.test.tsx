import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: {
        get: vi.fn(),
        post: vi.fn(),
        put: vi.fn(),
        delete: vi.fn(),
    },
}));

import { lightTheme } from "@/config/theme";
import type { Resume, SectionName } from "@/features/resume";
import { RESUME_NOT_FOUND_MESSAGE, ResumeContainer, useResumeStore } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { createAxiosResponse, createTestQueryClient, resetStoresAndMocks } from "@/test";
import { ThemeProvider } from "@mui/material";
import { LocalizationProvider } from "@mui/x-date-pickers";
import { AdapterDayjs } from "@mui/x-date-pickers/AdapterDayjs";
import { QueryClientProvider } from "@tanstack/react-query";
import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { AxiosError } from "axios";
import { createMemoryRouter } from "react-router";
import { RouterProvider } from "react-router/dom";

import { cloneResume, emptyTechStack } from "../../__tests__/resumeTestData";

/** 一覧型セクションの、職務経歴書上のキー(ストアの型は公開されていないため、updateSection の引数から取る) */
type ResumeArrayKeys = Parameters<ReturnType<typeof useResumeStore.getState>["updateSection"]>[0];

/** 各セクションに既存のエントリーを1件ずつ持つ職務経歴書 */
const fullResume = (): Resume =>
    cloneResume({
        certifications: [{ id: "certification-1", name: "基本情報技術者", date: "2020-04-01" }],
        portfolios: [
            { id: "portfolio-1", name: "Portfolio A", overview: "概要", techStack: null, link: "https://a.example" },
        ],
        snsPlatforms: [{ id: "sns-1", name: "GitHub", link: "https://github.com/example" }],
        selfPromotions: [{ id: "self-1", title: "強み", content: "内容" }],
    });

const sectionCases: { section: Exclude<SectionName, "basicInfo">; key: ResumeArrayKeys; label: string; id: string }[] =
    [
        { section: "career", key: "careers", label: "職歴", id: "career-1" },
        { section: "project", key: "projects", label: "プロジェクト", id: "project-1" },
        { section: "certification", key: "certifications", label: "保有資格", id: "certification-1" },
        { section: "portfolio", key: "portfolios", label: "ポートフォリオ", id: "portfolio-1" },
        { section: "snsPlatform", key: "snsPlatforms", label: "SNS", id: "sns-1" },
        { section: "selfPromotion", key: "selfPromotions", label: "自己PR", id: "self-1" },
    ];

const resumeNotFoundError = () =>
    new AxiosError("Not Found", "ERR_BAD_REQUEST", undefined, undefined, {
        ...createAxiosResponse({ message: RESUME_NOT_FOUND_MESSAGE, errors: {} }),
        status: 404,
    });

const serverError = () =>
    new AxiosError("Server Error", "ERR_BAD_RESPONSE", undefined, undefined, {
        ...createAxiosResponse({ message: "サーバーエラー", errors: {} }),
        status: 500,
    });

/** 後から失敗させられるリクエスト */
const deferredFailure = () => {
    let fail!: () => void;
    const promise = new Promise<never>((_, reject) => {
        fail = () => reject(resumeNotFoundError());
    });
    return { promise, fail };
};

const renderContainer = () => {
    const queryClient = createTestQueryClient();
    const router = createMemoryRouter([{ path: "/resume/:id", element: <ResumeContainer /> }], {
        initialEntries: ["/resume/resume-1"],
    });
    return render(
        <QueryClientProvider client={queryClient}>
            <ThemeProvider theme={lightTheme}>
                <LocalizationProvider dateAdapter={AdapterDayjs}>
                    <RouterProvider router={router} />
                </LocalizationProvider>
            </ThemeProvider>
        </QueryClientProvider>,
    );
};

/** 描画して、職務経歴書の読み込みが終わるまで待つ */
const renderLoaded = async () => {
    const utils = renderContainer();
    await screen.findByRole("tab", { name: "基本" });
    return utils;
};

const store = () => useResumeStore.getState();

/** 指定したセクションを開き、エントリーを選ぶ(dirty を付けると編集済みにする) */
const selectEntry = (section: SectionName, entryId: string | null, { dirty = false } = {}) => {
    act(() => {
        store().setActiveSection(section);
        store().setActiveEntryId(entryId);
        if (dirty && entryId) {
            store().addDirtyEntryId(entryId);
        }
    });
};

/** 保存前の新規エントリー(一時ID)を先頭に足して選ぶ */
const addTempEntry = (section: SectionName, key: ResumeArrayKeys, tempId: string) => {
    act(() => {
        const list = store().resume?.[key] ?? [];
        store().updateSection(key, [{ ...list[0], id: tempId }, ...list] as Resume[ResumeArrayKeys]);
    });
    selectEntry(section, tempId, { dirty: true });
};

const notFoundShown = () => screen.findByText(/404/);

describe("ResumeContainer", () => {
    beforeEach(() => {
        resetStoresAndMocks([
            () => vi.mocked(protectedApiClient.get).mockReset(),
            () => vi.mocked(protectedApiClient.post).mockReset(),
            () => vi.mocked(protectedApiClient.put).mockReset(),
            () => vi.mocked(protectedApiClient.delete).mockReset(),
        ]);
        vi.mocked(protectedApiClient.get).mockImplementation((url: string) => {
            if (url === "/resumes/resume-1") return Promise.resolve(createAxiosResponse(fullResume()));
            if (url === "/tech-stacks") return Promise.resolve(createAxiosResponse(emptyTechStack));
            if (url === "/certifications") return Promise.resolve(createAxiosResponse({ names: [] }));
            if (url === "/sns-platforms") return Promise.resolve(createAxiosResponse({ names: [] }));
            return Promise.resolve(createAxiosResponse(undefined));
        });
    });

    describe("読み込み", () => {
        it("読み込み中は、ローディングだけを表示すること", () => {
            vi.mocked(protectedApiClient.get).mockReturnValue(new Promise(() => {}));

            renderContainer();

            expect(screen.getByRole("progressbar")).toBeInTheDocument();
            expect(screen.queryByRole("tab", { name: "基本" })).not.toBeInTheDocument();
        });

        it("職務経歴書が見つからないときは、見つからない画面を表示すること", async () => {
            vi.mocked(protectedApiClient.get).mockRejectedValue(resumeNotFoundError());

            renderContainer();

            expect(await notFoundShown()).toBeInTheDocument();
            expect(screen.queryByRole("progressbar")).not.toBeInTheDocument();
        });

        it("それ以外の理由で読み込めなかったときは、見つからない画面にせず、ローディングのままにすること", async () => {
            vi.mocked(protectedApiClient.get).mockRejectedValue(serverError());

            renderContainer();

            await waitFor(() => expect(protectedApiClient.get).toHaveBeenCalledWith("/resumes/resume-1"));
            await act(() => new Promise((resolve) => setTimeout(resolve, 50)));
            expect(screen.getByRole("progressbar")).toBeInTheDocument();
            expect(screen.queryByText(/404/)).not.toBeInTheDocument();
            expect(screen.queryByRole("tab", { name: "基本" })).not.toBeInTheDocument();
        });
    });

    describe("職務経歴書が見つからないエラー", () => {
        it("基本情報の保存で見つからなかったときは、見つからない画面に切り替えること", async () => {
            const request = deferredFailure();
            vi.mocked(protectedApiClient.put).mockReturnValue(request.promise);
            await renderLoaded();
            act(() => store().setDirty(true));

            const saveButton = screen.getByRole("button", { name: "基本情報を保存" });
            fireEvent.click(saveButton);
            // 保存している間は、保存ボタンを押せない
            await waitFor(() => expect(saveButton).toBeDisabled());

            request.fail();
            expect(await notFoundShown()).toBeInTheDocument();
        });

        it.each(sectionCases)(
            "$label の新規作成で見つからなかったときは、見つからない画面に切り替えること",
            async ({ section, key, label }) => {
                const request = deferredFailure();
                vi.mocked(protectedApiClient.post).mockReturnValue(request.promise);
                await renderLoaded();
                addTempEntry(section, key, "temp_new");

                const saveButton = screen.getByRole("button", { name: `${label}情報を保存` });
                expect(saveButton).toBeEnabled();
                fireEvent.click(saveButton);
                await waitFor(() => expect(saveButton).toBeDisabled());
                expect(protectedApiClient.post).toHaveBeenCalledOnce();

                request.fail();
                expect(await notFoundShown()).toBeInTheDocument();
            },
        );

        it.each(sectionCases)(
            "$label の更新で見つからなかったときは、見つからない画面に切り替えること",
            async ({ section, label, id }) => {
                const request = deferredFailure();
                vi.mocked(protectedApiClient.put).mockReturnValue(request.promise);
                await renderLoaded();
                selectEntry(section, id, { dirty: true });

                const saveButton = screen.getByRole("button", { name: `${label}情報を保存` });
                fireEvent.click(saveButton);
                await waitFor(() => expect(saveButton).toBeDisabled());
                expect(protectedApiClient.put).toHaveBeenCalledOnce();
                expect(protectedApiClient.post).not.toHaveBeenCalled();

                request.fail();
                expect(await notFoundShown()).toBeInTheDocument();
            },
        );

        it.each(sectionCases)(
            "$label の削除で見つからなかったときは、見つからない画面に切り替えること",
            async ({ section, label, id }) => {
                const request = deferredFailure();
                vi.mocked(protectedApiClient.delete).mockReturnValue(request.promise);
                await renderLoaded();
                selectEntry(section, id);

                fireEvent.click(screen.getByRole("button", { name: `${label}情報を削除` }));
                fireEvent.click(
                    within(screen.getByRole("dialog", { name: "削除確認" })).getByRole("button", { name: "はい" }),
                );
                await waitFor(() => expect(protectedApiClient.delete).toHaveBeenCalledOnce());

                request.fail();
                expect(await notFoundShown()).toBeInTheDocument();
            },
        );

        it("一覧からの削除で見つからなかったときも、見つからない画面に切り替えること", async () => {
            vi.mocked(protectedApiClient.delete).mockRejectedValue(resumeNotFoundError());
            await renderLoaded();
            selectEntry("project", null);

            fireEvent.click(screen.getByRole("button", { name: "Project Aを削除" }));
            const dialog = screen.queryByRole("dialog", { name: "削除確認" });
            if (dialog) {
                fireEvent.click(within(dialog).getByRole("button", { name: "はい" }));
            }

            expect(await notFoundShown()).toBeInTheDocument();
        });
    });

    describe("削除", () => {
        it("確認ダイアログで「はい」を選んだときだけ、削除のAPIを呼ぶこと", async () => {
            vi.mocked(protectedApiClient.delete).mockResolvedValue(createAxiosResponse(undefined));
            await renderLoaded();
            selectEntry("project", "project-1");

            fireEvent.click(screen.getByRole("button", { name: "プロジェクト情報を削除" }));
            fireEvent.click(
                within(screen.getByRole("dialog", { name: "削除確認" })).getByRole("button", { name: "はい" }),
            );

            await waitFor(() =>
                expect(protectedApiClient.delete).toHaveBeenCalledWith("/resumes/resume-1/projects/project-1"),
            );
            await waitFor(() => expect(screen.queryByRole("dialog", { name: "削除確認" })).not.toBeInTheDocument());
        });

        it("確認ダイアログで「いいえ」を選んだときは、削除せずにダイアログを閉じること", async () => {
            await renderLoaded();
            selectEntry("project", "project-1");

            fireEvent.click(screen.getByRole("button", { name: "プロジェクト情報を削除" }));
            fireEvent.click(
                within(screen.getByRole("dialog", { name: "削除確認" })).getByRole("button", { name: "いいえ" }),
            );

            await waitFor(() => expect(screen.queryByRole("dialog", { name: "削除確認" })).not.toBeInTheDocument());
            expect(protectedApiClient.delete).not.toHaveBeenCalled();
            expect(store().resume?.projects.map((p) => p.id)).toEqual(["project-1"]);
            expect(store().activeEntryId).toBe("project-1");
        });

        it("保存前のエントリーは、確認せずにストアからだけ削除し、選択を外すこと", async () => {
            await renderLoaded();
            addTempEntry("project", "projects", "temp_new");

            fireEvent.click(screen.getByRole("button", { name: "プロジェクト情報を削除" }));

            expect(screen.queryByRole("dialog", { name: "削除確認" })).not.toBeInTheDocument();
            expect(store().resume?.projects.map((p) => p.id)).toEqual(["project-1"]);
            expect(store().activeEntryId).toBeNull();
            expect(protectedApiClient.delete).not.toHaveBeenCalled();
        });
    });

    describe("基本情報の保存", () => {
        it("入力どおりの値を送り、日付は年月日の形にそろえること", async () => {
            vi.mocked(protectedApiClient.put).mockResolvedValue(createAxiosResponse(fullResume()));
            await renderLoaded();
            act(() => store().updateResume({ resumeName: "新しい名前", date: "2024-05-06T00:00:00" }));

            fireEvent.click(screen.getByRole("button", { name: "基本情報を保存" }));

            await waitFor(() =>
                expect(protectedApiClient.put).toHaveBeenCalledWith("/resumes/resume-1/basic", {
                    resumeName: "新しい名前",
                    date: "2024-05-06",
                    lastName: "Yamada",
                    firstName: "Taro",
                }),
            );
        });

        it("姓名が未入力で日付が不正なときは、それぞれ空文字で送ること", async () => {
            vi.mocked(protectedApiClient.put).mockResolvedValue(createAxiosResponse(fullResume()));
            await renderLoaded();
            act(() =>
                store().updateResume({
                    date: "invalid-date",
                    lastName: null as unknown as string,
                    firstName: null as unknown as string,
                }),
            );

            fireEvent.click(screen.getByRole("button", { name: "基本情報を保存" }));

            await waitFor(() =>
                expect(protectedApiClient.put).toHaveBeenCalledWith("/resumes/resume-1/basic", {
                    resumeName: "Alpha Resume",
                    date: "",
                    lastName: "",
                    firstName: "",
                }),
            );
        });
    });

    describe("保存・削除ボタン", () => {
        it("基本情報では保存ボタンだけを表示し、編集するまで押せないこと", async () => {
            await renderLoaded();

            const saveButton = screen.getByRole("button", { name: "基本情報を保存" });
            expect(saveButton).toBeDisabled();
            expect(screen.queryByRole("button", { name: "基本情報を削除" })).not.toBeInTheDocument();

            act(() => store().setDirty(true));
            expect(saveButton).toBeEnabled();
        });

        it("一覧型のセクションでエントリーを選んでいないときは、保存・削除ボタンを表示しないこと", async () => {
            await renderLoaded();
            selectEntry("project", null);

            expect(screen.queryByRole("button", { name: "プロジェクト情報を保存" })).not.toBeInTheDocument();
            expect(screen.queryByRole("button", { name: "プロジェクト情報を削除" })).not.toBeInTheDocument();
        });

        it("一覧型のセクションでは、選んでいるエントリーが編集済みのときだけ保存ボタンを押せること", async () => {
            await renderLoaded();
            selectEntry("career", "career-1");

            const saveButton = screen.getByRole("button", { name: "職歴情報を保存" });
            expect(screen.getByRole("button", { name: "職歴情報を削除" })).toBeInTheDocument();
            expect(saveButton).toBeDisabled();

            // 基本情報の編集や、別のエントリーの編集では押せるようにならない
            act(() => {
                store().setDirty(true);
                store().addDirtyEntryId("project-1");
            });
            expect(saveButton).toBeDisabled();

            act(() => store().addDirtyEntryId("career-1"));
            expect(saveButton).toBeEnabled();
        });
    });
});
