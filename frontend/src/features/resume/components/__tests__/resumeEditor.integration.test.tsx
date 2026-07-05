import { ThemeProvider } from "@mui/material";
import { LocalizationProvider } from "@mui/x-date-pickers";
import { AdapterDayjs } from "@mui/x-date-pickers/AdapterDayjs";
import { QueryClientProvider } from "@tanstack/react-query";
import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { AxiosResponse } from "axios";
import { saveAs } from "file-saver";
import { createMemoryRouter } from "react-router";
import { RouterProvider } from "react-router/dom";
import { vi } from "vitest";

const debounceMocks = vi.hoisted(() => ({
    cancel: vi.fn(),
}));

vi.mock("use-debounce", () => ({
    useDebouncedCallback: (callback: (...args: unknown[]) => void) =>
        Object.assign(
            vi.fn((...args: unknown[]) => callback(...args)),
            { cancel: debounceMocks.cancel },
        ),
}));

vi.mock("@/lib", () => ({
    protectedApiClient: {
        get: vi.fn(),
        post: vi.fn(),
        put: vi.fn(),
        delete: vi.fn(),
    },
}));

vi.mock("file-saver", () => ({
    saveAs: vi.fn(),
}));

import { ErrorBanner } from "@/components/errors";
import { ProtectedLayout } from "@/components/layouts";
import { lightTheme } from "@/config/theme";
import type { Resume } from "@/features/resume";
import { ResumeContainer, useGetResumeList, useResumeStore } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { createAxiosResponse, createTestQueryClient, resetStoresAndMocks } from "@/test";

import { cloneResume, emptyTechStack, resumeSummaries } from "./resumeTestData";

const renderEditor = () => {
    const queryClient = createTestQueryClient();
    const user = userEvent.setup();
    const router = createMemoryRouter(
        [
            { path: "/resume/:id", element: <ResumeContainer /> },
            { path: "/resume/list", element: <div>resume list destination</div> },
        ],
        { initialEntries: ["/resume/resume-1"] },
    );

    const utils = render(
        <QueryClientProvider client={queryClient}>
            <ThemeProvider theme={lightTheme}>
                <LocalizationProvider dateAdapter={AdapterDayjs}>
                    <RouterProvider router={router} />
                </LocalizationProvider>
            </ThemeProvider>
        </QueryClientProvider>,
    );

    return { user, queryClient, router, ...utils };
};

const ResumeListDestination = () => {
    useGetResumeList();
    return <div>resume list destination</div>;
};

const renderEditorWithProtectedLayout = () => {
    const queryClient = createTestQueryClient();
    const user = userEvent.setup();
    const router = createMemoryRouter(
        [
            {
                element: <ProtectedLayout />,
                children: [
                    { path: "/resume/:id", element: <ResumeContainer /> },
                    { path: "/resume/list", element: <ResumeListDestination /> },
                ],
            },
        ],
        { initialEntries: ["/resume/resume-1"] },
    );

    const utils = render(
        <QueryClientProvider client={queryClient}>
            <ThemeProvider theme={lightTheme}>
                <LocalizationProvider dateAdapter={AdapterDayjs}>
                    <ErrorBanner />
                    <RouterProvider router={router} />
                </LocalizationProvider>
            </ThemeProvider>
        </QueryClientProvider>,
    );

    return { user, queryClient, router, ...utils };
};

