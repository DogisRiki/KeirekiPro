import { act, screen, waitFor } from "@testing-library/react";
import { vi } from "vitest";

import { toastMessage } from "@/config/messages";
import { NotificationProvider } from "@/providers/NotificationProvider";
import { useNotificationStore } from "@/stores";
import { renderWithProviders, resetStoresAndMocks } from "@/test";

describe("NotificationProvider", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
        sessionStorage.clear();
    });

    it("セッションに残された通知を表示し、表示したらセッションから消すこと", async () => {
        sessionStorage.setItem("global-toast", JSON.stringify({ m: toastMessage.unauthorized, t: "error" }));

        renderWithProviders(<NotificationProvider />);

        const alert = await screen.findByRole("alert");
        expect(alert).toHaveTextContent(toastMessage.unauthorized);
        expect(alert).toHaveClass("MuiAlert-colorError");
        expect(useNotificationStore.getState().type).toBe("error");
        expect(sessionStorage.getItem("global-toast")).toBeNull();
    });

    it("セッションに通知が無いときは、何も表示しないこと", () => {
        renderWithProviders(<NotificationProvider />);

        expect(screen.queryByRole("alert")).not.toBeInTheDocument();
        expect(useNotificationStore.getState().isShow).toBe(false);
    });

    it("ストアの通知を表示し、閉じるボタンで消すこと", async () => {
        const { user } = renderWithProviders(<NotificationProvider />);

        act(() => {
            useNotificationStore.getState().setNotification("保存しました", "success");
        });

        const alert = await screen.findByRole("alert");
        expect(alert).toHaveTextContent("保存しました");
        expect(alert).toHaveClass("MuiAlert-colorSuccess");

        await user.click(screen.getByRole("button", { name: "Close" }));

        expect(useNotificationStore.getState().isShow).toBe(false);
        await waitFor(() => expect(screen.queryByRole("alert")).not.toBeInTheDocument());
    });

    it("5秒経つと通知を閉じること", () => {
        vi.useFakeTimers();
        try {
            renderWithProviders(<NotificationProvider />);

            act(() => {
                useNotificationStore.getState().setNotification("保存しました", "success");
            });

            act(() => {
                vi.advanceTimersByTime(4999);
            });
            expect(useNotificationStore.getState().isShow).toBe(true);

            act(() => {
                vi.advanceTimersByTime(1);
            });
            expect(useNotificationStore.getState().isShow).toBe(false);
        } finally {
            vi.useRealTimers();
        }
    });

    it("通知の外をクリックしても閉じないこと", async () => {
        const { user } = renderWithProviders(
            <>
                <button type="button">外側</button>
                <NotificationProvider />
            </>,
        );

        act(() => {
            useNotificationStore.getState().setNotification("保存しました", "success");
        });
        await screen.findByRole("alert");

        await user.click(screen.getByRole("button", { name: "外側" }));

        expect(useNotificationStore.getState().isShow).toBe(true);
        expect(screen.getByRole("alert")).toHaveTextContent("保存しました");
    });
});
