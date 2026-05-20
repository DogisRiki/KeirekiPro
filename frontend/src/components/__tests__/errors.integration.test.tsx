import { act, screen, waitFor } from "@testing-library/react";
import { vi } from "vitest";

import { ErrorBanner, ErrorFallback, NotFound, ServerError } from "@/components/errors";
import { useErrorMessageStore } from "@/stores";
import { renderWithProviders, resetStoresAndMocks } from "@/test";

describe("errors", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
    });

    it("ErrorBannerはgeneral errorを表示し閉じた後も新しいエラーで再表示すること", async () => {
        const { user } = renderWithProviders(<ErrorBanner />);

        act(() => {
            useErrorMessageStore.getState().setErrors({ message: "最初のエラー", errors: {} });
        });

        expect(await screen.findByRole("alert")).toHaveTextContent("最初のエラー");
        await user.click(screen.getByRole("button", { name: "close" }));
        await waitFor(() => expect(screen.queryByRole("alert")).not.toBeInTheDocument());

        act(() => {
            useErrorMessageStore.getState().setErrors({ message: "次のエラー", errors: {} });
        });

        expect(await screen.findByRole("alert")).toHaveTextContent("次のエラー");
    });

    it("ErrorFallbackはエラー表示とrefresh操作を実行すること", async () => {
        const assign = vi.spyOn(window.location, "assign").mockImplementation(() => {});
        const { user } = renderWithProviders(<ErrorFallback />);

        expect(screen.getByRole("alert")).toHaveTextContent("Ooops, something went wrong :(");
        await user.click(screen.getByRole("button", { name: "Refresh" }));

        expect(assign).toHaveBeenCalledWith(window.location.origin);
    });

    it("NotFoundは404表示とトップへ戻る操作を実行すること", async () => {
        const assign = vi.spyOn(window.location, "assign").mockImplementation(() => {});
        const { user } = renderWithProviders(<NotFound />);

        expect(screen.getByRole("alert")).toHaveTextContent("404");
        await user.click(screen.getByRole("button"));

        expect(assign).toHaveBeenCalledWith(window.location.origin);
    });

    it("ServerErrorは戻る操作を実行すること", async () => {
        const back = vi.spyOn(window.history, "back").mockImplementation(() => {});
        const { user } = renderWithProviders(<ServerError />);

        await user.click(screen.getByRole("button"));

        expect(back).toHaveBeenCalled();
    });
});
