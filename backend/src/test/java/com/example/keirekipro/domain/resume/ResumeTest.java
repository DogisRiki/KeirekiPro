package com.example.keirekipro.domain.resume;

import static org.junit.jupiter.api.Assertions.assertAll;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.Certification;
import com.example.keirekipro.domain.model.resume.FullName;
import com.example.keirekipro.domain.model.resume.Link;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Portfolio;
import com.example.keirekipro.domain.model.resume.Project;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.model.resume.SelfPromotion;
import com.example.keirekipro.domain.model.resume.SocialLink;
import com.example.keirekipro.domain.model.resume.TechStack;
import com.example.keirekipro.domain.shared.Notification;
import com.example.keirekipro.domain.shared.exception.DomainException;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

class ResumeTest {

    @Mock
    private Notification notification;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
    }

    @Test
    @DisplayName("新規構築用コンストラクタでインスタンス化する")
    void test1() {
        Resume resume = createSampleResume();
        // インスタンスがnullでない。
        assertNotNull(resume);
        // IDが生成されている。
        assertNotNull(resume.getId());
        // 並び順が正しい値である。
        assertEquals(0, resume.getOrderNo());
        // 各フィールドが正しい値である。
        assertEquals(UUID.fromString("123e4567-e89b-12d3-a456-426614174000"), resume.getUserId());
        assertEquals(ResumeName.create(notification, "職務経歴書A"), resume.getName());
        assertEquals(LocalDate.now(), resume.getDate());
        assertEquals(FullName.create(notification, "山田", "太郎"), resume.getFullName());
        assertEquals(true, resume.isAutoSaveEnabled());
        assertEquals(LocalDateTime.of(2023, 1, 1, 0, 0), resume.getCreatedAt());
        assertEquals(LocalDateTime.of(2023, 1, 2, 0, 0), resume.getUpdatedAt());
    }

    @Test
    @DisplayName("通知オブジェクト内にエラーがある状態で、新規構築用コンストラクタでインスタンス化する")
    void test2() {
        Notification invalidNotification = new Notification();
        invalidNotification.addError("name", "職務経歴書名は必須です。");
        UUID userId = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        // ドメイン例外がスローされる。
        assertThrows(DomainException.class, () -> {
            Resume.create(
                    invalidNotification,
                    0,
                    userId,
                    null, // 名前がnull
                    LocalDate.now(),
                    FullName.create(notification, "山田", "太郎"),
                    true,
                    LocalDateTime.now(),
                    LocalDateTime.now(),
                    List.of(),
                    List.of(),
                    List.of(),
                    List.of(),
                    List.of(),
                    List.of());
        });
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test3() {
        UUID id = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        UUID userId = UUID.fromString("223e4567-e89b-12d3-a456-426614174000");
        Resume resume = Resume.reconstruct(
                id,
                0,
                userId,
                ResumeName.create(notification, "職務経歴書A"),
                LocalDate.of(2023, 1, 1),
                FullName.create(notification, "山田", "太郎"),
                true,
                LocalDateTime.of(2023, 1, 1, 0, 0),
                LocalDateTime.of(2023, 1, 2, 0, 0),
                List.of(createSampleCareer()),
                List.of(createSampleProject()),
                List.of(createSampleCertification()),
                List.of(createSamplePortfolio()),
                List.of(createSampleSociealLink()),
                List.of(createSampleSelfPromotion()));

        // インスタンスがnullでない。
        assertNotNull(resume);
        // IDが正しい値である。
        assertEquals(id, resume.getId());
        // 並び順が正しい値である。
        assertEquals(0, resume.getOrderNo());
        // 各フィールドが正しい値である。
        assertEquals(userId, resume.getUserId());
        assertEquals(ResumeName.create(notification, "職務経歴書A"), resume.getName());
        assertEquals(LocalDate.of(2023, 1, 1), resume.getDate());
        assertEquals(FullName.create(notification, "山田", "太郎"), resume.getFullName());
        assertEquals(true, resume.isAutoSaveEnabled());
        assertEquals(LocalDateTime.of(2023, 1, 1, 0, 0), resume.getCreatedAt());
        assertEquals(LocalDateTime.of(2023, 1, 2, 0, 0), resume.getUpdatedAt());
        assertEquals(1, resume.getCareers().size());
        assertEquals(1, resume.getProjects().size());
        assertEquals(1, resume.getCertifications().size());
        assertEquals(1, resume.getPortfolios().size());
        assertEquals(1, resume.getSocialLinks().size());
        assertEquals(1, resume.getSelfPromotions().size());
    }

    @Test
    @DisplayName("職務経歴書名を変更する")
    void test4() {
        Resume originalResume = createSampleResume();
        ResumeName newName = ResumeName.create(notification, "新しい履歴書名");
        Resume updatedResume = originalResume.changeName(newName);
        // 職務経歴書名が正しい値である。
        assertEquals(newName, updatedResume.getName());
    }

    @Test
    @DisplayName("日付を変更する")
    void test5() {
        Resume originalResume = createSampleResume();
        LocalDate newDate = LocalDate.of(2025, 1, 1);
        Resume updatedResume = originalResume.changeDate(newDate);
        // 日付が正しい値である。
        assertEquals(newDate, updatedResume.getDate());
    }

    @Test
    @DisplayName("自動保存設定を変更する")
    void test6() {
        Resume originalResume = createSampleResume();
        boolean newAutoSaveEnabled = false;
        Resume updatedResume = originalResume.changeAutoSaveEnabled(newAutoSaveEnabled);
        // 自動保存設定が正しい値である。
        assertEquals(newAutoSaveEnabled, updatedResume.isAutoSaveEnabled());
    }

    @Test
    @DisplayName("正常な値で職歴を追加する")
    void test7() {
        Resume beforeResume = createSampleResume();
        Career newCareer = Career.create(1, "株式会社DEF",
                Period.create(notification, YearMonth.of(2024, 1), null, true));
        Resume afterResume = beforeResume.addCareer(notification, newCareer);
        // 新しい職歴がリストに含まれている。
        assertTrue(afterResume.getCareers().contains(newCareer));
        // 職歴リストのサイズが増加している。
        assertEquals(afterResume.getCareers().size(), beforeResume.getCareers().size() + 1);
    }

    @Test
    @DisplayName("継続中の職歴と期間が重なる職歴を追加するとドメイン例外をスローする")
    void test8() {
        // 1回目の呼び出しではfalse、2回目の呼び出しではtrueを返すよう設定する。
        when(notification.hasErrors()).thenReturn(false).thenReturn(true);

        UUID userId = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        Resume resume = Resume.create(
                notification,
                0,
                userId,
                ResumeName.create(notification, "職務経歴書A"),
                LocalDate.now(),
                FullName.create(notification, "山田", "太郎"),
                true,
                LocalDateTime.of(2023, 1, 1, 0, 0),
                LocalDateTime.of(2023, 1, 2, 0, 0),
                List.of(Career.create(0, "株式会社ABC",
                        Period.create(notification, YearMonth.of(2024, 1), null, true))),
                List.of(),
                List.of(),
                List.of(),
                List.of(),
                List.of());
        // DomainExceptionがスローされる。
        assertThrows(DomainException.class, () -> {
            resume.addCareer(notification, Career.create(1, "株式会社DEF",
                    Period.create(notification, YearMonth.of(2024, 2), YearMonth.of(2024, 3), false)));
        });
        // エラーメッセージが登録される。
        verify(notification, times(1)).addError(
                eq("career"),
                eq("株式会社DEFと株式会社ABCの期間が重複しています。"));
    }

    @Test
    @DisplayName("同じ期間の職歴を追加するとドメイン例外をスローする")
    void test9() {
        // 1回目の呼び出しではfalse、2回目の呼び出しではtrueを返すよう設定する。
        when(notification.hasErrors()).thenReturn(false).thenReturn(true);

        Resume resume = createSampleResume();
        // DomainExceptionがスローされる。
        assertThrows(DomainException.class, () -> {
            resume.addCareer(notification, Career.create(1, "株式会社DEF",
                    Period.create(notification, YearMonth.of(2020, 1), YearMonth.of(2023, 12), false)));
        });
        // エラーメッセージが登録される。
        verify(notification, times(1)).addError(
                eq("career"),
                eq("株式会社DEFと株式会社ABCの期間が重複しています。"));
    }

    @Test
    @DisplayName("継続中の職歴が存在する状態で、継続中の職歴を追加するとドメイン例外をスローする")
    void test10() {
        // 1回目の呼び出しではfalse、2回目の呼び出しではtrueを返すよう設定する。
        when(notification.hasErrors()).thenReturn(false).thenReturn(true);

        UUID userId = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        Resume resume = Resume.create(
                notification,
                0,
                userId,
                ResumeName.create(notification, "職務経歴書A"),
                LocalDate.now(),
                FullName.create(notification, "山田", "太郎"),
                true,
                LocalDateTime.of(2023, 1, 1, 0, 0),
                LocalDateTime.of(2023, 1, 2, 0, 0),
                List.of(Career.create(0, "株式会社ABC",
                        Period.create(notification, YearMonth.of(2024, 1), null, true))),
                List.of(),
                List.of(),
                List.of(),
                List.of(),
                List.of());
        // DomainExceptionがスローされる。
        assertThrows(DomainException.class, () -> {
            resume.addCareer(notification, Career.create(1, "株式会社DEF",
                    Period.create(notification, YearMonth.of(2024, 2), null, true)));
        });
        // エラーメッセージが登録される。
        verify(notification, times(1)).addError(
                eq("career"),
                eq("株式会社DEFと株式会社ABCの期間が重複しています。"));
    }

    @Test
    @DisplayName("期間が重なる職歴を追加するとドメイン例外をスローする")
    void test11() {
        // 1回目の呼び出しではfalse、2回目の呼び出しではtrueを返すよう設定する。
        when(notification.hasErrors()).thenReturn(false).thenReturn(true);

        Resume resume = createSampleResume();
        // DomainExceptionがスローされる。
        assertThrows(DomainException.class, () -> {
            resume.addCareer(notification, Career.create(1, "株式会社DEF",
                    Period.create(notification, YearMonth.of(2023, 10), YearMonth.of(2024, 11), false)));
        });
        // エラーメッセージが登録される。
        verify(notification, times(1)).addError(
                eq("career"),
                eq("株式会社DEFと株式会社ABCの期間が重複しています。"));
    }

    @Test
    @DisplayName("期間が一部重なる職歴を追加するとドメイン例外をスローする")
    void test12() {
        // 1回目の呼び出しではfalse、2回目の呼び出しではtrueを返すよう設定する。
        when(notification.hasErrors()).thenReturn(false).thenReturn(true);

        Resume resume = createSampleResume();
        // DomainExceptionがスローされる。
        assertThrows(DomainException.class, () -> {
            resume.addCareer(notification, Career.create(1, "株式会社DEF",
                    Period.create(notification, YearMonth.of(2023, 11), YearMonth.of(2024, 6), false)));
        });
        // エラーメッセージが登録される。
        verify(notification, times(1)).addError(
                eq("career"),
                eq("株式会社DEFと株式会社ABCの期間が重複しています。"));
    }

    @Test
    @DisplayName("正常な値で職歴を更新する")
    void test13() {
        Resume beforeResume = createSampleResume();
        Career newCareer = Career.reconstruct(beforeResume.getCareers().get(0).getId(), 0, "株式会社DEF",
                Period.create(notification, YearMonth.of(2024, 1), null, true));
        Resume afterResume = beforeResume.updateCareer(notification, newCareer);
        // 更新した職歴がリストに含まれている。
        assertTrue(afterResume.getCareers().contains(newCareer));
        // 職歴リストのサイズが変わらない。
        assertEquals(afterResume.getCareers().size(), beforeResume.getCareers().size());
        // 更新した職歴の値が正しい。
        assertAll(
                () -> assertEquals(afterResume.getCareers().get(0).getCompanyName(), newCareer.getCompanyName()),
                () -> assertEquals(afterResume.getCareers().get(0).getPeriod(), newCareer.getPeriod()),
                () -> assertEquals(afterResume.getCareers().get(0).getOrderNo(), newCareer.getOrderNo()),
                () -> assertEquals(afterResume.getCareers().get(0).getId(), beforeResume.getCareers().get(0).getId()));
    }

    @Test
    @DisplayName("職歴を削除する")
    void test14() {
        Resume beforeResume = createSampleResume();
        Career newCareer = Career.create(1, "株式会社DEF",
                Period.create(notification, YearMonth.of(2024, 1), null, true));
        Resume afterResume = beforeResume.addCareer(notification, newCareer);
        // 削除1回目(2件 → 1件)
        Resume deletedResume = afterResume.removeCareer(newCareer.getId());
        // 削除した職歴がリストに含まれていない。
        assertFalse(deletedResume.getCareers().contains(newCareer));
        // 職歴リストのサイズが減少している。
        assertEquals(afterResume.getCareers().size() - 1, deletedResume.getCareers().size());

        // 削除2回目(1件 → 0件)
        Resume deletedResume2 = deletedResume.removeCareer(deletedResume.getCareers().get(0).getId());
        // 職歴リストが空になっている。
        assertTrue(deletedResume2.getCareers().isEmpty());
    }

    @Test
    @DisplayName("正常な値でプロジェクトを追加する")
    void test15() {
        Resume beforeResume = createSampleResume();
        Project newProject = createSampleProject();
        Resume afterResume = beforeResume.addProject(notification, newProject);
        // 新しいプロジェクトがリストに含まれている。
        assertTrue(afterResume.getProjects().contains(newProject));
        // プロジェクトリストのサイズが増加している。
        assertEquals(afterResume.getProjects().size(), beforeResume.getProjects().size() + 1);
    }

    @Test
    @DisplayName("職歴に存在しない会社名のプロジェクトを追加するとドメイン例外をスローする")
    void test16() {
        // 1回目の呼び出しではfalse、2回目の呼び出しではtrueを返すよう設定する。
        when(notification.hasErrors()).thenReturn(false).thenReturn(true);

        Resume resume = createSampleResume();
        Project notExistProject = createSampleProject().changeCompanyName("株式会社ZZZ");
        // DomainExceptionがスローされる。
        assertThrows(DomainException.class, () -> {
            resume.addProject(notification, notExistProject);
        });
        // エラーメッセージが登録される。
        verify(notification, times(1)).addError(
                eq("companyName"),
                eq("株式会社ZZZは職歴に存在しません。職歴に存在する会社名を選択してください。"));
    }

    @Test
    @DisplayName("正常な値でプロジェクトを更新する")
    void test17() {
        Resume beforeResume = createSampleResume();

        // 更新対象のプロジェクトを取得し、値を変更
        Project originalProject = beforeResume.getProjects().get(0);
        Project updatedProject = Project.reconstruct(
                originalProject.getId(),
                originalProject.getOrderNo(),
                originalProject.getCompanyName(), // 会社名は変更しない
                originalProject.getPeriod(),
                "新しいプロジェクト概要",
                "10人",
                "マネージャー",
                "新しい成果内容",
                Project.Process.create(false, true, true, false, true, true, false),
                TechStack.create(
                        List.of("JavaScript", "TypeScript"),
                        TechStack.Dependencies.create(
                                List.of("React", "Redux"),
                                List.of("Axios", "Lodash"),
                                List.of("Jest", "Enzyme"),
                                List.of("Prisma"),
                                List.of("npm")),
                        TechStack.Infrastructure.create(
                                List.of("Azure"),
                                List.of("Kubernetes"),
                                List.of("MySQL"),
                                List.of("Apache"),
                                List.of("CircleCI"),
                                List.of("Ansible"),
                                List.of("Grafana"),
                                List.of("Azure Monitor")),
                        TechStack.Tools.create(
                                List.of("GitLab"),
                                List.of("Asana"),
                                List.of("Teams"),
                                List.of("Notion"),
                                List.of("Insomnia"),
                                List.of("Sketch"))));

        Resume afterResume = beforeResume.updateProject(notification, updatedProject);

        // 更新したプロジェクトがリストに含まれている。
        assertTrue(afterResume.getProjects().contains(updatedProject));
        // プロジェクトリストのサイズが変わらない。
        assertEquals(afterResume.getProjects().size(), beforeResume.getProjects().size());
        // 更新したプロジェクトの値が正しい。
        assertAll(
                () -> assertEquals(afterResume.getProjects().get(0).getId(), originalProject.getId()),
                () -> assertEquals(afterResume.getProjects().get(0).getCompanyName(), originalProject.getCompanyName()),
                () -> assertEquals(afterResume.getProjects().get(0).getPeriod(), originalProject.getPeriod()),
                () -> assertEquals(afterResume.getProjects().get(0).getOverview(), "新しいプロジェクト概要"),
                () -> assertEquals(afterResume.getProjects().get(0).getTeamComp(), "10人"),
                () -> assertEquals(afterResume.getProjects().get(0).getRole(), "マネージャー"),
                () -> assertEquals(afterResume.getProjects().get(0).getAchievement(), "新しい成果内容"),
                () -> assertEquals(afterResume.getProjects().get(0).getProcess(),
                        Project.Process.create(false, true, true, false, true, true, false)),
                () -> assertEquals(afterResume.getProjects().get(0).getTechStack().getLanguages(),
                        List.of("JavaScript", "TypeScript")),
                () -> assertEquals(afterResume.getProjects().get(0).getTechStack().getDependencies().getFrameworks(),
                        List.of("React", "Redux")),
                () -> assertEquals(afterResume.getProjects().get(0).getTechStack().getInfrastructure().getClouds(),
                        List.of("Azure")),
                () -> assertEquals(afterResume.getProjects().get(0).getTechStack().getTools().getSourceControls(),
                        List.of("GitLab")));
    }

    @Test
    @DisplayName("プロジェクトを削除する")
    void test18() {
        Resume beforeResume = createSampleResume();

        // 削除対象のプロジェクトを追加
        Project newProject = Project.create(
                1,
                "株式会社DEF",
                Period.create(notification, YearMonth.of(2022, 1), YearMonth.of(2023, 1), false),
                "プロジェクト概要",
                "5人",
                "リーダー",
                "成果内容",
                Project.Process.create(true, false, true, false, true, false, true),
                TechStack.create(
                        List.of("Python"),
                        TechStack.Dependencies.create(
                                List.of("Flask"),
                                List.of("Requests"),
                                List.of("Pytest"),
                                List.of("SQLAlchemy"),
                                List.of("Pip")),
                        TechStack.Infrastructure.create(
                                List.of("AWS"),
                                List.of("Docker"),
                                List.of("PostgreSQL"),
                                List.of("Nginx"),
                                List.of("GitHub Actions"),
                                List.of("Terraform"),
                                List.of("Prometheus"),
                                List.of("CloudWatch")),
                        TechStack.Tools.create(
                                List.of("Git"),
                                List.of("Jira"),
                                List.of("Slack"),
                                List.of("Confluence"),
                                List.of("Postman"),
                                List.of("Figma"))));

        Resume afterResume = beforeResume.addProject(notification, newProject);

        // 削除1回目(2件 → 1件)
        Resume deletedResume = afterResume.removeProject(newProject.getId());
        // 削除したプロジェクトがリストに含まれていない。
        assertFalse(deletedResume.getProjects().contains(newProject));
        // プロジェクトリストのサイズが減少している。
        assertEquals(afterResume.getProjects().size() - 1, deletedResume.getProjects().size());

        // 削除2回目(1件 → 0件)
        Resume deletedResume2 = deletedResume.removeProject(deletedResume.getProjects().get(0).getId());
        // プロジェクトリストが空になっている。
        assertTrue(deletedResume2.getProjects().isEmpty());
    }

    @Test
    @DisplayName("資格を追加する")
    void test19() {
        Resume beforeResume = createSampleResume();
        Certification newCertification = Certification.create(1, "応用情報技術者", YearMonth.of(2025, 02));
        Resume afterResume = beforeResume.addCertification(newCertification);
        // 新しい資格がリストに含まれている
        assertTrue(afterResume.getCertifications().contains(newCertification));
        // 資格リストのサイズが増加している。
        assertEquals(afterResume.getCertifications().size(), beforeResume.getCertifications().size() + 1);
    }

    @Test
    @DisplayName("資格を更新する")
    void test20() {
        Resume beforeResume = createSampleResume();
        Certification newCertification = Certification.reconstruct(beforeResume.getCertifications().get(0).getId(), 0,
                "応用情報技術者", YearMonth.of(2025, 02));
        Resume afterResume = beforeResume.updateCertification(newCertification);
        // 更新した資格がリストに含まれている。
        assertTrue(afterResume.getCertifications().contains(newCertification));
        // 資格リストのサイズが変わらない。
        assertEquals(afterResume.getCertifications().size(), beforeResume.getCertifications().size());
        // 更新した資格の値が正しい。
        assertAll(
                () -> assertEquals(afterResume.getCertifications().get(0).getName(), newCertification.getName()),
                () -> assertEquals(afterResume.getCertifications().get(0).getDate(), newCertification.getDate()),
                () -> assertEquals(afterResume.getCertifications().get(0).getOrderNo(), newCertification.getOrderNo()),
                () -> assertEquals(afterResume.getCertifications().get(0).getId(),
                        beforeResume.getCertifications().get(0).getId()));
    }

    @Test
    @DisplayName("資格を削除する")
    void test21() {
        Resume beforeResume = createSampleResume();
        Certification newCertification = Certification.create(1, "応用情報技術者", YearMonth.of(2025, 02));
        Resume afterResume = beforeResume.addCertification(newCertification);
        // 削除1回目(2件 → 1件)
        Resume deletedResume = afterResume.removeCertification(newCertification.getId());
        // 削除した職歴がリストに含まれていない。
        assertFalse(deletedResume.getCertifications().contains(newCertification));
        // 職歴リストのサイズが減少している。
        assertEquals(afterResume.getCertifications().size() - 1, deletedResume.getCertifications().size());

        // 削除2回目(1件 → 0件)
        Resume deletedResume2 = deletedResume.removeCertification(deletedResume.getCertifications().get(0).getId());
        // 職歴リストが空になっている。
        assertTrue(deletedResume2.getCertifications().isEmpty());
    }

    @Test
    @DisplayName("ポートフォリオを追加する")
    void test22() {
        Resume beforeResume = createSampleResume();
        Portfolio newPortfolio = Portfolio.create(
                1,
                "新しいポートフォリオ",
                "新しいポートフォリオの概要",
                "新しい技術スタック",
                Link.create(notification, "https://new-portfolio.com"));

        Resume afterResume = beforeResume.addPortfolio(newPortfolio);

        // 新しいポートフォリオがリストに含まれている。
        assertTrue(afterResume.getPortfolios().contains(newPortfolio));
        // ポートフォリオリストのサイズが増加している。
        assertEquals(afterResume.getPortfolios().size(), beforeResume.getPortfolios().size() + 1);
    }

    @Test
    @DisplayName("ポートフォリオを更新する")
    void test23() {
        Resume beforeResume = createSampleResume();
        Portfolio updatedPortfolio = Portfolio.reconstruct(
                beforeResume.getPortfolios().get(0).getId(),
                0,
                "更新されたポートフォリオ",
                "更新されたポートフォリオの概要",
                "更新された技術スタック",
                Link.create(notification, "https://updated-portfolio.com"));

        Resume afterResume = beforeResume.updatePortfolio(updatedPortfolio);

        // 更新したポートフォリオがリストに含まれている。
        assertTrue(afterResume.getPortfolios().contains(updatedPortfolio));
        // ポートフォリオリストのサイズが変わらない。
        assertEquals(afterResume.getPortfolios().size(), beforeResume.getPortfolios().size());
        // 更新したポートフォリオの値が正しい。
        assertAll(
                () -> assertEquals(afterResume.getPortfolios().get(0).getName(), updatedPortfolio.getName()),
                () -> assertEquals(afterResume.getPortfolios().get(0).getOverview(), updatedPortfolio.getOverview()),
                () -> assertEquals(afterResume.getPortfolios().get(0).getTechStack(), updatedPortfolio.getTechStack()),
                () -> assertEquals(afterResume.getPortfolios().get(0).getLink(), updatedPortfolio.getLink()),
                () -> assertEquals(afterResume.getPortfolios().get(0).getId(),
                        beforeResume.getPortfolios().get(0).getId()));
    }

    @Test
    @DisplayName("ポートフォリオを削除する")
    void test24() {
        Resume beforeResume = createSampleResume();
        Portfolio newPortfolio = Portfolio.create(
                1,
                "削除対象のポートフォリオ",
                "削除対象の概要",
                "削除対象の技術スタック",
                Link.create(notification, "https://delete-portfolio.com"));

        Resume afterResume = beforeResume.addPortfolio(newPortfolio);

        // 削除1回目(2件 → 1件)
        Resume deletedResume = afterResume.removePortfolio(newPortfolio.getId());
        // 削除したポートフォリオがリストに含まれていない。
        assertFalse(deletedResume.getPortfolios().contains(newPortfolio));
        // ポートフォリオリストのサイズが減少している。
        assertEquals(afterResume.getPortfolios().size() - 1, deletedResume.getPortfolios().size());

        // 削除2回目(1件 → 0件)
        Resume deletedResume2 = deletedResume.removePortfolio(deletedResume.getPortfolios().get(0).getId());
        // ポートフォリオリストが空になっている。
        assertTrue(deletedResume2.getPortfolios().isEmpty());
    }

    @Test
    @DisplayName("ソーシャルリンクを追加する")
    void test25() {
        Resume beforeResume = createSampleResume();
        SocialLink newSocialLink = SocialLink.create(
                1,
                "Twitter",
                Link.create(notification, "https://twitter.com/user"));

        Resume afterResume = beforeResume.addSociealLink(newSocialLink);

        // 新しいソーシャルリンクがリストに含まれている。
        assertTrue(afterResume.getSocialLinks().contains(newSocialLink));
        // ソーシャルリンクリストのサイズが増加している。
        assertEquals(afterResume.getSocialLinks().size(), beforeResume.getSocialLinks().size() + 1);
    }

    @Test
    @DisplayName("ソーシャルリンクを更新する")
    void test26() {
        Resume beforeResume = createSampleResume();
        SocialLink updatedSocialLink = SocialLink.reconstruct(
                beforeResume.getSocialLinks().get(0).getId(),
                0,
                "LinkedIn",
                Link.create(notification, "https://linkedin.com/in/user"));

        Resume afterResume = beforeResume.updateSociealLink(updatedSocialLink);

        // 更新したソーシャルリンクがリストに含まれている。
        assertTrue(afterResume.getSocialLinks().contains(updatedSocialLink));
        // ソーシャルリンクリストのサイズが変わらない。
        assertEquals(afterResume.getSocialLinks().size(), beforeResume.getSocialLinks().size());
        // 更新したソーシャルリンクの値が正しい。
        assertAll(
                () -> assertEquals(afterResume.getSocialLinks().get(0).getName(), updatedSocialLink.getName()),
                () -> assertEquals(afterResume.getSocialLinks().get(0).getLink(), updatedSocialLink.getLink()),
                () -> assertEquals(afterResume.getSocialLinks().get(0).getId(),
                        beforeResume.getSocialLinks().get(0).getId()));
    }

    @Test
    @DisplayName("ソーシャルリンクを削除する")
    void test27() {
        Resume beforeResume = createSampleResume();
        SocialLink newSocialLink = SocialLink.create(
                1,
                "Facebook",
                Link.create(notification, "https://facebook.com/user"));

        Resume afterResume = beforeResume.addSociealLink(newSocialLink);

        // 削除1回目(2件 → 1件)
        Resume deletedResume = afterResume.removeSociealLink(newSocialLink.getId());
        // 削除したソーシャルリンクがリストに含まれていない。
        assertFalse(deletedResume.getSocialLinks().contains(newSocialLink));
        // ソーシャルリンクリストのサイズが減少している。
        assertEquals(afterResume.getSocialLinks().size() - 1, deletedResume.getSocialLinks().size());

        // 削除2回目(1件 → 0件)
        Resume deletedResume2 = deletedResume.removeSociealLink(deletedResume.getSocialLinks().get(0).getId());
        // ソーシャルリンクリストが空になっている。
        assertTrue(deletedResume2.getSocialLinks().isEmpty());
    }

    @Test
    @DisplayName("自己PRを追加する")
    void test28() {
        Resume beforeResume = createSampleResume();
        SelfPromotion newSelfPromotion = SelfPromotion.create(
                1,
                "新しいタイトル",
                "新しい自己PRの内容");

        Resume afterResume = beforeResume.addSelfPromotion(newSelfPromotion);

        // 新しい自己PRがリストに含まれている。
        assertTrue(afterResume.getSelfPromotions().contains(newSelfPromotion));
        // 自己PRリストのサイズが増加している。
        assertEquals(afterResume.getSelfPromotions().size(), beforeResume.getSelfPromotions().size() + 1);
    }

    @Test
    @DisplayName("自己PRを更新する")
    void test29() {
        Resume beforeResume = createSampleResume();
        SelfPromotion updatedSelfPromotion = SelfPromotion.reconstruct(
                beforeResume.getSelfPromotions().get(0).getId(),
                0,
                "更新されたタイトル",
                "更新された自己PRの内容");

        Resume afterResume = beforeResume.updateSelfPromotion(updatedSelfPromotion);

        // 更新した自己PRがリストに含まれている。
        assertTrue(afterResume.getSelfPromotions().contains(updatedSelfPromotion));
        // 自己PRリストのサイズが変わらない。
        assertEquals(afterResume.getSelfPromotions().size(), beforeResume.getSelfPromotions().size());
        // 更新した自己PRの値が正しい。
        assertAll(
                () -> assertEquals(afterResume.getSelfPromotions().get(0).getTitle(), updatedSelfPromotion.getTitle()),
                () -> assertEquals(afterResume.getSelfPromotions().get(0).getContent(),
                        updatedSelfPromotion.getContent()),
                () -> assertEquals(afterResume.getSelfPromotions().get(0).getId(),
                        beforeResume.getSelfPromotions().get(0).getId()));
    }

    @Test
    @DisplayName("自己PRを削除する")
    void test30() {
        Resume beforeResume = createSampleResume();
        SelfPromotion newSelfPromotion = SelfPromotion.create(
                1,
                "削除対象のタイトル",
                "削除対象の自己PRの内容");

        Resume afterResume = beforeResume.addSelfPromotion(newSelfPromotion);

        // 削除1回目(2件 → 1件)
        Resume deletedResume = afterResume.removeSelfPromotion(newSelfPromotion.getId());
        // 削除した自己PRがリストに含まれていない。
        assertFalse(deletedResume.getSelfPromotions().contains(newSelfPromotion));
        // 自己PRリストのサイズが減少している。
        assertEquals(afterResume.getSelfPromotions().size() - 1, deletedResume.getSelfPromotions().size());

        // 削除2回目(1件 → 0件)
        Resume deletedResume2 = deletedResume.removeSelfPromotion(deletedResume.getSelfPromotions().get(0).getId());
        // 自己PRリストが空になっている。
        assertTrue(deletedResume2.getSelfPromotions().isEmpty());
    }

    @Test
    @DisplayName("氏名を変更する")
    void test31() {
        Resume originalResume = createSampleResume();
        FullName newFullName = FullName.create(notification, "変更", "しました");
        Resume updatedResume = originalResume.ChangeFullName(newFullName);
        // 職務経歴書名が正しい値である。
        assertEquals(newFullName, updatedResume.getFullName());
    }

    /**
     * 職務経歴書のサンプルエンティティを作成する補助メソッド
     */
    private Resume createSampleResume() {
        UUID userId = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        return Resume.create(
                notification,
                0,
                userId,
                ResumeName.create(notification, "職務経歴書A"),
                LocalDate.now(),
                FullName.create(notification, "山田", "太郎"),
                true,
                LocalDateTime.of(2023, 1, 1, 0, 0),
                LocalDateTime.of(2023, 1, 2, 0, 0),
                List.of(createSampleCareer()),
                List.of(createSampleProject()),
                List.of(createSampleCertification()),
                List.of(createSamplePortfolio()),
                List.of(createSampleSociealLink()),
                List.of(createSampleSelfPromotion()));
    }

    /**
     * 職歴のサンプルエンティティを作成する補助メソッド
     */
    private Career createSampleCareer() {
        Period period = Period.create(notification, YearMonth.of(2020, 1), YearMonth.of(2023, 12), false);
        return Career.create(0, "株式会社ABC", period);
    }

    /**
     * プロジェクトのサンプルエンティティを作成する補助メソッド
     */
    private Project createSampleProject() {
        Period period = Period.create(notification, YearMonth.of(2021, 1), YearMonth.of(2023, 12), false);
        TechStack techStack = TechStack.create(
                List.of("Java", "Python"),
                TechStack.Dependencies.create(
                        List.of("Spring", "Django"),
                        List.of("Lombok", "Jackson"),
                        List.of("JUnit", "Mockito"),
                        List.of("MyBatis"),
                        List.of("Maven")),
                TechStack.Infrastructure.create(
                        List.of("AWS"),
                        List.of("Docker"),
                        List.of("PostgreSQL"),
                        List.of("Nginx"),
                        List.of("GitHub Actions"),
                        List.of("Terraform"),
                        List.of("Prometheus"),
                        List.of("CloudWatch")),
                TechStack.Tools.create(
                        List.of("Git"),
                        List.of("Jira"),
                        List.of("Slack"),
                        List.of("Confluence"),
                        List.of("Postman"),
                        List.of("Figma")));
        Project.Process process = Project.Process.create(true, true, true, true, true, true, true);
        return Project.create(0, "株式会社ABC", period, "プロジェクト概要", "5人", "リーダー", "成果内容", process, techStack);
    }

    /**
     * 資格のサンプルエンティティを作成する補助メソッド
     */
    private Certification createSampleCertification() {
        return Certification.create(0, "基本情報技術者", YearMonth.of(2025, 01));
    }

    /**
     * ポートフォリオのサンプルエンティティを作成する補助メソッド
     */
    private Portfolio createSamplePortfolio() {
        return Portfolio.create(0, "ポートフォリオ名", "概要", "技術スタック", Link.create(notification, "https://portfolio.com"));
    }

    /**
     * ソーシャルリンクのサンプルエンティティを作成する補助メソッド
     */
    private SocialLink createSampleSociealLink() {
        return SocialLink.create(0, "GitHub", Link.create(notification, "https://github.com/user"));
    }

    /**
     * 自己PRのサンプルエンティティを作成する補助メソッド
     */
    private SelfPromotion createSampleSelfPromotion() {
        return SelfPromotion.create(0, "自己PRタイトル", "自己PR内容");
    }
}
