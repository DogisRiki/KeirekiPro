package com.example.keirekipro.usecase.resume.export;

import com.example.keirekipro.domain.model.resume.Resume;

/**
 * PDFエクスポート生成を抽象化する出力ポート
 */
public interface ResumePdfExporter {

    /**
     * PDFを生成する
     *
     * @param resume 職務経歴書
     * @param settings PDFエクスポート設定
     * @return 生成結果
     */
    ExportedFile export(Resume resume, ResumePdfExportSettings settings);
}
