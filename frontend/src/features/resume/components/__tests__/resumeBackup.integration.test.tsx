import { screen, waitFor, within } from "@testing-library/react";
import type { AxiosResponse } from "axios";
import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: {
        get: vi.fn(),
    },
}));

vi.mock("file-saver", () => ({
    saveAs: vi.fn(),
}));

import { BackupSection } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { renderWithProviders, resetStoresAndMocks } from "@/test";

import { resumeSummaries } from "./resumeTestData";

describe("resume backup", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
        vi.mocked(protectedApiClient.get).mockReset();
        vi.mocked(protectedApiClient.get).mockResolvedValue({
            data: new Blob(["{}"], { type: "application/json" }),
            headers: { "content-disposition": 'attachment; filename="backup.json"' },
        } as unknown as AxiosResponse<Blob>);
    });

    it("BackupSectionは未選択では実行できずconfirm時だけバックアップAPIを呼ぶこと", async () => {
        const { user } = renderWithProviders(<BackupSection resumeList={resumeSummaries} />);

        const backupButton = screen.getByRole("button", { name: "バックアップ" });
        expect(backupButton).toBeDisabled();

        await user.click(screen.getByRole("combobox"));
        await user.click(screen.getByRole("option", { name: "Alpha Resume" }));
        expect(backupButton).toBeEnabled();

        await user.click(backupButton);
        await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "いいえ" }));
        await waitFor(() => expect(screen.queryByRole("dialog")).not.toBeInTheDocument());
        expect(protectedApiClient.get).not.toHaveBeenCalled();

        await user.click(backupButton);
        await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "はい" }));

        await waitFor(() =>
            expect(protectedApiClient.get).toHaveBeenCalledWith(
                "/resumes/resume-1/backup",
                expect.objectContaining({ responseType: "blob" }),
            ),
        );
    });
});
