package com.example.keirekipro.usecase.resume;

import java.util.List;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.Certification;
import com.example.keirekipro.domain.model.resume.Portfolio;
import com.example.keirekipro.domain.model.resume.Project;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.model.resume.SelfPromotion;
import com.example.keirekipro.domain.model.resume.SnsPlatform;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.domain.service.resume.ResumeNameDuplicationCheckService;
import com.example.keirekipro.presentation.resume.dto.CreateResumeRequest;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.resume.policy.ResumeLimitChecker;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書コピーして新規作成ユースケース
 */
@Service
@RequiredArgsConstructor
public class CopyCreateResumeUseCase {

    private final ResumeRepository resumeRepository;

    private final ResumeNameDuplicationCheckService resumeNameDuplicationCheckService;

    private final ResumeLimitChecker resumeLimitChecker;

    /**
     * 職務経歴書コピーして新規作成ユースケースを実行する
     *
     * @param userId  ユーザーID
     * @param request リクエスト
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, CreateResumeRequest request) {

        // 上限チェック
        resumeLimitChecker.checkResumeCreateAllowed(userId);

        ErrorCollector errorCollector = new ErrorCollector();

        // 職務経歴書名の重複チェック
        ResumeName resumeName = ResumeName.create(errorCollector, request.getResumeName());
        resumeNameDuplicationCheckService.execute(userId, resumeName);

        // コピー元を取得
        Resume source = resumeRepository.find(request.getResumeId())
                .orElseThrow(() -> new UseCaseException("コピー元の職務経歴書が存在しません。"));

        // 所有者チェック（他人の職務経歴書をコピーしようとした場合）
        if (!source.getUserId().equals(userId)) {
            throw new UseCaseException("コピー元の職務経歴書が存在しません。");
        }

        // 職歴
        List<Career> copiedCareers = source.getCareers().stream()
                .map(career -> Career.create(
                        errorCollector,
                        career.getCompanyName(),
                        career.getPeriod()))
                .toList();

        // プロジェクト
        List<Project> copiedProjects = source.getProjects().stream()
                .map(project -> Project.create(
                        errorCollector,
                        project.getCompanyName(),
                        project.getPeriod(),
                        project.getName(),
                        project.getOverview(),
                        project.getTeamComp(),
                        project.getRole(),
                        project.getAchievement(),
                        project.getProcess(),
                        project.getTechStack()))
                .toList();

        // 資格
        List<Certification> copiedCertifications = source.getCertifications().stream()
                .map(certification -> Certification.create(
                        errorCollector,
                        certification.getName(),
                        certification.getDate()))
                .toList();

        // ポートフォリオ
        List<Portfolio> copiedPortfolios = source.getPortfolios().stream()
                .map(portfolio -> Portfolio.create(
                        errorCollector,
                        portfolio.getName(),
                        portfolio.getOverview(),
                        portfolio.getTechStack(),
                        portfolio.getLink()))
                .toList();

        // SNSプラットフォーム
        List<SnsPlatform> copiedSnsPlatforms = source.getSnsPlatforms().stream()
                .map(snsPlatform -> SnsPlatform.create(
                        errorCollector,
                        snsPlatform.getName(),
                        snsPlatform.getLink()))
                .toList();

        // 自己PR
        List<SelfPromotion> copiedSelfPromotions = source.getSelfPromotions().stream()
                .map(selfPromotion -> SelfPromotion.create(
                        errorCollector,
                        selfPromotion.getTitle(),
                        selfPromotion.getContent()))
                .toList();

        // 職務経歴書エンティティ新規構築
        Resume copy = Resume.create(
                errorCollector,
                userId,
                resumeName,
                source.getDate(),
                source.getFullName(),
                copiedCareers,
                copiedProjects,
                copiedCertifications,
                copiedPortfolios,
                copiedSnsPlatforms,
                copiedSelfPromotions);

        resumeRepository.save(copy);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(copy);
    }
}
