import { paths } from "@/config/paths";
import { matchPath } from "react-router";

/**
 * アクセス解析に送るページのパスを作る
 * パスワード再設定ページのパスに含まれるトークンは、固定の文字列に置き換える
 * @param pathname ページのパス(クエリ文字列とハッシュを含まない)
 * @returns アクセス解析に送るパス
 */
export const toAnalyticsPath = (pathname: string): string => {
    if (matchPath(paths.password.reset, pathname)) {
        return paths.password.reset;
    }
    return pathname;
};

/**
 * アクセス解析に送るページのURLを作る(クエリ文字列とハッシュを含まない)
 * @param origin ページのオリジン
 * @param pathname ページのパス
 * @returns アクセス解析に送るURL
 */
export const toAnalyticsLocation = (origin: string, pathname: string): string => origin + toAnalyticsPath(pathname);
