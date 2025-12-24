/**
 * Content-Dispositionヘッダーからファイル名を抽出する
 * @param contentDisposition Content-Dispositionヘッダーの値
 * @returns ファイル名（取得できない場合はnull）
 */
export const extractFileName = (contentDisposition: string | undefined): string | null => {
    if (!contentDisposition) return null;
    const matches = contentDisposition.match(/filename="?([^";\n]+)"?/);
    return matches?.[1] ?? null;
};
