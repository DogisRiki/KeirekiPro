import { formatDate } from "@/utils";
import { describe, expect, it } from "vitest";

describe("formatDate", () => {
    it("空文字列の場合は空文字を返す", () => {
        expect(formatDate("")).toBe("");
    });

    it("有効な日付文字列をYYYY/MM形式で返す", () => {
        // ISO形式の日時文字列
        expect(formatDate("2025-07-15T00:00:00Z")).toBe("2025/07");
        // 短い日付形式
        expect(formatDate("1999-12-31")).toBe("1999/12");
        // 別タイムゾーンも考慮
        expect(formatDate("2000-01-01T12:34:56+09:00")).toBe("2000/01");
    });
});
