import { CreateResumeForm, useCreateResume, useGetResumeList } from "@/features/resume";
import { useState } from "react";

/**
 * 職務経歴書新規作成コンテナ
 */
export const CreateResumeContainer = () => {
    const [resumeName, setResumeName] = useState("");
    const [copySourceId, setCopySourceId] = useState("");

    const createResumeMutation = useCreateResume();
    const { data } = useGetResumeList();

    /**
     * フォーム送信ハンドラ
     */
    const handleSubmit = () => {
        createResumeMutation.mutate({
            resumeName,
            resumeId: copySourceId || undefined,
        });
    };

    return (
        <CreateResumeForm
            resumeName={resumeName}
            copySourceId={copySourceId}
            copySourceOptions={data?.resumes ?? []}
            onResumeNameChange={setResumeName}
            onCopySourceChange={setCopySourceId}
            onSubmit={handleSubmit}
            loading={createResumeMutation.isPending}
        />
    );
};
