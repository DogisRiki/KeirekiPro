/**
 * 配列で指定されたパスに基づいて、深くネストされたオブジェクトから値を取得する
 * @template T - オブジェクトの型
 * @template R - 返却値の型
 * @param {T} obj - 対象のオブジェクト
 * @param {readonly string[]} path - オブジェクトのプロパティへのパスを表す文字列の配列
 * @returns {R} 指定されたパスの値
 * @example
 * const obj = { a: { b: { c: [1, 2, 3] } } };
 * getNestedValue<typeof obj, number[]>(obj, ['a', 'b', 'c']); // [1, 2, 3]
 */
export const getNestedValue = <T extends object, R>(obj: T, path: readonly string[]): R => {
    const value = path.reduce((acc: any, key) => acc?.[key], obj);
    return value;
};

/**
 * 配列で指定されたパスに基づいて、深くネストされたオブジェクトの値を設定する
 * @param obj 更新対象のオブジェクト
 * @param path 設定したい値へのパスを表す文字列の配列
 * @param value 設定する値
 * @returns 更新されたオブジェクト
 * @example
 * const obj = { a: { b: { c: 1 } } };
 * setNestedValue(obj, ['a', 'b', 'c'], 2);
 */
export const setNestedValue = (obj: any, path: readonly string[], value: any) => {
    const lastKey = path[path.length - 1];
    const parentPath = path.slice(0, -1);
    const parent = parentPath.reduce((acc, key) => acc[key], obj);
    parent[lastKey] = value;
    return obj;
};

/**
 * 文字列の配列を「・」区切りの箇条書きテキストに変換する
 * - 引数がundefinedまたは長さ0の場合は空文字を返す
 * - 配列の要素が1件のみの場合は、その要素をそのまま返す
 * - 配列の要素が複数件ある場合は、先頭に「・」を付けて改行で連結した文字列を返す
 * @param items - 文字列の配列
 * @returns 「・」付き箇条書き形式に変換された文字列
 */
export const stringListToBulletList = (items?: readonly string[]): string => {
    if (!items || items.length === 0) {
        return "";
    }
    if (items.length === 1) {
        return items[0];
    }
    return items.map((item) => `・ ${item}`).join("\n");
};

/**
 * 文字列配列から、大文字小文字を無視して重複を取り除く
 * - 各要素は前後の空白をトリムして比較する
 * - 最初に出現した要素を優先して残す
 * - 空文字列は無視する
 *
 * @param values 重複除去の対象となる文字列配列
 * @returns 大文字小文字を無視して重複を取り除いた新しい配列
 */
export const dedupeIgnoreCase = (values: readonly string[]): string[] => {
    const seen = new Set<string>();
    const result: string[] = [];

    for (const raw of values) {
        const trimmed = raw.trim();
        if (!trimmed) {
            continue;
        }
        const key = trimmed.toLowerCase();
        if (seen.has(key)) {
            continue;
        }
        seen.add(key);
        result.push(trimmed);
    }

    return result;
};

/**
 * 大文字小文字を無視した比較のために文字列を正規化する
 * - 前後の空白をトリムする
 * - 小文字に変換する
 *
 * @param value 正規化対象の文字列
 * @returns 比較用に正規化された文字列
 */
export const normalizeForCaseInsensitiveCompare = (value: string): string => {
    return value.trim().toLowerCase();
};
