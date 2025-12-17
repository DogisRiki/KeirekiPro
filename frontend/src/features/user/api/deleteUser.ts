import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * ユーザー退会API
 * @returns Axiosレスポンス
 */
export const deleteUser = (): Promise<AxiosResponse<void>> => protectedApiClient.delete("/users/me");
