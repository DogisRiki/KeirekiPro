import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * ログイン中の利用者の確認のメールを送るAPI
 * @returns Axiosレスポンス(204)
 */
export const sendEmailVerification = (): Promise<AxiosResponse<void>> =>
    protectedApiClient.post("/users/me/email-verification");
