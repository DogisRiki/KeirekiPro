import { SectionTabs, sections, useResumeStore } from "@/features/resume";
import { renderWithProviders, resetStoresAndMocks } from "@/test";
import { screen, within } from "@testing-library/react";
import { vi } from "vitest";

/** 画面幅の判定(useMediaQuery)を、スマホ幅かどうかで固定する */
const mockMobile = (isMobile: boolean) => {
    vi.spyOn(window, "matchMedia").mockImplementation((query: string) => ({
        matches: isMobile,
        media: query,
        onchange: null,
        addListener: vi.fn(),
        removeListener: vi.fn(),
        addEventListener: vi.fn(),
        removeEventListener: vi.fn(),
        dispatchEvent: vi.fn(() => false),
    }));
};

describe("SectionTabs", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
        useResumeStore.getState().setActiveSection("career");
    });

    describe("デスクトップ幅", () => {
        beforeEach(() => {
            mockMobile(false);
        });

        it("セクションをタブで並べ、表示中のセクションを選択中にすること", () => {
            renderWithProviders(<SectionTabs />);

            expect(screen.getAllByRole("tab").map((tab) => tab.textContent)).toEqual(
                sections.map((section) => section.label),
            );
            expect(screen.getByRole("tab", { name: "職歴" })).toHaveAttribute("aria-selected", "true");
            expect(screen.getByRole("tab", { name: "基本" })).toHaveAttribute("aria-selected", "false");
            expect(screen.queryByRole("combobox")).not.toBeInTheDocument();
        });

        it.each(sections.filter((section) => section.key !== "career"))(
            "$label のタブを押すと、そのセクションに切り替えること",
            async ({ key, label }) => {
                const { user } = renderWithProviders(<SectionTabs />);

                await user.click(screen.getByRole("tab", { name: label }));

                expect(useResumeStore.getState().activeSection).toBe(key);
                expect(screen.getByRole("tab", { name: label })).toHaveAttribute("aria-selected", "true");
            },
        );
    });

    describe("スマホ幅", () => {
        beforeEach(() => {
            mockMobile(true);
        });

        it("セクションをセレクトで出し、表示中のセクションを選んだ状態にすること", async () => {
            const { user } = renderWithProviders(<SectionTabs />);

            expect(screen.queryByRole("tab")).not.toBeInTheDocument();
            const select = screen.getByRole("combobox");
            expect(select).toHaveTextContent("職歴");

            await user.click(select);

            const options = within(screen.getByRole("listbox")).getAllByRole("option");
            expect(options.map((option) => option.textContent)).toEqual(sections.map((section) => section.label));
            expect(screen.getByRole("option", { name: "職歴" })).toHaveAttribute("aria-selected", "true");
        });

        it.each(sections.filter((section) => section.key !== "career"))(
            "$label を選ぶと、そのセクションに切り替えて選択肢を閉じること",
            async ({ key, label }) => {
                const { user } = renderWithProviders(<SectionTabs />);

                await user.click(screen.getByRole("combobox"));
                await user.click(screen.getByRole("option", { name: label }));

                expect(useResumeStore.getState().activeSection).toBe(key);
                expect(screen.getByRole("combobox")).toHaveTextContent(label);
                expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
            },
        );
    });
});
