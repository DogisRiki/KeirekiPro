import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { get: vi.fn() },
}));

import type { SnsPlatform } from "@/features/resume";
import { SnsPlatformSection, useResumeStore } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { createAxiosResponse, renderWithProviders, resetStoresAndMocks } from "@/test";
import { fireEvent, screen } from "@testing-library/react";

import { cloneResume } from "../../../__tests__/resumeTestData";

type FieldErrors = Record<string, string[]>;

const otherSnsPlatform: SnsPlatform = { id: "sns-2", name: "Qiita", link: "https://qiita.com/example" };

/** SNSを2件持ち、そのうち1件を選んだ状態で描画する */
const renderSection = ({ sns = {}, errors }: { sns?: Partial<SnsPlatform>; errors?: FieldErrors } = {}) => {
    const store = useResumeStore.getState();
    store.setResume(
        cloneResume({
            snsPlatforms: [
                otherSnsPlatform,
                { id: "sns-1", name: "GitHub", link: "https://github.com/example", ...sns },
            ],
        }),
    );
    store.setActiveSection("snsPlatform");
    store.setActiveEntryId("sns-1");
    if (errors) {
        store.setEntryErrors("sns-1", errors);
    }
    return renderWithProviders(<SnsPlatformSection />);
};

const currentSnsPlatform = () => useResumeStore.getState().resume?.snsPlatforms.find((sns) => sns.id === "sns-1");

const nameInput = () => screen.getByRole("combobox", { name: /^プラットフォーム名/ });

const linkInput = () => screen.getByRole("textbox", { name: /^リンク/ });

describe("SnsPlatformSection", () => {
    beforeEach(() => {
        resetStoresAndMocks([() => vi.mocked(protectedApiClient.get).mockReset()]);
        vi.mocked(protectedApiClient.get).mockResolvedValue(createAxiosResponse({ names: ["GitHub", "Zenn"] }));
    });

    it("SNSが選ばれていないときは、選択を促す文言だけを表示すること", () => {
        useResumeStore.getState().setResume(cloneResume());
        useResumeStore.getState().setActiveSection("snsPlatform");

        renderWithProviders(<SnsPlatformSection />);

        expect(screen.getByText("一覧からSNSを選択してください。")).toBeInTheDocument();
        expect(screen.queryByRole("combobox", { name: /^プラットフォーム名/ })).not.toBeInTheDocument();
    });

    it("選ばれているSNSのプラットフォーム名とリンクを表示すること", () => {
        renderSection();

        expect(nameInput()).toHaveValue("GitHub");
        expect(linkInput()).toHaveValue("https://github.com/example");
    });

    it("プラットフォーム名を入力すると、選ばれているSNSに反映すること", () => {
        renderSection();

        fireEvent.change(nameInput(), { target: { value: "Git" } });

        expect(currentSnsPlatform()?.name).toBe("Git");
        expect(nameInput()).toHaveValue("Git");
        expect(useResumeStore.getState().resume?.snsPlatforms[0]).toEqual(otherSnsPlatform);
        expect(useResumeStore.getState().dirtyEntryIds.has("sns-1")).toBe(true);
    });

    it("プラットフォーム名の候補には、SNSのマスタを出すこと", async () => {
        const { user } = renderSection({ sns: { name: "" } });

        await user.click(nameInput());

        const optionNames = (await screen.findAllByRole("option")).map((option) => option.textContent);
        expect(optionNames).toEqual(["GitHub", "Zenn"]);
    });

    it("候補からプラットフォーム名を選ぶと、選ばれているSNSに反映すること", async () => {
        const { user } = renderSection({ sns: { name: "" } });

        await user.click(nameInput());
        await user.click(await screen.findByRole("option", { name: "Zenn" }));

        expect(currentSnsPlatform()?.name).toBe("Zenn");
        expect(nameInput()).toHaveValue("Zenn");
    });

    it("リンクを変更すると、選ばれているSNSに反映すること", () => {
        renderSection();

        fireEvent.change(linkInput(), { target: { value: "https://github.com/other" } });

        expect(currentSnsPlatform()?.link).toBe("https://github.com/other");
    });

    it("プラットフォーム名が既定の名前のときは、フォーカスで消すこと", () => {
        renderSection({ sns: { name: "新しいSNSプラットフォーム" } });

        fireEvent.focus(nameInput());

        expect(currentSnsPlatform()?.name).toBe("");
        expect(nameInput()).toHaveValue("");
    });

    it("候補を開くと、選んでいるプラットフォーム名を選択中として示し、ほかの候補も出すこと", async () => {
        const { user } = renderSection();

        await user.click(nameInput());

        const options = await screen.findAllByRole("option");
        expect(options.map((option) => option.textContent)).toEqual(["GitHub", "Zenn"]);
        expect(screen.getByRole("option", { name: "GitHub" })).toHaveAttribute("aria-selected", "true");
    });

    it("プラットフォーム名が既定の名前でないときは、フォーカスしても消さないこと", () => {
        renderSection();

        fireEvent.focus(nameInput());

        expect(currentSnsPlatform()?.name).toBe("GitHub");
        expect(useResumeStore.getState().dirtyEntryIds.has("sns-1")).toBe(false);
    });

    it("プラットフォーム名にエラーがあるときは、その欄だけをエラー表示にしてメッセージを出すこと", () => {
        renderSection({ errors: { name: ["プラットフォーム名のエラー"] } });

        expect(nameInput()).toHaveAttribute("aria-invalid", "true");
        expect(linkInput()).toHaveAttribute("aria-invalid", "false");
        expect(screen.getByText("プラットフォーム名のエラー")).toBeInTheDocument();
    });

    it("リンクにエラーがあるときは、リンクの欄だけをエラー表示にしてメッセージを出すこと", () => {
        renderSection({ errors: { link: ["リンクのエラー"] } });

        expect(linkInput()).toHaveAttribute("aria-invalid", "true");
        expect(nameInput()).toHaveAttribute("aria-invalid", "false");
        expect(screen.getByText("リンクのエラー")).toBeInTheDocument();
    });

    it("1つの欄に複数のエラーがあるときは、箇条書きでまとめて出すこと", () => {
        renderSection({ errors: { link: ["1つ目のエラー", "2つ目のエラー"] } });

        expect(screen.getByText("・ 1つ目のエラー ・ 2つ目のエラー")).toBeInTheDocument();
    });
});
