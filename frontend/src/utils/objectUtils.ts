/**
 * 配列で指定されたパスに基づいて、深くネストされたオブジェクトから値を取得する
 * @template T - オブジェクトの型
 * @template R - 返却値の型
 * @param {T} obj - 対象のオブジェクト
 * @param {string[]} path - オブジェクトのプロパティへのパスを表す文字列の配列
 * @returns {R} 指定されたパスの値
 * @example
 * const obj = { a: { b: { c: [1, 2, 3] } } };
 * getNestedValue<typeof obj, number[]>(obj, ['a', 'b', 'c']); // [1, 2, 3]
 */
export const getNestedValue = <T extends object, R>(obj: T, path: string[]): R => {
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
 * // { a: { b: { c: 2 } } }
 */
export const setNestedValue = (obj: any, path: string[], value: any) => {
    const lastKey = path[path.length - 1];
    const parentPath = path.slice(0, -1);
    const parent = parentPath.reduce((acc, key) => acc[key], obj);
    parent[lastKey] = value;
    return obj;
};
