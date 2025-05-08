import { baseApiClient } from "@/lib";
import axios from "axios";

/**
 * 認証が不要なAPI通信に使用するクライアント
 */
export const publicApiClient = axios.create({
    ...baseApiClient.defaults,
    withCredentials: true,
});
