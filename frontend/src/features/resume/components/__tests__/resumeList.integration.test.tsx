import { screen } from "@testing-library/react";
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
        vi.mocked(protectedApiClient.get).mockReset();
        vi.mocked(protectedApiClient.post).mockReset();
        vi.mocked(protectedApiClient.get).mockResolvedValue({
            data: { resumes: resumeSummaries },
        } as AxiosResponse<GetResumeListResponse>);
        vi.mocked(protectedApiClient.post).mockResolvedValue({
            data: cloneResume({ id: "created-resume" }),
        } as AxiosResponse<Resume>);
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
});
