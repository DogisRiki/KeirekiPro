package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.domain.service.resume.ResumeExportRuleCheckService;
import com.example.keirekipro.shared.utils.FileUtil;
import com.example.keirekipro.usecase.resume.dto.ExportResumeUseCaseDto;
import com.example.keirekipro.usecase.resume.export.ExportFormat;
import com.example.keirekipro.usecase.resume.export.ExportedFile;
import com.example.keirekipro.usecase.resume.export.ResumeExporter;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 職務経歴書エクスポートユースケース
 */
@Service
public class ExportResumeUseCase {

    private final ResumeRepository resumeRepository;

    private final ResumeExportRuleCheckService resumeExportRuleCheckService;

    private final ResumeExporter pdfExporter;

    private final ResumeExporter markdownExporter;

    /**
     * コンストラクタ
     */
    public ExportResumeUseCase(
            ResumeRepository resumeRepository,
            ResumeExportRuleCheckService resumeExportRuleCheckService,
            @Qualifier("thymeleafResumePdfExporter") ResumeExporter pdfExporter,
            @Qualifier("thymeleafResumeMarkdownExporter") ResumeExporter markdownExporter) {
        this.resumeRepository = resumeRepository;
        this.resumeExportRuleCheckService = resumeExportRuleCheckService;
        this.pdfExporter = pdfExporter;
        this.markdownExporter = markdownExporter;
    }

    /**
     * 職務経歴書をエクスポートする
     *
     * @param userId   ユーザーID
     * @param resumeId 職務経歴書ID
     * @param format   形式
     * @return エクスポート結果DTO
     */
    @Transactional(readOnly = true)
    public ExportResumeUseCaseDto execute(UUID userId, UUID resumeId, ExportFormat format) {

        Resume resume = resumeRepository.find(resumeId)
                .orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        // 所有者チェック
        if (!resume.getUserId().equals(userId)) {
            throw new UseCaseException("職務経歴書が存在しません。");
        }

        // エクスポート条件前提チェック
        resumeExportRuleCheckService.execute(resume);

        // フォーマットから実行するエクスポート処理を決定
        ExportedFile exported = switch (format) {
            case PDF -> pdfExporter.exportPdf(resume);
            case MARKDOWN -> markdownExporter.exportMarkdown(resume);
        };

        // ファイル名作成
        String baseName = FileUtil.sanitizeFileName(
                resume.getName() != null ? resume.getName().getValue() : null,
                "resume");
        String ext = format == ExportFormat.PDF ? ".pdf" : ".md";
        String fileName = baseName + ext;

        return new ExportResumeUseCaseDto(fileName, exported.getContentType(), exported.getContent());
    }
}
