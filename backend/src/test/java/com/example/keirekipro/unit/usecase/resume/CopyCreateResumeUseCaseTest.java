package com.example.keirekipro.unit.usecase.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.Certification;
import com.example.keirekipro.domain.model.resume.Portfolio;
import com.example.keirekipro.domain.model.resume.Project;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.model.resume.SelfPromotion;
import com.example.keirekipro.domain.model.resume.SocialLink;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.domain.service.resume.ResumeNameDuplicationCheckService;
import com.example.keirekipro.helper.ResumeObjectBuilder;
import com.example.keirekipro.presentation.resume.dto.CreateResumeRequest;
import com.example.keirekipro.usecase.resume.CopyCreateResumeUseCase;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.resume.policy.ResumeLimitChecker;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class CopyCreateResumeUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @Mock
    private ResumeNameDuplicationCheckService service;

    @Mock
    private ResumeLimitChecker checker;

    @InjectMocks
    private CopyCreateResumeUseCase useCase;

    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID RESUME_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID OTHER_USER_ID = UUID.fromString("33333333-3333-3333-3333-333333333333");
    private static final String ORIGINAL_NAME = "職務経歴書1";
    private static final String NEW_NAME = "職務経歴書New";
    private static final LocalDate DATE = LocalDate.of(2021, 5, 20);
    private static final String LAST_NAME = "山田";
    private static final String FIRST_NAME = "太郎";
    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2021, 5, 15, 10, 0);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2021, 5, 18, 15, 30);

    @Test
    @DisplayName("職務経歴書をコピーして新規作成でき、ResumeおよびサブエンティティのIDが再採番される")
    void test1() {
        // リクエスト準備
        CreateResumeRequest request = new CreateResumeRequest(NEW_NAME, RESUME_ID);

        // コピー元エンティティをヘルパーで生成
        Resume source = ResumeObjectBuilder.buildResume(
                RESUME_ID, USER_ID, ORIGINAL_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        // モック設定
        doNothing().when(service).execute(eq(USER_ID), any(ResumeName.class));
        doNothing().when(checker).checkResumeCreateAllowed(USER_ID);
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(source));

        // 実行
        ArgumentCaptor<Resume> captor = ArgumentCaptor.forClass(Resume.class);
        final ResumeInfoUseCaseDto actual = useCase.execute(USER_ID, request);

        // 検証
        verify(service).execute(eq(USER_ID), any(ResumeName.class));
        verify(repository).find(RESUME_ID);
        verify(repository).save(captor.capture());

        Resume saved = captor.getValue();

        // ルートエンティティの基本項目検証
        assertThat(saved.getId()).isNotNull();
        assertThat(saved.getId()).isNotEqualTo(source.getId()); // コピー元とは別IDであること
        assertThat(saved.getUserId()).isEqualTo(USER_ID);
        assertThat(saved.getName().getValue()).isEqualTo(NEW_NAME);
        assertThat(saved.getDate()).isEqualTo(source.getDate());
        assertThat(saved.getFullName()).isEqualTo(source.getFullName());

        // 職歴のID再採番と内容コピーの検証
        assertThat(saved.getCareers()).hasSize(source.getCareers().size());
        for (int i = 0; i < source.getCareers().size(); i++) {
            Career sourceCareer = source.getCareers().get(i);
            Career copiedCareer = saved.getCareers().get(i);

            assertThat(copiedCareer.getId()).isNotNull();
            assertThat(copiedCareer.getId()).isNotEqualTo(sourceCareer.getId());
            assertThat(copiedCareer.getCompanyName()).isEqualTo(sourceCareer.getCompanyName());
            assertThat(copiedCareer.getPeriod()).isEqualTo(sourceCareer.getPeriod());
        }

        // プロジェクトのID再採番と内容コピーの検証
        assertThat(saved.getProjects()).hasSize(source.getProjects().size());
        for (int i = 0; i < source.getProjects().size(); i++) {
            Project sourceProject = source.getProjects().get(i);
            Project copiedProject = saved.getProjects().get(i);

            assertThat(copiedProject.getId()).isNotNull();
            assertThat(copiedProject.getId()).isNotEqualTo(sourceProject.getId());
            assertThat(copiedProject.getCompanyName()).isEqualTo(sourceProject.getCompanyName());
            assertThat(copiedProject.getPeriod()).isEqualTo(sourceProject.getPeriod());
            assertThat(copiedProject.getName()).isEqualTo(sourceProject.getName());
            assertThat(copiedProject.getOverview()).isEqualTo(sourceProject.getOverview());
            assertThat(copiedProject.getTeamComp()).isEqualTo(sourceProject.getTeamComp());
            assertThat(copiedProject.getRole()).isEqualTo(sourceProject.getRole());
            assertThat(copiedProject.getAchievement()).isEqualTo(sourceProject.getAchievement());
            assertThat(copiedProject.getProcess()).isEqualTo(sourceProject.getProcess());
            assertThat(copiedProject.getTechStack()).isEqualTo(sourceProject.getTechStack());
        }

        // 資格のID再採番と内容コピーの検証
        assertThat(saved.getCertifications()).hasSize(source.getCertifications().size());
        for (int i = 0; i < source.getCertifications().size(); i++) {
            Certification sourceCertification = source.getCertifications().get(i);
            Certification copiedCertification = saved.getCertifications().get(i);

            assertThat(copiedCertification.getId()).isNotNull();
            assertThat(copiedCertification.getId()).isNotEqualTo(sourceCertification.getId());
            assertThat(copiedCertification.getName()).isEqualTo(sourceCertification.getName());
            assertThat(copiedCertification.getDate()).isEqualTo(sourceCertification.getDate());
        }

        // ポートフォリオのID再採番と内容コピーの検証
        assertThat(saved.getPortfolios()).hasSize(source.getPortfolios().size());
        for (int i = 0; i < source.getPortfolios().size(); i++) {
            Portfolio sourcePortfolio = source.getPortfolios().get(i);
            Portfolio copiedPortfolio = saved.getPortfolios().get(i);

            assertThat(copiedPortfolio.getId()).isNotNull();
            assertThat(copiedPortfolio.getId()).isNotEqualTo(sourcePortfolio.getId());
            assertThat(copiedPortfolio.getName()).isEqualTo(sourcePortfolio.getName());
            assertThat(copiedPortfolio.getOverview()).isEqualTo(sourcePortfolio.getOverview());
            assertThat(copiedPortfolio.getTechStack()).isEqualTo(sourcePortfolio.getTechStack());
            assertThat(copiedPortfolio.getLink()).isEqualTo(sourcePortfolio.getLink());
        }

        // ソーシャルリンクのID再採番と内容コピーの検証
        assertThat(saved.getSocialLinks()).hasSize(source.getSocialLinks().size());
        for (int i = 0; i < source.getSocialLinks().size(); i++) {
            SocialLink sourceSocialLink = source.getSocialLinks().get(i);
            SocialLink copiedSocialLink = saved.getSocialLinks().get(i);

            assertThat(copiedSocialLink.getId()).isNotNull();
            assertThat(copiedSocialLink.getId()).isNotEqualTo(sourceSocialLink.getId());
            assertThat(copiedSocialLink.getName()).isEqualTo(sourceSocialLink.getName());
            assertThat(copiedSocialLink.getLink()).isEqualTo(sourceSocialLink.getLink());
        }

        // 自己PRのID再採番と内容コピーの検証
        assertThat(saved.getSelfPromotions()).hasSize(source.getSelfPromotions().size());
        for (int i = 0; i < source.getSelfPromotions().size(); i++) {
            SelfPromotion sourceSelfPromotion = source.getSelfPromotions().get(i);
            SelfPromotion copiedSelfPromotion = saved.getSelfPromotions().get(i);

            assertThat(copiedSelfPromotion.getId()).isNotNull();
            assertThat(copiedSelfPromotion.getId()).isNotEqualTo(sourceSelfPromotion.getId());
            assertThat(copiedSelfPromotion.getTitle()).isEqualTo(sourceSelfPromotion.getTitle());
            assertThat(copiedSelfPromotion.getContent()).isEqualTo(sourceSelfPromotion.getContent());
        }

        // save()で受け取ったResumeからDTOを組み立て、それを比較（既存検証は維持）
        ResumeInfoUseCaseDto expected = ResumeInfoUseCaseDto.convertToUseCaseDto(saved);

        assertThat(actual)
                .usingRecursiveComparison()
                .isEqualTo(expected);
    }

    @Test
    @DisplayName("職務経歴書名が重複していた場合、例外がスローされ後続処理が行われない")
    void test2() {
        CreateResumeRequest request = new CreateResumeRequest(NEW_NAME, RESUME_ID);

        doThrow(new UseCaseException("この職務経歴書名は既に登録されています。"))
                .when(service).execute(eq(USER_ID), any(ResumeName.class));

        assertThatThrownBy(() -> useCase.execute(USER_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("この職務経歴書名は既に登録されています。");

        verify(service).execute(eq(USER_ID), any(ResumeName.class));
        verify(repository, never()).find(any());
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("ログインユーザー以外が所有する職務経歴書をコピーしようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        // リクエスト準備
        CreateResumeRequest request = new CreateResumeRequest(NEW_NAME, RESUME_ID);

        // コピー元エンティティ（所有者は別ユーザー）
        Resume source = ResumeObjectBuilder.buildResume(
                RESUME_ID, OTHER_USER_ID, ORIGINAL_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        // モック
        doNothing().when(service).execute(eq(USER_ID), any(ResumeName.class));
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(source));

        // 実行＆検証
        assertThatThrownBy(() -> useCase.execute(USER_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("コピー元の職務経歴書が存在しません。");

        verify(service).execute(eq(USER_ID), any(ResumeName.class));
        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("コピー元の職務経歴書が存在しない場合、UseCaseExceptionがスローされる")
    void test4() {
        // リクエスト準備
        CreateResumeRequest request = new CreateResumeRequest(NEW_NAME, RESUME_ID);

        // モック（コピー元なし）
        doNothing().when(service).execute(eq(USER_ID), any(ResumeName.class));
        when(repository.find(RESUME_ID)).thenReturn(Optional.empty());

        // 実行＆検証
        assertThatThrownBy(() -> useCase.execute(USER_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("コピー元の職務経歴書が存在しません。");

        verify(service).execute(eq(USER_ID), any(ResumeName.class));
        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("職務経歴書が上限枚数である場合、例外がスローされ後続処理が行われない")
    void test5() {
        // リクエスト準備
        CreateResumeRequest request = new CreateResumeRequest(NEW_NAME, RESUME_ID);

        // モックをセットアップ：上限チェックでUseCaseExceptionを投げる
        doThrow(new UseCaseException("上限")).when(checker).checkResumeCreateAllowed(USER_ID);

        // ユースケース実行＆UseCaseExceptionがスローされることを検証
        assertThatThrownBy(() -> useCase.execute(USER_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("上限");

        // 上限チェックは呼ばれるが、後続処理は行われない
        verify(checker).checkResumeCreateAllowed(USER_ID);
        verify(service, never()).execute(any(), any());
        verify(repository, never()).save(any());
    }
}