describe("resume editor", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
        debounceMocks.cancel.mockClear();
        vi.mocked(saveAs).mockReset();
        URL.createObjectURL = vi.fn(() => "data:application/pdf;base64,JVBERi0=");
        URL.revokeObjectURL = vi.fn();
        vi.mocked(protectedApiClient.get).mockReset();
        vi.mocked(protectedApiClient.post).mockReset();
        vi.mocked(protectedApiClient.put).mockReset();
        vi.mocked(protectedApiClient.delete).mockReset();

        vi.mocked(protectedApiClient.get).mockImplementation((url: string) => {
            if (url === "/resumes/resume-1") {
                return Promise.resolve(createAxiosResponse(cloneResume()));
            }
            if (url === "/resumes") {
                return Promise.resolve(createAxiosResponse({ resumes: resumeSummaries }));
            }
            if (url === "/tech-stacks") {
                return Promise.resolve(createAxiosResponse(emptyTechStack));
            }
            if (url === "/resumes/resume-1/export") {
                return Promise.resolve(
                    createAxiosResponse(new Blob(["exported"]), {
                        headers: {},
                    }),
                );
            }
            return Promise.resolve(createAxiosResponse(undefined));
        });
        vi.mocked(protectedApiClient.post).mockImplementation((url: string) => {
            if (url === "/resumes/resume-1/export") {
                return Promise.resolve(
                    createAxiosResponse(new Blob(["pdf"], { type: "application/pdf" }), {
                        headers: { "content-disposition": 'attachment; filename="resume.pdf"' },
                    }),
                );
            }
            return Promise.resolve(createAxiosResponse(cloneResume()));
        });
        vi.mocked(protectedApiClient.put).mockImplementation((url: string, payload: unknown) => {
            if (url === "/resumes/resume-1/basic") {
                return Promise.resolve(createAxiosResponse(cloneResume(payload as Partial<Resume>)));
            }
            return Promise.resolve(createAxiosResponse(cloneResume()));
        });
        vi.mocked(protectedApiClient.delete).mockResolvedValue(createAxiosResponse(undefined));
    });

    it("section tab切り替えで表示セクションとstoreを更新すること", async () => {
        const { user } = renderEditor();

        await screen.findByRole("tab", { name: "基本" });
        await user.click(screen.getByRole("tab", { name: "プロジェクト" }));

        expect(await screen.findByText("プロジェクト情報")).toBeInTheDocument();
        expect(screen.getByText("Project A")).toBeInTheDocument();
        expect(useResumeStore.getState().activeSection).toBe("project");
    });

    it("project entryを複製しコピーをactive entryにすること", async () => {
        const { user } = renderEditor();

        await user.click(await screen.findByRole("tab", { name: "プロジェクト" }));
        await user.click(screen.getByRole("button", { name: "Project Aを複製" }));

        expect(await screen.findByText("Project A（コピー）")).toBeInTheDocument();
        const state = useResumeStore.getState();
        expect(state.resume?.projects).toHaveLength(2);
        expect(state.resume?.projects[0].name).toBe("Project A（コピー）");
        expect(state.activeEntryId).toBe(state.resume?.projects[0].id);
    }, 10000);

    it("entry deleteは一時IDを確認なしで消し既存IDはconfirm後に削除APIへ接続すること", async () => {
        const { user } = renderEditor();

        await user.click(await screen.findByRole("tab", { name: "プロジェクト" }));
        await user.click(screen.getByRole("button", { name: "新規追加" }));
        expect(await screen.findByText("新しいプロジェクト")).toBeInTheDocument();

        fireEvent.click(screen.getByRole("button", { name: "新しいプロジェクトを削除" }));
        expect(screen.queryByText("新しいプロジェクト")).not.toBeInTheDocument();
        expect(screen.queryByRole("dialog", { name: "削除確認" })).not.toBeInTheDocument();

        await user.click(screen.getByText("Project A"));
        fireEvent.click(screen.getByRole("button", { name: "プロジェクト情報を削除" }));
        fireEvent.click(within(screen.getByRole("dialog", { name: "削除確認" })).getByRole("button", { name: "はい" }));

        await waitFor(() =>
            expect(protectedApiClient.delete).toHaveBeenCalledWith("/resumes/resume-1/projects/project-1"),
        );
    }, 10000);

    it("保存buttonはdirty状態に連動し保存時に基本情報APIへ接続すること", async () => {
        const { user } = renderEditor();

        await screen.findByRole("textbox", { name: /職務経歴書名/ });
        const saveButton = screen.getByRole("button", { name: "基本情報を保存" });
        expect(saveButton).toBeDisabled();

        const resumeName = screen.getByRole("textbox", { name: /職務経歴書名/ });
        await user.clear(resumeName);
        await user.type(resumeName, "Updated Resume");

        expect(saveButton).toBeEnabled();
        await user.click(saveButton);

        await waitFor(() =>
            expect(protectedApiClient.put).toHaveBeenCalledWith(
                "/resumes/resume-1/basic",
                expect.objectContaining({ resumeName: "Updated Resume" }),
            ),
        );
    });

    it("auto-save有効時は入力変更を基本情報APIへ反映すること", async () => {
        const { user } = renderEditor();

        await screen.findByRole("textbox", { name: /姓/ });
        await user.click(screen.getByRole("switch", { name: "自動保存" }));
        await user.clear(screen.getByRole("textbox", { name: /姓/ }));
        await user.type(screen.getByRole("textbox", { name: /姓/ }), "Suzuki");

        await waitFor(() =>
            expect(protectedApiClient.put).toHaveBeenCalledWith(
                "/resumes/resume-1/basic",
                expect.objectContaining({ lastName: "Suzuki" }),
            ),
        );
    });

    it("export menuはPDFプレビューを開き、Markdownは直接ダウンロードすること", async () => {
        const { user } = renderEditor();

        await screen.findByRole("button", { name: "エクスポート" });
        await user.click(screen.getByRole("button", { name: "エクスポート" }));
        await user.click(screen.getByRole("menuitem", { name: /PDFでエクスポート/ }));

        await waitFor(() =>
            expect(protectedApiClient.post).toHaveBeenCalledWith(
                "/resumes/resume-1/export",
                expect.objectContaining({
                    format: "pdf",
                    disposition: "inline",
                }),
                expect.objectContaining({
                    headers: { Accept: "application/pdf, application/json" },
                }),
            ),
        );
        expect(await screen.findByRole("dialog", { name: "PDFプレビュー" })).toBeInTheDocument();
        expect(screen.getByTitle("PDFプレビュー")).toHaveAttribute("src", expect.stringContaining("navpanes=0"));
        expect(screen.getByTitle("PDFプレビュー")).toHaveAttribute("src", expect.stringContaining("zoom=100"));
        expect(saveAs).not.toHaveBeenCalled();

        await user.click(
            within(screen.getByRole("dialog", { name: "PDFプレビュー" })).getByRole("button", { name: "エクスポート" }),
        );
        await waitFor(() =>
            expect(protectedApiClient.post).toHaveBeenCalledWith(
                "/resumes/resume-1/export",
                expect.objectContaining({
                    format: "pdf",
                    disposition: "attachment",
                }),
                expect.objectContaining({
                    headers: { Accept: "application/pdf, application/json" },
                }),
            ),
        );
        await waitFor(() => expect(saveAs).toHaveBeenCalled());
        const pdfBlob = vi.mocked(saveAs).mock.calls[vi.mocked(saveAs).mock.calls.length - 1]?.[0] as Blob;
        expect(pdfBlob.type).toBe("application/pdf");
        expect(screen.getByRole("dialog", { name: "PDFプレビュー" })).toBeInTheDocument();
        await user.click(
            within(screen.getByRole("dialog", { name: "PDFプレビュー" })).getByRole("button", { name: "とじる" }),
        );
        await waitFor(() => expect(screen.queryByRole("dialog", { name: "PDFプレビュー" })).not.toBeInTheDocument());

        await user.click(screen.getByRole("button", { name: "エクスポート" }));
        await user.click(await screen.findByRole("menuitem", { name: /Markdownでエクスポート/ }));

        await waitFor(() =>
            expect(protectedApiClient.get).toHaveBeenCalledWith(
                "/resumes/resume-1/export",
                expect.objectContaining({
                    headers: { Accept: "text/markdown, application/json" },
                    responseType: "blob",
                }),
            ),
        );
        await waitFor(() => expect(saveAs).toHaveBeenCalledTimes(2));
        const markdownBlob = vi.mocked(saveAs).mock.calls[vi.mocked(saveAs).mock.calls.length - 1]?.[0] as Blob;
        expect(markdownBlob.type).toBe("text/markdown");
    });

    it("PDFプレビューは初回PDFの取得完了後にだけモーダルを表示すること", async () => {
        let resolvePreviewRequest!: (response: AxiosResponse<Blob>) => void;
        vi.mocked(protectedApiClient.post).mockImplementationOnce(
            () =>
                new Promise((resolve) => {
                    resolvePreviewRequest = resolve;
                }),
        );

        const { user } = renderEditor();

        await screen.findByRole("button", { name: "エクスポート" });
        await user.click(screen.getByRole("button", { name: "エクスポート" }));
        await user.click(screen.getByRole("menuitem", { name: /PDFでエクスポート/ }));

        expect(screen.queryByRole("dialog", { name: "PDFプレビュー" })).not.toBeInTheDocument();

        act(() => {
            resolvePreviewRequest(
                createAxiosResponse(new Blob(["pdf"], { type: "application/pdf" }), {
                    headers: {},
                }),
            );
        });

        expect(await screen.findByRole("dialog", { name: "PDFプレビュー" })).toBeInTheDocument();
    });

    it("PDFプレビューで表ヘッダー色を変更後に設定値リセットしてもモーダルを維持すること", async () => {
        const { user } = renderEditor();

        await screen.findByRole("button", { name: "エクスポート" });
        await user.click(screen.getByRole("button", { name: "エクスポート" }));
        await user.click(screen.getByRole("menuitem", { name: /PDFでエクスポート/ }));

        const dialog = await screen.findByRole("dialog", { name: "PDFプレビュー" });
        const colorCodeInput = within(dialog).getByLabelText("カラーコード");
        await user.clear(colorCodeInput);
        await user.type(colorCodeInput, "ff0000");
        await user.click(within(dialog).getByRole("button", { name: "設定値リセット" }));

        await waitFor(() => expect(colorCodeInput).toHaveValue("d9d9d9"));
        expect(screen.getByRole("dialog", { name: "PDFプレビュー" })).toBeInTheDocument();
    });

    it("詳細画面でMarkdownエクスポート対象が存在しない場合は一覧画面へ遷移すること", async () => {
        const { user } = renderEditorWithProtectedLayout();

        await screen.findByRole("button", { name: "エクスポート" });
        vi.mocked(protectedApiClient.get).mockRejectedValueOnce({
            isAxiosError: true,
            response: {
                status: 404,
                data: { message: "対象の職務経歴書データが存在しません。", errors: {} },
            },
        });

        await user.click(screen.getByRole("button", { name: "エクスポート" }));
        await user.click(await screen.findByRole("menuitem", { name: /Markdownでエクスポート/ }));

        expect(await screen.findByText("resume list destination")).toBeInTheDocument();
        expect(await screen.findByText("対象の職務経歴書データが存在しません。")).toBeInTheDocument();
    });

    it("詳細画面でPDFプレビュー対象が存在しない場合は一覧画面へ遷移すること", async () => {
        let rejectPreviewRequest!: (error: unknown) => void;
        const { user } = renderEditorWithProtectedLayout();

        await screen.findByRole("button", { name: "エクスポート" });
        vi.mocked(protectedApiClient.post).mockImplementationOnce(
            () =>
                new Promise((_, reject) => {
                    rejectPreviewRequest = reject;
                }),
        );

        await user.click(screen.getByRole("button", { name: "エクスポート" }));
        await user.click(await screen.findByRole("menuitem", { name: /PDFでエクスポート/ }));

        expect(screen.queryByRole("dialog", { name: "PDFプレビュー" })).not.toBeInTheDocument();

        act(() => {
            rejectPreviewRequest({
                isAxiosError: true,
                response: {
                    status: 404,
                    data: { message: "対象の職務経歴書データが存在しません。", errors: {} },
                },
            });
        });

        expect(await screen.findByText("resume list destination")).toBeInTheDocument();
        expect(await screen.findByText("対象の職務経歴書データが存在しません。")).toBeInTheDocument();
        expect(screen.queryByRole("dialog", { name: "PDFプレビュー" })).not.toBeInTheDocument();
    });

    it("保存APIのfield errorを該当フォームへ表示すること", async () => {
        vi.mocked(protectedApiClient.put).mockRejectedValueOnce({
            response: {
                data: {
                    errors: {
                        resumeName: ["職務経歴書名を入力してください。"],
                    },
                },
            },
        });

        const { user } = renderEditor();

        const resumeName = await screen.findByRole("textbox", { name: /職務経歴書名/ });
        await user.clear(resumeName);
        await user.click(screen.getByRole("button", { name: "基本情報を保存" }));

        expect(await screen.findByText(/職務経歴書名を入力してください。/)).toBeInTheDocument();
    });
});
