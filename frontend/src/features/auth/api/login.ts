import { publicApiClient } from "@/lib";
import { AxiosResponse } from "axios";

/**
 * ログインリクエスト
 */
export interface LoginPayload {
    email: string;
    password: string;
}

/**
 * ログインAPI
 */
export const login = (payload: LoginPayload): Promise<AxiosResponse<string>> =>
    publicApiClient.post("/auth/login", payload);
