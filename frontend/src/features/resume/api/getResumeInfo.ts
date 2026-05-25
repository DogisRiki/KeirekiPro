import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";

type ResumeArrays = Pick<
    Resume,
    "careers" | "projects" | "certifications" | "portfolios" | "snsPlatforms" | "selfPromotions"
>;

type ResumeInfoResponse = Omit<Resume, keyof ResumeArrays> & Partial<ResumeArrays>;

/**
 * 職務経歴書情報取得API
 * @param resumeId 職務経歴書ID
 * @returns 職務経歴書情報
 */
export const getResumeInfo = async (resumeId: string): Promise<Resume> => {
    const response = await protectedApiClient.get<ResumeInfoResponse>(`/resumes/${resumeId}`);
    const resume = response.data;

    return {
        ...resume,
        careers: resume.careers ?? [],
        projects: resume.projects ?? [],
        certifications: resume.certifications ?? [],
        portfolios: resume.portfolios ?? [],
        snsPlatforms: resume.snsPlatforms ?? [],
        selfPromotions: resume.selfPromotions ?? [],
    };
};
