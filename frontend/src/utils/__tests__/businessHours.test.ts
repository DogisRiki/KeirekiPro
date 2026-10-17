import { isBusinessHours } from "@/utils";
import { describe, expect, it } from "vitest";

describe("isBusinessHours", () => {
    it("月曜 7:59 は時間外、8:00 は営業時間", () => {
        expect(isBusinessHours(new Date("2026-10-19T07:59:00+09:00"))).toBe(false);
        expect(isBusinessHours(new Date("2026-10-19T08:00:00+09:00"))).toBe(true);
    });

    it("金曜 19:59 は営業時間、20:00 は時間外", () => {
        expect(isBusinessHours(new Date("2026-10-16T19:59:00+09:00"))).toBe(true);
        expect(isBusinessHours(new Date("2026-10-16T20:00:00+09:00"))).toBe(false);
    });

    it("日本時間の月曜 8:00(UTC の日曜 23:00)を営業時間と判定する", () => {
        const now = new Date("2026-10-19T08:00:00+09:00");
        // 前提: UTC では日曜 23:00 にあたる
        expect(now.getUTCDay()).toBe(0);
        expect(now.getUTCHours()).toBe(23);

        expect(isBusinessHours(now)).toBe(true);
    });

    it("土曜と日曜の昼は時間外", () => {
        expect(isBusinessHours(new Date("2026-10-17T12:00:00+09:00"))).toBe(false);
        expect(isBusinessHours(new Date("2026-10-18T12:00:00+09:00"))).toBe(false);
    });

    it("祝日の平日の昼も営業時間", () => {
        // 2026-10-12 はスポーツの日(月曜の祝日)
        expect(isBusinessHours(new Date("2026-10-12T12:00:00+09:00"))).toBe(true);
    });
});
