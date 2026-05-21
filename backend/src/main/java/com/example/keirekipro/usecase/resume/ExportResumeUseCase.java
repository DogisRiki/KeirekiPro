package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.domain.service.resume.ResumeExportRuleCheckService;
import com.example.keirekipro.shared.utils.FileUtil;
import com.example.keirekipro.usecase.resume.dto.ExportResumeCommand;
import com.example.keirekipro.usecase.resume.dto.ExportResumeUseCaseDto;
import com.example.keirekipro.usecase.resume.export.ExportFormat;
import com.example.keirekipro.usecase.resume.export.ExportedFile;
import com.example.keirekipro.usecase.resume.export.ResumeMarkdownExporter;
import com.example.keirekipro.usecase.resume.export.ResumePdfExportSettings;
import com.example.keirekipro.usecase.resume.export.ResumePdfExporter;
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

    private final ResumePdfExporter pdfExporter;

    private final ResumeMarkdownExporter markdownExporter;

    /**
     * コンストラクタ
     */
    public ExportResumeUseCase(
            ResumeRepository resumeRepository,
            ResumeExportRuleCheckService resumeExportRuleCheckService,
            @Qualifier("thymeleafResumePdfExporter") ResumePdfExporter pdfExporter,
            @Qualifier("thymeleafResumeMarkdownExporter") ResumeMarkdownExporter markdownExporter) {
        this.resumeRepository = resumeRepository;
        this.resumeExportRuleCheckService = resumeExportRuleCheckService;
        this.pdfExporter = pdfExporter;
        this.markdownExporter = markdownExporter;
    }

    /**
     * 職務経歴書をエクスポートする
     *
     * @param userId ユーザーID
     * @param resumeId 職務経歴書ID
     * @param format 形式
     * @return エクスポート結果DTO
     */
    @Transactional(readOnly = true)
    public ExportResumeUseCaseDto execute(UUID userId, UUID resumeId, ExportFormat format) {
        ExportResumeCommand command = new ExportResumeCommand(
                format,
                ExportResumeCommand.ExportDisposition.ATTACHMENT,
                null);
        return execute(userId, resumeId, command);
    }

    /**
     * 職務経歴書をエクスポートする
     *
     * @param userId ユーザーID
     * @param resumeId 職務経歴書ID
     * @param command エクスポートコマンド
     * @return エクスポート結果DTO
     */
    @Transactional(readOnly = true)
    public ExportResumeUseCaseDto execute(UUID userId, UUID resumeId, ExportResumeCommand command) {

        Resume resume = resumeRepository.find(resumeId)
                .orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        // 所有者チェック
        if (!resume.getUserId().equals(userId)) {
            throw new UseCaseException("職務経歴書が存在しません。");
        }

        // エクスポート条件前提チェック
        var errors = resumeExportRuleCheckService.execute(resume);
        if (!errors.isEmpty()) {
            String message = command.isPreview()
                    ? "入力エラーがあるため、PDFプレビューを表示できません。"
                    : "職務経歴書をエクスポートできません。";
            throw new UseCaseException(message + "\n- " + String.join("\n- ", errors));
        }

        // フォーマットから実行するエクスポート処理を決定
        ExportedFile exported = switch (command.getFormat()) {
            case PDF -> pdfExporter.export(resume, buildPdfSettings(command));
            case MARKDOWN -> markdownExporter.export(resume);
        };

        // ファイル名作成
        String baseName = FileUtil.sanitizeFileName(
                resume.getName() != null ? resume.getName().getValue() : null,
                "resume");
        String ext = command.getFormat() == ExportFormat.PDF ? ".pdf" : ".md";
        String fileName = baseName + ext;

        return new ExportResumeUseCaseDto(fileName, exported.getContentType(), exported.getContent());
    }

    private ResumePdfExportSettings buildPdfSettings(ExportResumeCommand command) {
        if (command.getPdfSettings() == null) {
            return ResumePdfExportSettings.defaults();
        }

        ExportResumeCommand.PdfSettings pdfSettings = command.getPdfSettings();
        try {
            return ResumePdfExportSettings.normalize(
                    pdfSettings.fontFamily(),
                    pdfSettings.titleFontSize(),
                    pdfSettings.dateFontSize(),
                    pdfSettings.fullNameFontSize(),
                    pdfSettings.sectionHeadingFontSize(),
                    pdfSettings.tableHeaderColor());
        } catch (IllegalArgumentException e) {
            throw new UseCaseException(e.getMessage());
        }
    }
}
