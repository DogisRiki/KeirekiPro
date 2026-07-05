import { fireEvent, screen, waitFor } from "@testing-library/react";
import type { Dayjs } from "dayjs";
import dayjs from "dayjs";
import { useState } from "react";
import { vi } from "vitest";

import { DatePicker, Dialog, Loading, PasswordTextField, ScrollToTopButton, ThemeSwitch } from "@/components/ui";
import { useThemeStore } from "@/stores";
import { renderWithProviders, resetStoresAndMocks } from "@/test";

describe("ui controls", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
    });

    it("Dialogはconfirm/cancelで正しいcallbackを呼ぶこと", async () => {
        const onClose = vi.fn();
        const { user, rerender } = renderWithProviders(
            <Dialog open variant="confirm" title="confirm title" description="confirm description" onClose={onClose} />,
        );

        expect(screen.getByRole("dialog", { name: "confirm title" })).toBeInTheDocument();
        await user.click(screen.getByRole("button", { name: "いいえ" }));
        expect(onClose).toHaveBeenCalledWith(false);

        rerender(
            <Dialog open variant="confirm" title="confirm title" description="confirm description" onClose={onClose} />,
        );
        await user.click(screen.getByRole("button", { name: "はい" }));
        expect(onClose).toHaveBeenCalledWith(true);
    });

    it("PasswordTextFieldはaccessible name付きボタンで表示を切り替えること", async () => {
        const Wrapper = () => {
            const [value, setValue] = useState("");
            return (
                <PasswordTextField
                    label="パスワード"
                    value={value}
                    onChange={(e) => setValue(e.target.value)}
                    slotProps={{ htmlInput: { maxLength: 12, minLength: 8 } }}
                />
            );
        };

        const { user } = renderWithProviders(<Wrapper />);
        const input = screen.getByLabelText("パスワード");

        expect(input).toHaveAttribute("type", "password");
        expect(input).toHaveAttribute("maxlength", "12");

        await user.type(input, "pass1234");
        await user.click(screen.getByRole("button", { name: "パスワードを表示" }));

        expect(input).toHaveValue("pass1234");
        expect(input).toHaveAttribute("type", "text");
        expect(screen.getByRole("button", { name: "パスワードを隠す" })).toBeInTheDocument();
    });

    it("DatePickerは入力欄操作で開き直接入力では値を変えないこと", async () => {
        const onOpen = vi.fn();
        const onChange = vi.fn();
        const { user } = renderWithProviders(
            <DatePicker label="日付" value={dayjs("2024-01-01")} onChange={onChange} open={false} onOpen={onOpen} />,
        );

        const input = screen.getByRole("group", { name: "日付" });

        await user.click(input);
        fireEvent.keyDown(input, { key: "Enter" });
        await user.type(input, "2024/02/01");
        fireEvent.paste(input, { clipboardData: { getData: () => "2024/03/01" } });

        expect(onOpen).toHaveBeenCalled();
        expect(onChange).not.toHaveBeenCalled();
    });

    it("DatePickerはカレンダー選択で値を更新できること", async () => {
        const onChange = vi.fn<(newValue: Dayjs | null) => void>();
        const Wrapper = () => {
            const [value, setValue] = useState<Dayjs | null>(dayjs("2024-01-01"));

            return (
                <DatePicker
                    label="日付"
                    value={value}
                    onChange={(newValue) => {
                        onChange(newValue);
                        setValue(newValue);
                    }}
                />
            );
        };

        const { user } = renderWithProviders(<Wrapper />);

        await user.click(screen.getByRole("group", { name: "日付" }));
        await user.click(await screen.findByRole("gridcell", { name: "15" }));

        await waitFor(() => expect(onChange).toHaveBeenCalled());
        const selectedValue = onChange.mock.calls[onChange.mock.calls.length - 1]?.[0];
        expect(selectedValue?.format("YYYY-MM-DD")).toBe("2024-01-15");
    });

    it("Loadingはactiveに応じて表示を切り替えること", () => {
        const { rerender } = renderWithProviders(<Loading active />);

        expect(screen.getByRole("progressbar")).toBeVisible();

        rerender(<Loading active={false} />);

        expect(screen.queryByRole("progressbar")).not.toBeInTheDocument();
    });

    it("Loadingのoverlayは対象領域内に表示すること", () => {
        renderWithProviders(
            <div style={{ position: "relative", minHeight: 120 }}>
                <button>対象操作</button>
                <Loading active variant="overlay" />
            </div>,
        );

        expect(screen.getByRole("button", { name: "対象操作" })).toBeInTheDocument();
        expect(screen.getByRole("progressbar")).toBeVisible();
    });

    it("ScrollToTopButtonはスクロール後に表示されクリックで先頭へ戻すこと", async () => {
        const scrollTo = vi.spyOn(window, "scrollTo").mockImplementation(() => {});
        Object.defineProperty(window, "scrollY", { value: 0, writable: true, configurable: true });

        const { user } = renderWithProviders(<ScrollToTopButton />);
        expect(screen.queryByRole("button", { name: "ページ上部へ戻る" })).not.toBeInTheDocument();

        Object.defineProperty(window, "scrollY", { value: 301, writable: true, configurable: true });
        fireEvent.scroll(window);

        await user.click(await screen.findByRole("button", { name: "ページ上部へ戻る" }));

        expect(scrollTo).toHaveBeenCalledWith({ top: 0, behavior: "smooth" });
    });

    it("ThemeSwitchはclickでtheme storeのmodeを更新すること", async () => {
        const { user } = renderWithProviders(<ThemeSwitch />);

        await user.click(screen.getByRole("switch"));

        expect(useThemeStore.getState().mode).toBe("dark");
    });
});
