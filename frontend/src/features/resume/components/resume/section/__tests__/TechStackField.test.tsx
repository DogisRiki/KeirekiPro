import { TechStackField } from "@/features/resume";
import { renderWithProviders, resetStoresAndMocks } from "@/test";
import { screen } from "@testing-library/react";
import { vi } from "vitest";

const options = ["TypeScript", "React", "Vue.js"];

const renderField = (value: string[] | null = []) => {
    const onChange = vi.fn();
    const utils = renderWithProviders(
        <TechStackField label="フレームワーク" value={value} options={options} onChange={onChange} />,
    );
    return { onChange, ...utils };
};

const input = () => screen.getByRole("combobox", { name: "フレームワーク" });

describe("TechStackField", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
    });

    it("選んでいる値を表示すること", () => {
        renderField(["React", "Go"]);

        expect(screen.getByRole("button", { name: "React" })).toBeInTheDocument();
        expect(screen.getByRole("button", { name: "Go" })).toBeInTheDocument();
    });

    it("値が無いときは、何も選んでいない状態で表示し、入力した値を追加できること", async () => {
        const { user, onChange } = renderField(null);

        await user.type(input(), "Go{Enter}");

        expect(onChange).toHaveBeenCalledWith(["Go"]);
    });

    it("入力した値が候補と大文字小文字だけ違うときは、候補の正式名称で追加すること", async () => {
        const { user, onChange } = renderField(["React"]);

        await user.type(input(), "typescript{Enter}");

        expect(onChange).toHaveBeenCalledWith(["React", "TypeScript"]);
    });

    it("候補に無い値は、入力したとおりに追加すること", async () => {
        const { user, onChange } = renderField([]);

        await user.type(input(), "Svelte{Enter}");

        expect(onChange).toHaveBeenCalledWith(["Svelte"]);
    });

    it("値を変えたときは、既存の値も正式名称にそろえ、大文字小文字を無視して重複を除くこと", async () => {
        const { user, onChange } = renderField(["react", "React", "vue.js"]);

        await user.type(input(), "Go{Enter}");

        expect(onChange).toHaveBeenCalledWith(["React", "Vue.js", "Go"]);
    });

    it("候補の一覧には、選んでいる値を大文字小文字を無視して出さないこと", async () => {
        const { user } = renderField(["react"]);

        await user.click(input());

        const optionNames = screen.getAllByRole("option").map((option) => option.textContent);
        expect(optionNames).toEqual(["TypeScript", "Vue.js"]);
    });

    it("同じ値をEnterで足そうとしたときは、エラーを出して追加を止めること", async () => {
        const { user, onChange } = renderField(["React"]);

        await user.type(input(), " REACT {Enter}");

        expect(onChange).not.toHaveBeenCalled();
        expect(input()).toHaveAttribute("aria-invalid", "true");
        expect(screen.getByText("「React」")).toBeInTheDocument();
        expect(screen.getByText(/はすでに同一の値が入力されています。/)).toBeInTheDocument();
    });

    it("重複のエラーは、入力を変えたら消すこと", async () => {
        const { user, onChange } = renderField(["React"]);
        await user.type(input(), "react{Enter}");
        expect(screen.getByText(/はすでに同一の値が入力されています。/)).toBeInTheDocument();

        await user.type(input(), "{Backspace}");

        expect(screen.queryByText(/はすでに同一の値が入力されています。/)).not.toBeInTheDocument();
        expect(input()).toHaveAttribute("aria-invalid", "false");
        expect(onChange).not.toHaveBeenCalled();
    });

    it("Enter以外のキーでは、重複を確かめないこと", async () => {
        const { user } = renderField(["React"]);

        await user.type(input(), "React");
        await user.keyboard("{Tab}");

        expect(screen.queryByText(/はすでに同一の値が入力されています。/)).not.toBeInTheDocument();
    });

    it("空白だけを入力してEnterを押しても、重複を確かめないこと", async () => {
        // 既存の値に空白だけの値が混じっていても、空白だけの入力とは重複扱いにしない
        const { user } = renderField(["React", " "]);

        await user.type(input(), "   {Enter}");

        expect(screen.queryByText(/はすでに同一の値が入力されています。/)).not.toBeInTheDocument();
        expect(input()).toHaveAttribute("aria-invalid", "false");
    });
});
