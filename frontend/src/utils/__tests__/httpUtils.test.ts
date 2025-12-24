import { extractFileName } from "@/utils";
import { describe, expect, it } from "vitest";

describe("httpUtils", () => {
    it("ダブルクォートで囲まれたファイル名を抽出できる", () => {
        const header = 'attachment; filename="resume.pdf"';
        expect(extractFileName(header)).toBe("resume.pdf");
    });

    it("クォートなしのファイル名を抽出できる", () => {
        const header = "attachment; filename=resume.pdf";
        expect(extractFileName(header)).toBe("resume.pdf");
    });

    it("日本語ファイル名を抽出できる", () => {
        const header = 'attachment; filename="職務経歴書.pdf"';
        expect(extractFileName(header)).toBe("職務経歴書.pdf");
    });

    it("undefinedの場合はnullを返す", () => {
        expect(extractFileName(undefined)).toBeNull();
    });

    it("空文字の場合はnullを返す", () => {
        expect(extractFileName("")).toBeNull();
    });

    it("filenameが含まれない場合はnullを返す", () => {
        const header = "attachment";
        expect(extractFileName(header)).toBeNull();
    });
});
