import { describe, expect, it } from "vitest";

import { getNestedValue, setNestedValue } from "@/utils";

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
