import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { TEMP_ID_PREFIX, useResumeStore, useUpdateCertification } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useUpdateCertification", () => {
    const wrapper = createQueryWrapper();

    const localOnlyTempId = `${TEMP_ID_PREFIX}cert-temp-99`;

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
                id: "cert-1",
                name: "ローカル（更新対象・dirty）",
                date: "2020-06-01",
            },
            {
                id: "cert-3",
                name: "ローカル（別dirty）",
                date: "2021-01-01",
            },
            {
                id: localOnlyTempId,
                name: "ローカルのみ（temp）",
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
        vi.mocked(protectedApiClient.put).mockReset();

        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useNotificationStore.getState(), "setNotification");

        vi.spyOn(useResumeStore.getState(), "updateResumeFromServer");
        vi.spyOn(useResumeStore.getState(), "setDirty");
        vi.spyOn(useResumeStore.getState(), "removeDirtyEntryId");
    });

    it("成功時はcertificationsをマージしてupdateResumeFromServerが呼ばれ、dirty解除・通知が実行されること", async () => {
        const certificationId = "cert-1";

        // store準備
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().addDirtyEntryId(certificationId);
        useResumeStore.getState().addDirtyEntryId("cert-3");
        useResumeStore.getState().addDirtyEntryId(localOnlyTempId);

        const serverResume: Resume = {
            ...localResume,
            updatedAt: "2024-02-10T00:00:00.000Z",
            certifications: [
                {
                    id: "cert-1",
                    name: "サーバー（更新後）",
                    date: "2020-06-01",
                },
                {
                    id: "cert-2",
                    name: "サーバー（別エントリー）",
                    date: "2019-01-01",
                },
                {
                    id: "cert-3",
                    name: "サーバー（dirtyで上書きされる想定）",
                    date: "2021-01-01",
                },
            ],
        };

        const mockResponse = { status: 200, data: serverResume } as AxiosResponse<Resume>;
        vi.mocked(protectedApiClient.put).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useUpdateCertification("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                certificationId,
                payload: {
                    name: "ローカル（更新対象・dirty）",
                    date: "2020-06-01",
                },
            });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // マージ結果：
        // - ローカルのみのエントリー（temp）は先頭へ
        // - server certificationsをベースにdirtyなcert-3はローカルデータで上書き
        // - 更新対象（certificationId=cert-1）はローカル上書き対象から除外されるため、serverが優先
        const expectedCertifications = [
            localResume.certifications.find((c) => c.id === localOnlyTempId)!,
            serverResume.certifications.find((c) => c.id === "cert-1")!, // server優先
            serverResume.certifications.find((c) => c.id === "cert-2")!,
            localResume.certifications.find((c) => c.id === "cert-3")!, // dirtyなのでローカル優先
        ];

        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().updateResumeFromServer).toHaveBeenCalledWith({
            certifications: expectedCertifications,
            updatedAt: serverResume.updatedAt,
        });
        expect(useResumeStore.getState().removeDirtyEntryId).toHaveBeenCalledWith(certificationId);
        expect(useResumeStore.getState().setDirty).toHaveBeenCalledWith(false);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith("資格を更新しました。", "success");
    });
});
