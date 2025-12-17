import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { TEMP_ID_PREFIX, useCreateCertification, useResumeStore } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useCreateCertification", () => {
    const wrapper = createQueryWrapper();

    const tempId = `${TEMP_ID_PREFIX}cert-temp-1`;
    const localOnlyTempId = `${TEMP_ID_PREFIX}cert-temp-2`;

    const localResume: Resume = {
        id: "resume-1",
        resumeName: "テスト職務経歴書",
        date: "2024-01-01",
        lastName: "山田",
        firstName: "太郎",
        createdAt: "2024-01-01T00:00:00.000Z",
        updatedAt: "2024-01-01T00:00:00.000Z",
        careers: [],
        projects: [],
        certifications: [
            {
                id: tempId,
                name: "一時資格",
                date: "2024-01-01",
            },
            {
                id: "cert-1",
                name: "ローカル（dirty）資格名",
                date: "2020-06-01",
            },
            {
                id: localOnlyTempId,
                name: "ローカルのみ（temp）資格",
                date: "2023-01-01",
            },
        ],
        portfolios: [],
        socialLinks: [],
        selfPromotions: [],
    };

    beforeEach(() => {
        resetStoresAndMocks([]);
        useResumeStore.getState().clearResume();
        vi.mocked(protectedApiClient.post).mockReset();

        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useNotificationStore.getState(), "setNotification");

        vi.spyOn(useResumeStore.getState(), "updateResumeFromServer");
        vi.spyOn(useResumeStore.getState(), "setDirty");
        vi.spyOn(useResumeStore.getState(), "removeDirtyEntryId");
        vi.spyOn(useResumeStore.getState(), "setActiveEntryId");
    });

    it("成功時はcertificationsをマージしてupdateResumeFromServerが呼ばれ、activeEntryId更新・dirty解除・通知が実行されること", async () => {
        // store準備
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().setActiveSection("certification");
        useResumeStore.getState().setActiveEntryId(tempId);
        useResumeStore.getState().addDirtyEntryId(tempId);
        useResumeStore.getState().addDirtyEntryId("cert-1"); // serverから返るIDをdirtyとして上書き対象にする

        const serverResume: Resume = {
            ...localResume,
            updatedAt: "2024-02-01T00:00:00.000Z",
            certifications: [
                {
                    id: "cert-1",
                    name: "サーバー資格名（上書きされる想定）",
                    date: "2020-06-01",
                },
                {
                    id: "cert-2",
                    name: "新規作成された資格",
                    date: "2024-01-01",
                },
            ],
        };

        const mockResponse = { status: 201, data: serverResume } as AxiosResponse<Resume>;
        vi.mocked(protectedApiClient.post).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useCreateCertification("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                tempId,
                payload: {
                    name: "一時資格",
                    date: "2024-01-01",
                },
            });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // certificationsのマージ結果：
        // - 保存対象のtempIdは除外
        // - ローカルのみのエントリー（localOnlyTempId）を先頭へ
        // - server certificationsをベースに、dirtyなcert-1はローカルデータで上書き
        const expectedCertifications = [
            localResume.certifications.find((c) => c.id === localOnlyTempId)!,
            localResume.certifications.find((c) => c.id === "cert-1")!, // dirtyなのでローカルが優先
            serverResume.certifications.find((c) => c.id === "cert-2")!,
        ];

        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().updateResumeFromServer).toHaveBeenCalledWith({
            certifications: expectedCertifications,
            updatedAt: serverResume.updatedAt,
        });
        expect(useResumeStore.getState().setActiveEntryId).toHaveBeenCalledWith("cert-2");
        expect(useResumeStore.getState().removeDirtyEntryId).toHaveBeenCalledWith(tempId);
        expect(useResumeStore.getState().setDirty).toHaveBeenCalledWith(false);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith("資格を作成しました。", "success");
    });
});
