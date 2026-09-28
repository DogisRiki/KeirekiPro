import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { get: vi.fn() },
}));

import type { Certification } from "@/features/resume";
import { CertificationSection, useResumeStore } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { createAxiosResponse, renderWithProviders, resetStoresAndMocks } from "@/test";
import { fireEvent, screen } from "@testing-library/react";

import { cloneResume } from "../../../__tests__/resumeTestData";

type FieldErrors = Record<string, string[]>;

const otherCertification: Certification = { id: "certification-2", name: "TOEIC", date: "2018-06" };

/** 資格を2件持ち、そのうち1件を選んだ状態で描画する */
const renderSection = ({
    certification = {},
    errors,
}: { certification?: Partial<Certification>; errors?: FieldErrors } = {}) => {
    const store = useResumeStore.getState();
    store.setResume(
        cloneResume({
            certifications: [
                otherCertification,
                { id: "certification-1", name: "基本情報技術者", date: "2020-04", ...certification },
            ],
        }),
    );
    store.setActiveSection("certification");
    store.setActiveEntryId("certification-1");
    if (errors) {
        store.setEntryErrors("certification-1", errors);
    }
    return renderWithProviders(<CertificationSection />);
};

const currentCertification = () =>
    useResumeStore.getState().resume?.certifications.find((certification) => certification.id === "certification-1");

const nameInput = () => screen.getByRole("combobox", { name: /^資格名/ });

const dateGroup = () => screen.getByRole("group", { name: /^取得年月/ });

describe("CertificationSection", () => {
    beforeEach(() => {
        resetStoresAndMocks([() => vi.mocked(protectedApiClient.get).mockReset()]);
        vi.mocked(protectedApiClient.get).mockResolvedValue(
            createAxiosResponse({ names: ["基本情報技術者", "応用情報技術者"] }),
        );
    });

    it("資格が選ばれていないときは、選択を促す文言だけを表示すること", () => {
        useResumeStore.getState().setResume(cloneResume());
        useResumeStore.getState().setActiveSection("certification");

        renderWithProviders(<CertificationSection />);

        expect(screen.getByText("一覧から資格を選択してください。")).toBeInTheDocument();
        expect(screen.queryByRole("combobox", { name: /^資格名/ })).not.toBeInTheDocument();
    });

    it("選ばれている資格の資格名と取得年月を表示すること", () => {
        renderSection();

        expect(nameInput()).toHaveValue("基本情報技術者");
        expect(dateGroup()).toHaveTextContent("2020/04");
    });

    it("資格名を入力すると、選ばれている資格に反映すること", () => {
        renderSection();

        fireEvent.change(nameInput(), { target: { value: "応用" } });

        expect(currentCertification()?.name).toBe("応用");
        expect(nameInput()).toHaveValue("応用");
        expect(useResumeStore.getState().resume?.certifications[0]).toEqual(otherCertification);
        expect(useResumeStore.getState().dirtyEntryIds.has("certification-1")).toBe(true);
    });

    it("資格名の候補には、資格のマスタを出すこと", async () => {
        const { user } = renderSection({ certification: { name: "" } });

        await user.click(nameInput());

        const optionNames = (await screen.findAllByRole("option")).map((option) => option.textContent);
        expect(optionNames).toEqual(["基本情報技術者", "応用情報技術者"]);
    });

    it("候補から資格名を選ぶと、選ばれている資格に反映すること", async () => {
        const { user } = renderSection({ certification: { name: "" } });

        await user.click(nameInput());
        await user.click(await screen.findByRole("option", { name: "応用情報技術者" }));

        expect(currentCertification()?.name).toBe("応用情報技術者");
        expect(nameInput()).toHaveValue("応用情報技術者");
    });

    it("資格名が既定の名前のときは、フォーカスで消すこと", () => {
        renderSection({ certification: { name: "新しい資格" } });

        fireEvent.focus(nameInput());

        expect(currentCertification()?.name).toBe("");
        expect(nameInput()).toHaveValue("");
    });

    it("候補を開くと、選んでいる資格名を選択中として示し、ほかの候補も出すこと", async () => {
        const { user } = renderSection();

        await user.click(nameInput());

        const options = await screen.findAllByRole("option");
        expect(options.map((option) => option.textContent)).toEqual(["基本情報技術者", "応用情報技術者"]);
        expect(screen.getByRole("option", { name: "基本情報技術者" })).toHaveAttribute("aria-selected", "true");
    });

    it("資格名が既定の名前でないときは、フォーカスしても消さないこと", () => {
        renderSection();

        fireEvent.focus(nameInput());

        expect(currentCertification()?.name).toBe("基本情報技術者");
        expect(useResumeStore.getState().dirtyEntryIds.has("certification-1")).toBe(false);
    });

    it("取得年月を選ぶと、年月の形式でストアに反映すること", async () => {
        const { user } = renderSection();

        await user.click(dateGroup());
        fireEvent.click(await screen.findByRole("radio", { name: "2019" }));
        fireEvent.click(await screen.findByRole("radio", { name: "October" }));

        expect(currentCertification()?.date).toBe("2019-10");
    });

    it("資格名にエラーがあるときは、資格名の欄だけをエラー表示にしてメッセージを出すこと", () => {
        renderSection({ errors: { name: ["資格名のエラー"] } });

        expect(nameInput()).toHaveAttribute("aria-invalid", "true");
        expect(dateGroup()).toHaveAttribute("aria-invalid", "false");
        expect(screen.getByText("資格名のエラー")).toBeInTheDocument();
    });

    it("取得年月にエラーがあるときは、取得年月の欄だけをエラー表示にしてメッセージを出すこと", () => {
        renderSection({ errors: { date: ["取得年月のエラー"] } });

        expect(dateGroup()).toHaveAttribute("aria-invalid", "true");
        expect(nameInput()).toHaveAttribute("aria-invalid", "false");
        expect(screen.getByText("取得年月のエラー")).toBeInTheDocument();
    });

    it("1つの欄に複数のエラーがあるときは、箇条書きでまとめて出すこと", () => {
        renderSection({ errors: { name: ["1つ目のエラー", "2つ目のエラー"] } });

        expect(screen.getByText("・ 1つ目のエラー ・ 2つ目のエラー")).toBeInTheDocument();
    });
});
