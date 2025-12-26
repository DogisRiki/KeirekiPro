package com.example.keirekipro.usecase.resume.export;

import com.example.keirekipro.domain.model.resume.Resume;

/**
 * エクスポート生成を抽象化する出力ポート
 */
public interface ResumeExporter {

    /**
     * PDFを生成する
     *
     * @param resume 職務経歴書
     * @return 生成結果
     */
    ExportedFile exportPdf(Resume resume);

    /**
     * Markdownを生成する
     *
     * @param resume 職務経歴書
     * @return 生成結果
     */
    ExportedFile exportMarkdown(Resume resume);
}
