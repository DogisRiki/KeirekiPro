import type { ResumePdfSettings } from "@/features/resume";
import { ResumePdfPreviewModal } from "@/features/resume";
import { renderWithProviders, resetStoresAndMocks } from "@/test";
import { fireEvent, screen } from "@testing-library/react";
import { useState } from "react";
import { vi } from "vitest";

const baseSettings: ResumePdfSettings = {
    fontFamily: "NotoSansJP",
    fontSizes: { title: 16, date: 10, fullName: 10, sectionHeading: 11.5 },
    tableHeaderColor: { hex: "336699" },
};

const createHandlers = () => ({
    onSettingsChange: vi.fn<(settings: ResumePdfSettings) => void>(),
    onRefresh: vi.fn(),
    onReset: vi.fn(),
    onExport: vi.fn(),
    onClose: vi.fn(),
});

const renderModal = ({
    settings = baseSettings,
    previewUrl = "blob:preview",
    open = true,
}: { settings?: ResumePdfSettings; previewUrl?: string | null; open?: boolean } = {}) => {
    const handlers = createHandlers();
    const utils = renderWithProviders(
        <ResumePdfPreviewModal open={open} previewUrl={previewUrl} settings={settings} {...handlers} />,
    );
    return { ...handlers, ...utils };
};

const hexInput = () => screen.getByRole("textbox", { name: "カラーコード" });

const rgbInput = (key: "R" | "G" | "B") => screen.getByRole("spinbutton", { name: key });

const fontSizeInput = (label: string) => screen.getByRole("combobox", { name: label });

