import { act, screen, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";
import { Route, Routes } from "react-router";
import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: {
        get: vi.fn(),
        post: vi.fn(),
    },
}));

import type { GetResumeListResponse, Resume } from "@/features/resume";
import { CreateResumeContainer, ResumeListContainer } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useNotificationStore } from "@/stores";
import { renderWithProviders, resetStoresAndMocks } from "@/test";

import { cloneResume, resumeSummaries } from "./resumeTestData";

describe("resume list", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
        URL.createObjectURL = vi.fn(() => "data:application/pdf;base64,JVBERi0=");
        URL.revokeObjectURL = vi.fn();
        vi.mocked(protectedApiClient.get).mockReset();
        vi.mocked(protectedApiClient.post).mockReset();
        vi.mocked(protectedApiClient.get).mockResolvedValue({
            data: { resumes: resumeSummaries },
        } as AxiosResponse<GetResumeListResponse>);
        vi.mocked(protectedApiClient.post).mockImplementation((url: string) => {
            if (url === "/resumes/resume-1/export") {
                return Promise.resolve({
                    data: new Blob(["pdf"], { type: "application/pdf" }),
                    headers: {},
                } as AxiosResponse<Blob>);
            }
            return Promise.resolve({
                data: cloneResume({ id: "created-resume" }),
            } as AxiosResponse<Resume>);
        });
    });

    it("ResumeListContainerは一覧取得後にカードを表示しクリックで編集画面へ遷移すること", async () => {
        const { user } = renderWithProviders(
            <Routes>
                <Route path="/resume/list" element={<ResumeListContainer />} />
                <Route path="/resume/:id" element={<div>edit destination</div>} />
            </Routes>,
            { route: "/resume/list" },
        );

        expect(await screen.findByText("Alpha Resume")).toBeInTheDocument();
        expect(screen.getByText("Beta Resume")).toBeInTheDocument();

        await user.click(screen.getByText("Alpha Resume"));

        expect(await screen.findByText("edit destination")).toBeInTheDocument();
        expect(protectedApiClient.get).toHaveBeenCalledWith("/resumes");
    });

    it("ResumeListContainerはempty時にNoData表示に切り替わること", async () => {
        vi.mocked(protectedApiClient.get).mockResolvedValueOnce({
            data: { resumes: [] },
        } as unknown as AxiosResponse<GetResumeListResponse>);

        renderWithProviders(<ResumeListContainer />);

        expect(await screen.findByText("表示するデータがありません。")).toBeInTheDocument();
    });

    it("ResumeListContainerは一覧の初回取得中にNoDataを表示しないこと", async () => {
        let resolveListRequest!: (response: AxiosResponse<GetResumeListResponse>) => void;
        vi.mocked(protectedApiClient.get).mockImplementationOnce(
            () =>
                new Promise((resolve) => {
                    resolveListRequest = resolve;
                }),
        );

        renderWithProviders(<ResumeListContainer />);

        expect(screen.queryByText("表示するデータがありません。")).not.toBeInTheDocument();

        act(() => {
            resolveListRequest({ data: { resumes: [] } } as AxiosResponse<GetResumeListResponse>);
        });

        expect(await screen.findByText("表示するデータがありません。")).toBeInTheDocument();
    });

    it("CreateResumeContainerはAPI結果のIDで編集画面へ遷移しsuccess通知を設定すること", async () => {
        const { user } = renderWithProviders(
            <Routes>
                <Route path="/resume/new" element={<CreateResumeContainer />} />
                <Route path="/resume/:id" element={<div>created resume destination</div>} />
            </Routes>,
            { route: "/resume/new" },
        );

        await screen.findByRole("combobox");
        await user.type(screen.getByRole("textbox", { name: /職務経歴書名/ }), "New Resume");
        await user.click(screen.getByRole("combobox"));
        await user.click(screen.getByRole("option", { name: "Alpha Resume" }));
        await user.click(screen.getByRole("button", { name: "作成" }));

        expect(await screen.findByText("created resume destination")).toBeInTheDocument();
        expect(protectedApiClient.post).toHaveBeenCalledWith("/resumes", {
            resumeName: "New Resume",
            resumeId: "resume-1",
        });
        expect(useNotificationStore.getState()).toMatchObject({
            message: "職務経歴書を作成しました。",
            type: "success",
            isShow: true,
        });
    });

    it("コピー元が存在しない場合はコピー元を未選択に戻すこと", async () => {
        vi.mocked(protectedApiClient.post).mockRejectedValueOnce({
            isAxiosError: true,
            response: {
                status: 404,
                data: { message: "対象の職務経歴書データが存在しません。", errors: {} },
            },
        });

        const { user } = renderWithProviders(<CreateResumeContainer />);

        await screen.findByRole("combobox");
        await user.type(screen.getByRole("textbox", { name: /職務経歴書名/ }), "Copied Resume");
        await user.click(screen.getByRole("combobox"));
        await user.click(screen.getByRole("option", { name: "Alpha Resume" }));
        await user.click(screen.getByRole("button", { name: "作成" }));

        await waitFor(() => expect(screen.getByRole("combobox")).toHaveTextContent("未選択"));
        expect(protectedApiClient.post).toHaveBeenCalledWith("/resumes", {
            resumeName: "Copied Resume",
            resumeId: "resume-1",
        });
    });

    it("ResumeCardMenuからPDFエクスポートを選んでも編集画面へ遷移せずPDFプレビューモーダルを操作できること", async () => {
        const { user } = renderWithProviders(
            <Routes>
                <Route path="/resume/list" element={<ResumeListContainer />} />
                <Route path="/resume/:id" element={<div>edit destination</div>} />
            </Routes>,
            { route: "/resume/list" },
        );

        await screen.findByText("Alpha Resume");
        await user.click(screen.getAllByRole("button", { name: "職務経歴書メニューを開く" })[0]);
        await user.hover(screen.getByRole("menuitem", { name: "エクスポート" }));
        await user.click(await screen.findByRole("menuitem", { name: "PDFでエクスポート" }));

        const dialog = await screen.findByRole("dialog", { name: "PDFプレビュー" });
        await user.click(screen.getByLabelText("カラーコード"));

        expect(dialog).toBeInTheDocument();
        expect(screen.queryByText("edit destination")).not.toBeInTheDocument();
        expect(protectedApiClient.post).toHaveBeenCalledWith(
            expect.stringMatching(/^\/resumes\/resume-[12]\/export$/),
            expect.objectContaining({
                format: "pdf",
                disposition: "inline",
            }),
            expect.objectContaining({
                headers: { Accept: "application/pdf, application/json" },
            }),
        );
    });

    it("一覧画面でMarkdownエクスポート対象が存在しない場合は一覧を再取得すること", async () => {
        let listRequestCount = 0;
        vi.mocked(protectedApiClient.get).mockImplementation((url: string) => {
            if (url === "/resumes") {
                listRequestCount += 1;
                return Promise.resolve({
                    data: { resumes: listRequestCount === 1 ? resumeSummaries : [resumeSummaries[1]] },
                } as AxiosResponse<GetResumeListResponse>);
            }
            if (url === "/resumes/resume-1/export") {
                return Promise.reject({
                    isAxiosError: true,
                    response: {
                        status: 404,
                        data: { message: "対象の職務経歴書データが存在しません。", errors: {} },
                    },
                });
            }
            return Promise.resolve({ data: undefined } as AxiosResponse<void>);
        });

        const { user } = renderWithProviders(<ResumeListContainer />, { route: "/resume/list" });

        await screen.findByText("Alpha Resume");
        await user.click(screen.getAllByRole("button", { name: "職務経歴書メニューを開く" })[1]);
        await user.hover(screen.getByRole("menuitem", { name: "エクスポート" }));
        await user.click(await screen.findByRole("menuitem", { name: "Markdownでエクスポート" }));

        await waitFor(() => expect(screen.queryByText("Alpha Resume")).not.toBeInTheDocument());
        expect(screen.getByText("Beta Resume")).toBeInTheDocument();
        expect(listRequestCount).toBe(2);
    });

    it("一覧画面でPDFプレビュー対象が存在しない場合は一覧を再取得すること", async () => {
        let listRequestCount = 0;
        let rejectPreviewRequest!: (error: unknown) => void;
        vi.mocked(protectedApiClient.get).mockImplementation((url: string) => {
            if (url === "/resumes") {
                listRequestCount += 1;
                return Promise.resolve({
                    data: { resumes: listRequestCount === 1 ? resumeSummaries : [resumeSummaries[1]] },
                } as AxiosResponse<GetResumeListResponse>);
            }
            return Promise.resolve({ data: undefined } as AxiosResponse<void>);
        });
        vi.mocked(protectedApiClient.post).mockImplementationOnce(
            () =>
                new Promise((_, reject) => {
                    rejectPreviewRequest = reject;
                }),
        );

        const { user } = renderWithProviders(<ResumeListContainer />, { route: "/resume/list" });

        await screen.findByText("Alpha Resume");
        await user.click(screen.getAllByRole("button", { name: "職務経歴書メニューを開く" })[1]);
        await user.hover(screen.getByRole("menuitem", { name: "エクスポート" }));
        await user.click(await screen.findByRole("menuitem", { name: "PDFでエクスポート" }));

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

        await waitFor(() => expect(screen.queryByText("Alpha Resume")).not.toBeInTheDocument());
        expect(screen.getByText("Beta Resume")).toBeInTheDocument();
        expect(screen.queryByRole("dialog", { name: "PDFプレビュー" })).not.toBeInTheDocument();
        expect(protectedApiClient.post).toHaveBeenCalledTimes(1);
        expect(listRequestCount).toBeGreaterThanOrEqual(2);
    });
});
