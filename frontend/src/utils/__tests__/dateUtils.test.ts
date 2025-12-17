import { formatDate, formatDateTimeJa } from "@/utils";
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

describe("formatDateTimeJa", () => {
    it("空文字列の場合は空文字を返す", () => {
        expect(formatDateTimeJa("")).toBe("");
    });

    it("有効な日時文字列を「YYYY年M月D日 H:mm:ss」形式で返す（分秒は0埋め）", () => {
        expect(formatDateTimeJa("2025-12-16T06:04:32")).toBe("2025年12月16日 6:04:32");
        expect(formatDateTimeJa("2025-12-16T06:00:02")).toBe("2025年12月16日 6:00:02");
    });

    it("小数秒がミリ秒(3桁)を超える場合でも正しく整形する", () => {
        expect(formatDateTimeJa("2025-12-16T06:04:32.407708")).toBe("2025年12月16日 6:04:32");
    });

    it("不正な日付文字列の場合は空文字を返す", () => {
        expect(formatDateTimeJa("invalid-date")).toBe("");
    });
});
