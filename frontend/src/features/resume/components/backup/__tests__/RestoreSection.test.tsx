import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: {
        post: vi.fn(),
    },
}));

import { RestoreSection } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { createAxiosResponse, renderWithProviders, resetStoresAndMocks } from "@/test";
import { fireEvent, screen, waitFor } from "@testing-library/react";

const backupJson = { resume: { name: "バックアップした職務経歴書" } };

const createJsonFile = (name = "backup.json") =>
    new File([JSON.stringify(backupJson)], name, { type: "application/json" });

const createTextFile = () => new File(["not json"], "memo.txt", { type: "text/plain" });

/**
 * ドロップ領域にファイルを落とす(ファイル選択と同じ判定を通る)
 */
const selectFiles = (files: File[]) => {
    const items = files.map((file) => ({ kind: "file", type: file.type, getAsFile: () => file }));
    fireEvent.drop(screen.getByRole("presentation"), { dataTransfer: { files, items, types: ["Files"] } });
};

const restoreButton = () => screen.getByRole("button", { name: "リストア" });

describe("RestoreSection", () => {
    beforeEach(() => {
        resetStoresAndMocks([() => vi.mocked(protectedApiClient.post).mockReset()]);
    });

    it("ファイルを選ぶまでは、リストアボタンを押せないこと", () => {
        renderWithProviders(<RestoreSection />);

        expect(screen.getByText("ファイルをドラッグ＆ドロップ または クリックして選択")).toBeInTheDocument();
        expect(restoreButton()).toBeDisabled();
    });

    it("JSONのファイルを選んだときは、そのファイルを選択中にし、リストアボタンを押せるようにすること", async () => {
        renderWithProviders(<RestoreSection />);

        selectFiles([createJsonFile()]);

        expect(await screen.findByText("backup.json")).toBeInTheDocument();
        expect(restoreButton()).toBeEnabled();
    });

    it("JSON以外のファイルを選んだときは、選択中のファイルを取り消すこと", async () => {
        renderWithProviders(<RestoreSection />);
        selectFiles([createJsonFile()]);
        await screen.findByText("backup.json");

        selectFiles([createTextFile()]);

        await waitFor(() => expect(screen.queryByText("backup.json")).not.toBeInTheDocument());
        expect(screen.queryByText("memo.txt")).not.toBeInTheDocument();
        expect(restoreButton()).toBeDisabled();
    });

    it("複数のファイルを選んだときは、どれも選択中にしないこと", async () => {
        renderWithProviders(<RestoreSection />);
        selectFiles([createJsonFile()]);
        await screen.findByText("backup.json");

        selectFiles([createJsonFile("first.json"), createJsonFile("second.json")]);

        await waitFor(() => expect(screen.queryByText("backup.json")).not.toBeInTheDocument());
        expect(screen.queryByText("first.json")).not.toBeInTheDocument();
        expect(screen.queryByText("second.json")).not.toBeInTheDocument();
        expect(restoreButton()).toBeDisabled();
    });

    it("選択解除を押すと、選択を取り消し、ファイル選択の画面は開かないこと", async () => {
        const { user } = renderWithProviders(<RestoreSection />);
        selectFiles([createJsonFile()]);
        await screen.findByText("backup.json");
        const openDialog = vi.spyOn(HTMLInputElement.prototype, "click");

        await user.click(screen.getByRole("button", { name: "選択解除" }));

        expect(screen.queryByText("backup.json")).not.toBeInTheDocument();
        expect(screen.getByText("ファイルをドラッグ＆ドロップ または クリックして選択")).toBeInTheDocument();
        expect(restoreButton()).toBeDisabled();
        expect(openDialog).not.toHaveBeenCalled();
    });

    it("リストアボタンを押すと、選んだファイルの内容で復元を依頼すること", async () => {
        vi.mocked(protectedApiClient.post).mockResolvedValue(createAxiosResponse({ id: "resume-1" }));
        const { user } = renderWithProviders(<RestoreSection />);
        selectFiles([createJsonFile()]);
        await screen.findByText("backup.json");

        await user.click(restoreButton());

        await waitFor(() => expect(protectedApiClient.post).toHaveBeenCalledTimes(1));
        expect(protectedApiClient.post).toHaveBeenCalledWith("/resumes/restore", backupJson);
    });

    it("復元の処理中は、リストアボタンを押せないこと", async () => {
        vi.mocked(protectedApiClient.post).mockReturnValue(new Promise(() => {}));
        const { user } = renderWithProviders(<RestoreSection />);
        selectFiles([createJsonFile()]);
        await screen.findByText("backup.json");

        await user.click(restoreButton());

        await waitFor(() => expect(restoreButton()).toBeDisabled());
        expect(screen.getByText("backup.json")).toBeInTheDocument();
    });
});
