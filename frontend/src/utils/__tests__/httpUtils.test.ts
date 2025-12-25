import { extractFileName } from "@/utils";
import { describe, expect, it } from "vitest";

describe("httpUtils", () => {
    it("filename*（RFC 5987形式）のファイル名を抽出できる（URLデコードあり）", () => {
        const header = "attachment; filename*=UTF-8''resume%20file.pdf";
        expect(extractFileName(header)).toBe("resume file.pdf");
    });

    it("filename* がある場合は filename より優先して抽出できる", () => {
        const header = "attachment; filename=\"fallback.pdf\"; filename*=UTF-8''resume%20file.pdf";
        expect(extractFileName(header)).toBe("resume file.pdf");
    });

    it("ダブルクォートで囲まれたファイル名を抽出できる", () => {
        const header = 'attachment; filename="resume.pdf"';
        expect(extractFileName(header)).toBe("resume.pdf");
    });

    it("クォートなしのファイル名を抽出できる", () => {
        const header = "attachment; filename=resume.pdf";
        expect(extractFileName(header)).toBe("resume.pdf");
    });

    it("日本語ファイル名を抽出できる（filename）", () => {
        const header = 'attachment; filename="職務経歴書.pdf"';
        expect(extractFileName(header)).toBe("職務経歴書.pdf");
    });

    it("日本語ファイル名を抽出できる（filename*）", () => {
        const header = "attachment; filename*=UTF-8''%E8%81%B7%E5%8B%99%E7%B5%8C%E6%AD%B4%E6%9B%B8.pdf";
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