describe("ResumePdfPreviewModal", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
    });

    it("閉じているときは、何も表示しないこと", () => {
        renderModal({ open: false });

        expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    });

    it("プレビューのURLに表示の指定を付けて、PDFを表示すること", () => {
        renderModal({ previewUrl: "blob:preview-1" });

        expect(screen.getByTitle("PDFプレビュー")).toHaveAttribute(
            "src",
            "blob:preview-1#toolbar=1&navpanes=0&zoom=100",
        );
    });

    it("プレビューのURLが無いときは、PDFを表示しないこと", () => {
        renderModal({ previewUrl: null });

        expect(screen.queryByTitle("PDFプレビュー")).not.toBeInTheDocument();
    });

    it("今の設定を各欄に表示すること", () => {
        renderModal();

        expect(screen.getByRole("combobox", { name: "フォント" })).toHaveTextContent("ゴシック系（Noto Sans JP）");
        expect(fontSizeInput("タイトルフォントサイズ")).toHaveValue("16");
        expect(fontSizeInput("日付フォントサイズ")).toHaveValue("10");
        expect(fontSizeInput("氏名フォントサイズ")).toHaveValue("10");
        expect(fontSizeInput("セクション見出しフォントサイズ")).toHaveValue("11.5");
        expect(hexInput()).toHaveValue("336699");
        expect(rgbInput("R")).toHaveValue(51);
        expect(rgbInput("G")).toHaveValue(102);
        expect(rgbInput("B")).toHaveValue(153);
    });

    it("明朝系のフォントが設定されているときは、明朝系を選んだ状態で表示すること", () => {
        renderModal({ settings: { ...baseSettings, fontFamily: "NotoSerifJP" } });

        expect(screen.getByRole("combobox", { name: "フォント" })).toHaveTextContent("明朝系（Noto Serif JP）");
    });

    it("表ヘッダー色がRGBだけで指定されているときは、カラーコードに直して表示すること", () => {
        renderModal({ settings: { ...baseSettings, tableHeaderColor: { rgb: { r: 255, g: 0, b: 16 } } } });

        expect(hexInput()).toHaveValue("ff0010");
        expect(rgbInput("R")).toHaveValue(255);
    });

    it("表ヘッダー色の指定が無いときは、薄い灰色(d9d9d9)を表示すること", () => {
        renderModal({ settings: { ...baseSettings, tableHeaderColor: {} } });

        expect(hexInput()).toHaveValue("d9d9d9");
        expect(rgbInput("R")).toHaveValue(217);
        expect(rgbInput("G")).toHaveValue(217);
        expect(rgbInput("B")).toHaveValue(217);
    });

    it("フォントを選ぶと、ほかの設定を残したままフォントを変えること", async () => {
        const { user, onSettingsChange } = renderModal();

        await user.click(screen.getByRole("combobox", { name: "フォント" }));
        await user.click(screen.getByRole("option", { name: "明朝系（Noto Serif JP）" }));

        expect(onSettingsChange).toHaveBeenCalledWith({ ...baseSettings, fontFamily: "NotoSerifJP" });
    });

    it("フォントサイズを候補から選ぶと、ほかの設定を残したままその項目だけを変えること", async () => {
        const { user, onSettingsChange } = renderModal();

        await user.click(fontSizeInput("日付フォントサイズ"));
        await user.click(screen.getByRole("option", { name: "12" }));

        expect(onSettingsChange).toHaveBeenLastCalledWith({
            ...baseSettings,
            fontSizes: { ...baseSettings.fontSizes, date: 12 },
        });
    });

    it("フォントサイズを入力してEnterを押すと、数値にして反映すること", async () => {
        const { user, onSettingsChange } = renderModal();

        await user.clear(fontSizeInput("タイトルフォントサイズ"));
        await user.type(fontSizeInput("タイトルフォントサイズ"), "13.5{Enter}");

        expect(onSettingsChange).toHaveBeenCalledWith({
            ...baseSettings,
            fontSizes: { ...baseSettings.fontSizes, title: 13.5 },
        });
        expect(onSettingsChange.mock.calls.every(([settings]) => settings.fontSizes.title === 13.5)).toBe(true);
    });

    it("フォントサイズを入力して欄を離れると、数値にして反映すること", async () => {
        const { user, onSettingsChange } = renderModal();

        await user.clear(fontSizeInput("氏名フォントサイズ"));
        await user.type(fontSizeInput("氏名フォントサイズ"), "9");
        fireEvent.blur(fontSizeInput("氏名フォントサイズ"));

        expect(onSettingsChange).toHaveBeenLastCalledWith({
            ...baseSettings,
            fontSizes: { ...baseSettings.fontSizes, fullName: 9 },
        });
    });

    it("フォントサイズの入力が空のときは、設定を変えないこと", async () => {
        const { user, onSettingsChange } = renderModal();

        await user.clear(fontSizeInput("タイトルフォントサイズ"));
        fireEvent.blur(fontSizeInput("タイトルフォントサイズ"));

        expect(onSettingsChange).not.toHaveBeenCalled();
    });

    it("フォントサイズの入力が数値でないときは、設定を変えないこと", async () => {
        const { user, onSettingsChange } = renderModal();

        await user.clear(fontSizeInput("タイトルフォントサイズ"));
        await user.type(fontSizeInput("タイトルフォントサイズ"), "abc{Enter}");
        fireEvent.blur(fontSizeInput("タイトルフォントサイズ"));

        expect(onSettingsChange).not.toHaveBeenCalled();
    });

    it("Enter以外のキーでは、フォントサイズを反映しないこと", async () => {
        const { user, onSettingsChange } = renderModal();

        await user.clear(fontSizeInput("タイトルフォントサイズ"));
        await user.type(fontSizeInput("タイトルフォントサイズ"), "20");

        expect(onSettingsChange).not.toHaveBeenCalled();
    });

    it("カラーコードは、記号と16進数以外の文字を除き、小文字にして反映すること", () => {
        const { onSettingsChange } = renderModal();

        fireEvent.change(hexInput(), { target: { value: "#AbC-1z23" } });

        expect(onSettingsChange).toHaveBeenCalledWith({ ...baseSettings, tableHeaderColor: { hex: "abc123" } });
    });

    it("カラーコードは、7文字目以降を捨てて反映すること", () => {
        const { onSettingsChange } = renderModal();

        fireEvent.change(hexInput(), { target: { value: "1234567" } });

        expect(onSettingsChange).toHaveBeenCalledWith({ ...baseSettings, tableHeaderColor: { hex: "123456" } });
    });

    it("カラーコードが6桁そろうまでは、入力中の値を表示するだけで反映しないこと", () => {
        const { onSettingsChange } = renderModal();

        fireEvent.change(hexInput(), { target: { value: "12a" } });

        expect(onSettingsChange).not.toHaveBeenCalled();
        expect(hexInput()).toHaveValue("12a");
        expect(rgbInput("R")).toHaveValue(51);
    });

    it("入力中のカラーコードがあっても、設定の色が変わったら新しい色を表示すること", () => {
        // 親が設定を持ち、変更を受け取ったら反映する
        const Harness = () => {
            const [settings, setSettings] = useState(baseSettings);
            return (
                <ResumePdfPreviewModal
                    {...createHandlers()}
                    open
                    previewUrl={null}
                    settings={settings}
                    onSettingsChange={setSettings}
                />
            );
        };
        renderWithProviders(<Harness />);
        fireEvent.change(hexInput(), { target: { value: "12a" } });
        expect(hexInput()).toHaveValue("12a");

        fireEvent.change(rgbInput("G"), { target: { value: "255" } });

        expect(hexInput()).toHaveValue("33ff99");
    });

    it("RGBを変えると、ほかの色の値を残したカラーコードにして反映すること", () => {
        const { onSettingsChange } = renderModal();

        fireEvent.change(rgbInput("G"), { target: { value: "255" } });

        expect(onSettingsChange).toHaveBeenCalledWith({ ...baseSettings, tableHeaderColor: { hex: "33ff99" } });
    });

    it.each(["0", "255"])("RGBが範囲の端(%s)のときも反映すること", (value) => {
        const { onSettingsChange } = renderModal();

        fireEvent.change(rgbInput("R"), { target: { value } });

        expect(onSettingsChange).toHaveBeenCalledTimes(1);
    });

    it.each(["-1", "256", "1.5"])("RGBが0〜255の整数でない(%s)ときは、設定を変えないこと", (value) => {
        const { onSettingsChange } = renderModal();

        fireEvent.change(rgbInput("B"), { target: { value } });

        expect(onSettingsChange).not.toHaveBeenCalled();
    });

    it("カラーピッカーで色を変えると、カラーコードにして反映すること", () => {
        const { onSettingsChange } = renderModal({
            settings: { ...baseSettings, tableHeaderColor: { hex: "ff0000" } },
        });

        fireEvent.keyDown(screen.getByRole("slider", { name: "Hue" }), { key: "ArrowRight", keyCode: 39 });

        expect(onSettingsChange).toHaveBeenCalledTimes(1);
        const [settings] = onSettingsChange.mock.calls[0];
        expect(settings.fontSizes).toEqual(baseSettings.fontSizes);
        expect(settings.tableHeaderColor.hex).toMatch(/^[0-9a-f]{6}$/);
        expect(settings.tableHeaderColor.hex).not.toBe("ff0000");
    });

    it.each([
        ["プレビュー更新", "onRefresh"],
        ["設定値リセット", "onReset"],
        ["エクスポート", "onExport"],
        ["とじる", "onClose"],
        ["PDFプレビューを閉じる", "onClose"],
    ] as const)("%s を押すと、%s を呼ぶこと", async (name, handler) => {
        const view = renderModal();

        await view.user.click(screen.getByRole("button", { name }));

        expect(view[handler]).toHaveBeenCalledTimes(1);
        expect(view.onSettingsChange).not.toHaveBeenCalled();
    });
});
