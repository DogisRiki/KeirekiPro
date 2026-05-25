import { getResumeInfo } from "@/features/resume/api/getResumeInfo";
import { useResumeStore } from "@/features/resume/stores/resumeStore";
import type { Resume } from "@/features/resume/types";
import type { ErrorResponse } from "@/types";
import axios from "axios";

export const RESUME_NOT_FOUND_MESSAGE = "対象の職務経歴書データが存在しません。";

export type ResumeNotFoundHandler = (errorResponse?: ErrorResponse) => void | Promise<void>;

export const isResumeNotFoundError = (error: unknown): boolean => {
    return (
        axios.isAxiosError<ErrorResponse>(error) &&
        error.response?.status === 404 &&
        error.response.data?.message === RESUME_NOT_FOUND_MESSAGE
    );
};

export const isSectionNotFoundError = (error: unknown): boolean => {
    return (
        axios.isAxiosError<ErrorResponse>(error) &&
        error.response?.status === 404 &&
        error.response.data?.message !== RESUME_NOT_FOUND_MESSAGE
    );
};

export const syncResumeInfoFromServer = async (resumeId: string): Promise<Resume> => {
    const resume = await getResumeInfo(resumeId);
    useResumeStore.getState().syncResumeFromServer(resume);
    return resume;
};
