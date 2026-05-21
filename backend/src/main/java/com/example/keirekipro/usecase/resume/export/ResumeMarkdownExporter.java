package com.example.keirekipro.usecase.resume.export;

import com.example.keirekipro.domain.model.resume.Resume;

/**
 * Markdownエクスポート生成を抽象化する出力ポート
 */
public interface ResumeMarkdownExporter {

    /**
     * Markdownを生成する
     *
     * @param resume 職務経歴書
     * @return 生成結果
     */
    ExportedFile export(Resume resume);
}
