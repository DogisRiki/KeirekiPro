import { describe, expect, it } from "vitest";

import {
    dedupeIgnoreCase,
    getNestedValue,
    normalizeForCaseInsensitiveCompare,
    setNestedValue,
    stringListToBulletList,
} from "@/utils";

describe("getNestedValue", () => {
    const obj = {
        a: {
            b: {
                c: [1, 2, { d: "hello" }],
            },
        },
    };

    it("ネストされたプロパティの値を取得できること", () => {
        // 数値の配列を取得できること
        const arr = getNestedValue<typeof obj, number[]>(obj, ["a", "b", "c"]);
        expect(arr).toEqual([1, 2, { d: "hello" }]);

        // オブジェクト内のさらに深い文字列を取得できること
        const str = getNestedValue<typeof obj, string>(obj, ["a", "b", "c", "2", "d"]);
        expect(str).toBe("hello");
    });

    it("存在しないパスの場合 undefined を返すこと", () => {
        const missing = getNestedValue<typeof obj, unknown>(obj, ["a", "x", "y"]);
        expect(missing).toBeUndefined();
    });
});

describe("setNestedValue", () => {
    it("ネストされたプロパティの値を更新し、同じオブジェクトを返すこと", () => {
        const target = { a: { b: { c: 1 } } };
        const result = setNestedValue(target, ["a", "b", "c"], 42);

        // 戻り値が元のオブジェクトであること
        expect(result).toBe(target);

        // ネストされた値が更新されること
        expect(target.a.b.c).toBe(42);
    });

    it("新たに配列要素を上書きできること", () => {
        const target = { x: { y: [0, 1, 2] } };
        const result = setNestedValue(target, ["x", "y", "1"], 99);

        expect(result).toBe(target);
        expect(target.x.y).toEqual([0, 99, 2]);
    });
});

describe("stringListToBulletList", () => {
    it("空配列またはundefinedの場合は空文字を返す", () => {
        expect(stringListToBulletList(undefined)).toBe("");
        expect(stringListToBulletList([])).toBe("");
    });

    it("要素が1件の場合はそのまま返す", () => {
        expect(stringListToBulletList(["single message"])).toBe("single message");
    });

    it("複数要素の場合は先頭に「・ 」を付け改行でつなげて返す", () => {
        const input = ["first", "second", "third"];
        const expected = "・ first\n・ second\n・ third";
        expect(stringListToBulletList(input)).toBe(expected);
    });

    it("特殊文字や空文字を含む要素も正しく処理する", () => {
        const input = ["", "こんにちは", "error: ⚠️"];
        const expected = "・ \n・ こんにちは\n・ error: ⚠️";
        expect(stringListToBulletList(input)).toBe(expected);
    });
});

describe("dedupeIgnoreCase", () => {
    it("大文字小文字を無視して重複を取り除くこと", () => {
        const input = ["React", "react", "REACT", "Vue"];
        const result = dedupeIgnoreCase(input);
        expect(result).toEqual(["React", "Vue"]);
    });

    it("前後の空白をトリムして比較すること", () => {
        const input = ["  Go", "go  ", "GO"];
        const result = dedupeIgnoreCase(input);
        // 最初に出現したものを残す
        expect(result).toEqual(["Go"]);
    });

    it("空文字列は無視されること", () => {
        const input = ["TypeScript", "", "  ", "typescript"];
        const result = dedupeIgnoreCase(input);
        expect(result).toEqual(["TypeScript"]);
    });

    it("元の配列は破壊しないこと", () => {
        const input = ["A", "a"];
        const copy = [...input];

        const result = dedupeIgnoreCase(input);

        expect(input).toEqual(copy);
        expect(result).not.toBe(input);
    });
});

describe("normalizeForCaseInsensitiveCompare", () => {
    it("前後の空白を取り除き、小文字に変換すること", () => {
        expect(normalizeForCaseInsensitiveCompare("  React ")).toBe("react");
        expect(normalizeForCaseInsensitiveCompare("Go")).toBe("go");
    });

    it("すでに正規化されている文字列はそのまま返すこと", () => {
        expect(normalizeForCaseInsensitiveCompare("typescript")).toBe("typescript");
    });

    it("空白のみの文字列は空文字を返すこと", () => {
        expect(normalizeForCaseInsensitiveCompare("   ")).toBe("");
    });
});
