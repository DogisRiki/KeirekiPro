/**
 * Content-Dispositionヘッダーからファイル名を抽出する
 * @param contentDisposition Content-Dispositionヘッダーの値
 * @returns ファイル名（取得できない場合はnull）
 */
export const extractFileName = (contentDisposition: string | undefined): string | null => {
    if (!contentDisposition) return null;

    const filenameStar = contentDisposition.match(/filename\*\s*=\s*UTF-8''([^;]+)/i);
    if (filenameStar?.[1]) {
        try {
            return decodeURIComponent(filenameStar[1]);
        } catch {
            return filenameStar[1];
        }
    }

    const filename = contentDisposition.match(/filename="?([^";\n]+)"?/i);
    return filename?.[1] ?? null;
};
