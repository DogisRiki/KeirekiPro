import "axios";

/**
 * axiosの型定義を拡張
 */
declare module "axios" {
    export interface AxiosRequestConfig {
        skipAuthRefresh?: boolean;
    }
}
