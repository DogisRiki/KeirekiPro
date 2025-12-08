package com.example.keirekipro.unit.domain.model.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assertions.assertAll;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.Certification;
import com.example.keirekipro.domain.model.resume.CompanyName;
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
import com.example.keirekipro.domain.shared.exception.DomainException;
import com.example.keirekipro.shared.Notification;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ResumeTest {

    @Mock
    private Notification notification;

    @Test
    @DisplayName("新規構築用コンストラクタでインスタンス化する")
    void test1() {
        Resume resume = createSampleResume();

        assertThat(resume).isNotNull();
        assertThat(resume.getId()).isNotNull();
        assertThat(resume.getUserId()).isEqualTo(UUID.fromString("123e4567-e89b-12d3-a456-426614174000"));
        assertThat(resume.getName()).isEqualTo(ResumeName.create(notification, "職務経歴書A"));
        assertThat(resume.getDate()).isEqualTo(LocalDate.now());
        assertThat(resume.getFullName()).isEqualTo(FullName.create(notification, "山田", "太郎"));
        assertThat(resume.getCreatedAt()).isNotNull();
        assertThat(resume.getUpdatedAt()).isNotNull();
    }

    @Test
    @DisplayName("通知オブジェクト内にエラーがある状態で、新規構築用コンストラクタでインスタンス化するとDomainExceptionをスローする")
    void test2() {
        Notification invalidNotification = new Notification();
        invalidNotification.addError("name", "職務経歴書名は入力必須です。");
        UUID userId = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> {
            Resume.create(
                    invalidNotification,
                    userId,
                    null, // 名前がnull
                    LocalDate.now(),
                    FullName.create(notification, "山田", "太郎"),
                    List.of(),
                    List.of(),
                    List.of(),
                    List.of(),
                    List.of(),
                    List.of());
        }).isInstanceOf(DomainException.class);
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test3() {
        UUID id = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        UUID userId = UUID.fromString("223e4567-e89b-12d3-a456-426614174000");
        Resume resume = Resume.reconstruct(
                id,
                userId,
                ResumeName.create(notification, "職務経歴書A"),
                LocalDate.of(2023, 1, 1),
                FullName.create(notification, "山田", "太郎"),
                LocalDateTime.of(2023, 1, 1, 0, 0),
                LocalDateTime.of(2023, 1, 2, 0, 0),
                List.of(createSampleCareer()),
                List.of(createSampleProject()),
                List.of(createSampleCertification()),
                List.of(createSamplePortfolio()),
                List.of(createSampleSociealLink()),
                List.of(createSampleSelfPromotion()));

        assertThat(resume).isNotNull();
        assertThat(resume.getId()).isEqualTo(id);
        assertThat(resume.getUserId()).isEqualTo(userId);
        assertThat(resume.getName()).isEqualTo(ResumeName.create(notification, "職務経歴書A"));
        assertThat(resume.getDate()).isEqualTo(LocalDate.of(2023, 1, 1));
        assertThat(resume.getFullName()).isEqualTo(FullName.create(notification, "山田", "太郎"));
        assertThat(resume.getCreatedAt()).isEqualTo(LocalDateTime.of(2023, 1, 1, 0, 0));
        assertThat(resume.getUpdatedAt()).isEqualTo(LocalDateTime.of(2023, 1, 2, 0, 0));
        assertThat(resume.getCareers().size()).isEqualTo(1);
        assertThat(resume.getProjects().size()).isEqualTo(1);
        assertThat(resume.getCertifications().size()).isEqualTo(1);
        assertThat(resume.getPortfolios().size()).isEqualTo(1);
        assertThat(resume.getSocialLinks().size()).isEqualTo(1);
        assertThat(resume.getSelfPromotions().size()).isEqualTo(1);
    }

    @Test
    @DisplayName("職務経歴書名を変更する")
    void test4() {
        Resume originalResume = createSampleResume();
        ResumeName newName = ResumeName.create(notification, "新しい履歴書名");
        Notification domainNotification = new Notification();

        Resume updatedResume = originalResume.changeName(domainNotification, newName);

        assertThat(updatedResume.getName()).isEqualTo(newName);
    }

    @Test
    @DisplayName("日付を変更する")
    void test5() {
        Resume originalResume = createSampleResume();
        LocalDate newDate = LocalDate.of(2025, 1, 1);
        Notification domainNotification = new Notification();

        Resume updatedResume = originalResume.changeDate(domainNotification, newDate);

        assertThat(updatedResume.getDate()).isEqualTo(newDate);
    }

    @Test
    @DisplayName("正常な値で職歴を追加する")
    void test6() {
        Resume beforeResume = createSampleResume();
        Career newCareer = Career.create(notification, CompanyName.create(notification, "株式会社DEF"),
                Period.create(notification, YearMonth.of(2024, 1), null, true));
        Notification domainNotification = new Notification();

        Resume afterResume = beforeResume.addCareer(domainNotification, newCareer);

        assertThat(afterResume.getCareers().contains(newCareer)).isTrue();
        assertThat(afterResume.getCareers().size()).isEqualTo(beforeResume.getCareers().size() + 1);
    }

    @Test
    @DisplayName("継続中の職歴と期間が重なる職歴を追加するとDomainExceptionをスローする")
    void test7() {
        UUID userId = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        Resume resume = Resume.create(
                notification,
                userId,
                ResumeName.create(notification, "職務経歴書A"),
                LocalDate.now(),
                FullName.create(notification, "山田", "太郎"),
                List.of(Career.create(notification, CompanyName.create(notification, "株式会社ABC"),
                        Period.create(notification, YearMonth.of(2024, 1), null, true))),
                List.of(),
                List.of(),
                List.of(),
                List.of(),
                List.of());

        Career overlappingCareer = Career.create(notification, CompanyName.create(notification, "株式会社DEF"),
                Period.create(notification, YearMonth.of(2024, 2), YearMonth.of(2024, 3), false));

        Notification domainNotification = new Notification();

        assertThatThrownBy(() -> resume.addCareer(domainNotification, overlappingCareer))
                .isInstanceOf(DomainException.class)
                .hasMessageContaining("株式会社DEFと株式会社ABCの期間が重複しています。");
    }

    @Test
    @DisplayName("同じ期間の職歴を追加するとDomainExceptionをスローする")
    void test8() {
        Resume resume = createSampleResume();

        Career overlappingCareer = Career.create(notification, CompanyName.create(notification, "株式会社DEF"),
                Period.create(notification, YearMonth.of(2020, 1), YearMonth.of(2023, 12), false));

        Notification domainNotification = new Notification();

        assertThatThrownBy(() -> resume.addCareer(domainNotification, overlappingCareer))
                .isInstanceOf(DomainException.class)
                .hasMessageContaining("株式会社DEFと株式会社ABCの期間が重複しています。");
    }

    @Test
    @DisplayName("継続中の職歴が存在する状態で、継続中の職歴を追加するとDomainExceptionをスローする")
    void test9() {
        UUID userId = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        Resume resume = Resume.create(
                notification,
                userId,
                ResumeName.create(notification, "職務経歴書A"),
                LocalDate.now(),
                FullName.create(notification, "山田", "太郎"),
                List.of(Career.create(notification, CompanyName.create(notification, "株式会社ABC"),
                        Period.create(notification, YearMonth.of(2024, 1), null, true))),
                List.of(),
                List.of(),
                List.of(),
                List.of(),
                List.of());

        Career overlappingCareer = Career.create(notification, CompanyName.create(notification, "株式会社DEF"),
                Period.create(notification, YearMonth.of(2024, 2), null, true));

        Notification domainNotification = new Notification();

        assertThatThrownBy(() -> resume.addCareer(domainNotification, overlappingCareer))
                .isInstanceOf(DomainException.class)
                .hasMessageContaining("株式会社DEFと株式会社ABCの期間が重複しています。");
    }

    @Test
    @DisplayName("期間が重なる職歴を追加するとDomainExceptionをスローする")
    void test10() {
        Resume resume = createSampleResume();

        Career overlappingCareer = Career.create(notification, CompanyName.create(notification, "株式会社DEF"),
                Period.create(notification, YearMonth.of(2023, 10), YearMonth.of(2024, 11), false));

        Notification domainNotification = new Notification();

        assertThatThrownBy(() -> resume.addCareer(domainNotification, overlappingCareer))
                .isInstanceOf(DomainException.class)
                .hasMessageContaining("株式会社DEFと株式会社ABCの期間が重複しています。");
    }

    @Test
    @DisplayName("期間が一部重なる職歴を追加するとDomainExceptionをスローする")
    void test11() {
        Resume resume = createSampleResume();

        Career overlappingCareer = Career.create(notification, CompanyName.create(notification, "株式会社DEF"),
                Period.create(notification, YearMonth.of(2023, 11), YearMonth.of(2024, 6), false));

        Notification domainNotification = new Notification();

        assertThatThrownBy(() -> resume.addCareer(domainNotification, overlappingCareer))
                .isInstanceOf(DomainException.class)
                .hasMessageContaining("株式会社DEFと株式会社ABCの期間が重複しています。");
    }

    @Test
    @DisplayName("正常な値で職歴を更新する")
    void test12() {
        Resume beforeResume = createSampleResume();
        Career newCareer = Career.reconstruct(beforeResume.getCareers().get(0).getId(),
                CompanyName.create(notification, "株式会社DEF"),
                Period.create(notification, YearMonth.of(2024, 1), null, true));
        Notification domainNotification = new Notification();

        Resume afterResume = beforeResume.updateCareer(domainNotification, newCareer);

        // 更新した職歴がリストに含まれている
        assertThat(afterResume.getCareers().contains(newCareer)).isTrue();
        // 職歴リストのサイズが変わらない
        assertThat(afterResume.getCareers().size()).isEqualTo(beforeResume.getCareers().size());
        // 更新した職歴の値が正しい
        assertThat(afterResume.getCareers().get(0).getCompanyName()).isEqualTo(newCareer.getCompanyName());
        assertThat(afterResume.getCareers().get(0).getPeriod()).isEqualTo(newCareer.getPeriod());
        assertThat(afterResume.getCareers().get(0).getId()).isEqualTo(beforeResume.getCareers().get(0).getId());
    }

    @Test
    @DisplayName("職歴を削除する")
    void test13() {
        Resume beforeResume = createSampleResume();
        Career newCareer = Career.create(notification, CompanyName.create(notification, "株式会社DEF"),
                Period.create(notification, YearMonth.of(2024, 1), null, true));
        Notification domainNotification = new Notification();

        Resume afterResume = beforeResume.addCareer(domainNotification, newCareer);
        // 削除1回目(2件 → 1件)
        Resume deletedResume = afterResume.removeCareer(newCareer.getId());

        // 削除した職歴がリストに含まれていない
        assertThat(deletedResume.getCareers().contains(newCareer)).isFalse();
        // 職歴リストのサイズが減少している
        assertThat(deletedResume.getCareers().size()).isEqualTo(afterResume.getCareers().size() - 1);

        // 削除2回目(1件 → 0件)
        Resume deletedResume2 = deletedResume.removeCareer(deletedResume.getCareers().get(0).getId());
        // 職歴リストが空になっている
        assertThat(deletedResume2.getCareers().isEmpty()).isTrue();
    }

    @Test
    @DisplayName("正常な値でプロジェクトを追加する")
    void test14() {
        Resume beforeResume = createSampleResume();
        Project newProject = createSampleProject();
        Notification domainNotification = new Notification();

        Resume afterResume = beforeResume.addProject(domainNotification, newProject);

        // 新しいプロジェクトがリストに含まれている
        assertThat(afterResume.getProjects().contains(newProject)).isTrue();
        // プロジェクトリストのサイズが増加している
        assertThat(afterResume.getProjects().size()).isEqualTo(beforeResume.getProjects().size() + 1);
    }

    @Test
    @DisplayName("職歴に存在しない会社名のプロジェクトを追加するとDomainExceptionをスローする")
    void test15() {
        Resume resume = createSampleResume();
        Project notExistProject = createSampleProject().changeCompanyName(notification,
                CompanyName.create(notification, "株式会社ZZZ"));

        Notification domainNotification = new Notification();

        assertThatThrownBy(() -> resume.addProject(domainNotification, notExistProject))
                .isInstanceOf(DomainException.class)
                .hasMessageContaining("株式会社ZZZは職歴に存在しません。職歴に存在する会社名を選択してください。");
    }

    @Test
    @DisplayName("正常な値でプロジェクトを更新する")
    void test16() {
        Resume beforeResume = createSampleResume();

        // 更新対象のプロジェクトを取得し、値を変更
        Project originalProject = beforeResume.getProjects().get(0);

        TechStack.Frontend updatedFrontend = TechStack.Frontend.create(
                List.of("JavaScript", "TypeScript"),
                List.of("React"),
                List.of("Redux", "Axios", "Lodash"),
                List.of("Vite"),
                List.of("npm"),
                List.of("ESLint"),
                List.of("Prettier"),
                List.of("Jest", "Enzyme"));

        TechStack.Backend updatedBackend = TechStack.Backend.create(
                List.of("Node.js"),
                List.of("Express"),
                List.of("Prisma"),
                List.of("npm"),
                List.of("npm"),
                List.of("ESLint"),
                List.of("Prettier"),
                List.of("Jest"),
                List.of("Prisma ORM"),
                List.of("JWT"));

        TechStack.Infrastructure updatedInfrastructure = TechStack.Infrastructure.create(
                List.of("Azure"),
                List.of("Ubuntu 22.04"),
                List.of("Kubernetes"),
                List.of("MySQL"),
                List.of("Apache"),
                List.of("CircleCI"),
                List.of("Ansible"),
                List.of("Grafana"),
                List.of("Azure Monitor"));

        TechStack.Tools updatedTools = TechStack.Tools.create(
                List.of("GitLab"),
                List.of("Asana"),
                List.of("Teams"),
                List.of("Notion"),
                List.of("Insomnia"),
                List.of("Sketch"),
                List.of("WebStorm"),
                List.of("Docker Desktop"));

        TechStack updatedTechStack = TechStack.create(
                updatedFrontend,
                updatedBackend,
                updatedInfrastructure,
                updatedTools);

        Project updatedProject = Project.reconstruct(
                originalProject.getId(),
                originalProject.getCompanyName(), // 会社名は変更しない
                originalProject.getPeriod(),
                "新しいプロジェクト名",
                "新しいプロジェクト概要",
                "10人",
                "マネージャー",
                "新しい成果内容",
                Project.Process.create(false, true, true, false, true, true, false),
                updatedTechStack);

        Notification domainNotification = new Notification();

        Resume afterResume = beforeResume.updateProject(domainNotification, updatedProject);

        // 更新したプロジェクトがリストに含まれている
        assertThat(afterResume.getProjects().contains(updatedProject)).isTrue();
        // プロジェクトリストのサイズが変わらない
        assertThat(afterResume.getProjects().size()).isEqualTo(beforeResume.getProjects().size());
        // 更新したプロジェクトの値が正しい
        assertAll(
                () -> assertThat(afterResume.getProjects().get(0).getId()).isEqualTo(originalProject.getId()),
                () -> assertThat(afterResume.getProjects().get(0).getCompanyName())
                        .isEqualTo(originalProject.getCompanyName()),
                () -> assertThat(afterResume.getProjects().get(0).getPeriod()).isEqualTo(originalProject.getPeriod()),
                () -> assertThat(afterResume.getProjects().get(0).getName()).isEqualTo("新しいプロジェクト名"),
                () -> assertThat(afterResume.getProjects().get(0).getOverview()).isEqualTo("新しいプロジェクト概要"),
                () -> assertThat(afterResume.getProjects().get(0).getTeamComp()).isEqualTo("10人"),
                () -> assertThat(afterResume.getProjects().get(0).getRole()).isEqualTo("マネージャー"),
                () -> assertThat(afterResume.getProjects().get(0).getAchievement()).isEqualTo("新しい成果内容"),
                () -> assertThat(afterResume.getProjects().get(0).getProcess())
                        .isEqualTo(Project.Process.create(false, true, true, false, true, true, false)),
                () -> assertThat(afterResume.getProjects().get(0).getTechStack().getFrontend().getLanguages())
                        .isEqualTo(List.of("JavaScript", "TypeScript")),
                () -> assertThat(afterResume.getProjects().get(0).getTechStack().getFrontend().getFrameworks())
                        .isEqualTo(List.of("React")),
                () -> assertThat(afterResume.getProjects().get(0).getTechStack().getInfrastructure().getClouds())
                        .isEqualTo(List.of("Azure")),
                () -> assertThat(afterResume.getProjects().get(0).getTechStack().getTools().getSourceControls())
                        .isEqualTo(List.of("GitLab")));
    }

    @Test
    @DisplayName("プロジェクトを削除する")
    void test17() {
        Resume beforeResume = createSampleResume();

        TechStack.Frontend frontend = TechStack.Frontend.create(
                List.of("TypeScript"),
                List.of("React"),
                List.of("React Query"),
                List.of("Vite"),
                List.of("npm"),
                List.of("ESLint"),
                List.of("Prettier"),
                List.of("Vitest"));

        TechStack.Backend backend = TechStack.Backend.create(
                List.of("Python"),
                List.of("Flask"),
                List.of("Requests"),
                List.of("Poetry"),
                List.of("Poetry"),
                List.of(),
                List.of(),
                List.of("Pytest"),
                List.of("SQLAlchemy"),
                List.of());

        TechStack.Infrastructure infrastructure = TechStack.Infrastructure.create(
                List.of("AWS"),
                List.of("Amazon Linux 2023"),
                List.of("Docker"),
                List.of("PostgreSQL"),
                List.of("Nginx"),
                List.of("GitHub Actions"),
                List.of("Terraform"),
                List.of(),
                List.of());

        TechStack.Tools tools = TechStack.Tools.create(
                List.of("Git"),
                List.of("Jira"),
                List.of("Slack"),
                List.of("Confluence"),
                List.of("Postman"),
                List.of("Figma"),
                List.of("Visual Studio Code"),
                List.of("Docker Desktop"));

        TechStack techStack = TechStack.create(frontend, backend, infrastructure, tools);

        // 削除対象のプロジェクトを追加（職歴に存在する会社名を使用）
        Project newProject = Project.create(
                notification,
                CompanyName.create(notification, "株式会社ABC"),
                Period.create(notification, YearMonth.of(2022, 1), YearMonth.of(2023, 1), false),
                "プロジェクト概要",
                "プロジェクト名",
                "5人",
                "リーダー",
                "成果内容",
                Project.Process.create(true, false, true, false, true, false, true),
                techStack);

        Notification domainNotification = new Notification();

        Resume afterResume = beforeResume.addProject(domainNotification, newProject);

        // 削除1回目(2件 → 1件)
        Resume deletedResume = afterResume.removeProject(newProject.getId());
        // 削除したプロジェクトがリストに含まれていない
        assertThat(deletedResume.getProjects().contains(newProject)).isFalse();
        // プロジェクトリストのサイズが減少している
        assertThat(deletedResume.getProjects().size()).isEqualTo(afterResume.getProjects().size() - 1);

        // 削除2回目(1件 → 0件)
        Resume deletedResume2 = deletedResume.removeProject(deletedResume.getProjects().get(0).getId());
        // プロジェクトリストが空になっている
        assertThat(deletedResume2.getProjects().isEmpty()).isTrue();
    }

    @Test
    @DisplayName("資格を追加する")
    void test18() {
        Resume beforeResume = createSampleResume();
        Certification newCertification = Certification.create(notification, "応用情報技術者", YearMonth.of(2025, 2));
        Notification domainNotification = new Notification();

        Resume afterResume = beforeResume.addCertification(domainNotification, newCertification);

        // 新しい資格がリストに含まれている
        assertThat(afterResume.getCertifications().contains(newCertification)).isTrue();
        // 資格リストのサイズが増加している
        assertThat(afterResume.getCertifications().size()).isEqualTo(beforeResume.getCertifications().size() + 1);
    }

    @Test
    @DisplayName("資格を更新する")
    void test19() {
        Resume beforeResume = createSampleResume();
        Certification newCertification = Certification.reconstruct(beforeResume.getCertifications().get(0).getId(),
                "応用情報技術者", YearMonth.of(2025, 2));
        Notification domainNotification = new Notification();

        Resume afterResume = beforeResume.updateCertification(domainNotification, newCertification);

        // 更新した資格がリストに含まれている
        assertThat(afterResume.getCertifications().contains(newCertification)).isTrue();
        // 資格リストのサイズが変わらない
        assertThat(afterResume.getCertifications().size()).isEqualTo(beforeResume.getCertifications().size());
        // 更新した資格の値が正しい
        assertAll(
                () -> assertThat(afterResume.getCertifications().get(0).getName())
                        .isEqualTo(newCertification.getName()),
                () -> assertThat(afterResume.getCertifications().get(0).getDate())
                        .isEqualTo(newCertification.getDate()),
                () -> assertThat(afterResume.getCertifications().get(0).getId())
                        .isEqualTo(beforeResume.getCertifications().get(0).getId()));
    }

    @Test
    @DisplayName("資格を削除する")
    void test20() {
        Resume beforeResume = createSampleResume();
        Certification newCertification = Certification.create(notification, "応用情報技術者", YearMonth.of(2025, 2));
        Notification domainNotification = new Notification();

        Resume afterResume = beforeResume.addCertification(domainNotification, newCertification);

        // 削除1回目(2件 → 1件)
        Resume deletedResume = afterResume.removeCertification(newCertification.getId());
        // 削除した職歴がリストに含まれていない
        assertThat(deletedResume.getCertifications().contains(newCertification)).isFalse();
        // 職歴リストのサイズが減少している
        assertThat(deletedResume.getCertifications().size()).isEqualTo(afterResume.getCertifications().size() - 1);

        // 削除2回目(1件 → 0件)
        Resume deletedResume2 = deletedResume.removeCertification(deletedResume.getCertifications().get(0).getId());
        // 職歴リストが空になっている
        assertThat(deletedResume2.getCertifications().isEmpty()).isTrue();
    }

    @Test
    @DisplayName("ポートフォリオを追加する")
    void test21() {
        Resume beforeResume = createSampleResume();
        Portfolio newPortfolio = Portfolio.create(
                notification,
                "新しいポートフォリオ",
                "新しいポートフォリオの概要",
                "新しい技術スタック",
                Link.create(notification, "https://new-portfolio.com"));

        Notification domainNotification = new Notification();

        Resume afterResume = beforeResume.addPortfolio(domainNotification, newPortfolio);

        // 新しいポートフォリオがリストに含まれている
        assertThat(afterResume.getPortfolios().contains(newPortfolio)).isTrue();
        // ポートフォリオリストのサイズが増加している
        assertThat(afterResume.getPortfolios().size()).isEqualTo(beforeResume.getPortfolios().size() + 1);
    }

    @Test
    @DisplayName("ポートフォリオを更新する")
    void test22() {
        Resume beforeResume = createSampleResume();
        Portfolio updatedPortfolio = Portfolio.reconstruct(
                beforeResume.getPortfolios().get(0).getId(),
                "更新されたポートフォリオ",
                "更新されたポートフォリオの概要",
                "更新された技術スタック",
                Link.create(notification, "https://updated-portfolio.com"));

        Notification domainNotification = new Notification();

        Resume afterResume = beforeResume.updatePortfolio(domainNotification, updatedPortfolio);

        // 更新したポートフォリオがリストに含まれている
        assertThat(afterResume.getPortfolios().contains(updatedPortfolio)).isTrue();
        // ポートフォリオリストのサイズが変わらない
        assertThat(afterResume.getPortfolios().size()).isEqualTo(beforeResume.getPortfolios().size());
        // 更新したポートフォリオの値が正しい
        assertAll(
                () -> assertThat(afterResume.getPortfolios().get(0).getName()).isEqualTo(updatedPortfolio.getName()),
                () -> assertThat(afterResume.getPortfolios().get(0).getOverview())
                        .isEqualTo(updatedPortfolio.getOverview()),
                () -> assertThat(afterResume.getPortfolios().get(0).getTechStack())
                        .isEqualTo(updatedPortfolio.getTechStack()),
                () -> assertThat(afterResume.getPortfolios().get(0).getLink()).isEqualTo(updatedPortfolio.getLink()),
                () -> assertThat(afterResume.getPortfolios().get(0).getId())
                        .isEqualTo(beforeResume.getPortfolios().get(0).getId()));
    }

    @Test
    @DisplayName("ポートフォリオを削除する")
    void test23() {
        Resume beforeResume = createSampleResume();
        Portfolio newPortfolio = Portfolio.create(
                notification,
                "削除対象のポートフォリオ",
                "削除対象の概要",
                "削除対象の技術スタック",
                Link.create(notification, "https://delete-portfolio.com"));

        Notification domainNotification = new Notification();

        Resume afterResume = beforeResume.addPortfolio(domainNotification, newPortfolio);

        // 削除1回目(2件 → 1件)
        Resume deletedResume = afterResume.removePortfolio(newPortfolio.getId());
        // 削除したポートフォリオがリストに含まれていない
        assertThat(deletedResume.getPortfolios().contains(newPortfolio)).isFalse();
        // ポートフォリオリストのサイズが減少している
        assertThat(deletedResume.getPortfolios().size()).isEqualTo(afterResume.getPortfolios().size() - 1);

        // 削除2回目(1件 → 0件)
        Resume deletedResume2 = deletedResume.removePortfolio(deletedResume.getPortfolios().get(0).getId());
        // ポートフォリオリストが空になっている
        assertThat(deletedResume2.getPortfolios().isEmpty()).isTrue();
    }

    @Test
    @DisplayName("ソーシャルリンクを追加する")
    void test24() {
        Resume beforeResume = createSampleResume();
        SocialLink newSocialLink = SocialLink.create(
                notification,
                "Twitter",
                Link.create(notification, "https://twitter.com/user"));

        Notification domainNotification = new Notification();

        Resume afterResume = beforeResume.addSociealLink(domainNotification, newSocialLink);

        // 新しいソーシャルリンクがリストに含まれている
        assertThat(afterResume.getSocialLinks().contains(newSocialLink)).isTrue();
        // ソーシャルリンクリストのサイズが増加している
        assertThat(afterResume.getSocialLinks().size()).isEqualTo(beforeResume.getSocialLinks().size() + 1);
    }

    @Test
    @DisplayName("ソーシャルリンクを更新する")
    void test25() {
        Resume beforeResume = createSampleResume();
        SocialLink updatedSocialLink = SocialLink.reconstruct(
                beforeResume.getSocialLinks().get(0).getId(),
                "LinkedIn",
                Link.create(notification, "https://linkedin.com/in/user"));

        Notification domainNotification = new Notification();

        Resume afterResume = beforeResume.updateSociealLink(domainNotification, updatedSocialLink);

        // 更新したソーシャルリンクがリストに含まれている
        assertThat(afterResume.getSocialLinks().contains(updatedSocialLink)).isTrue();
        // ソーシャルリンクリストのサイズが変わらない
        assertThat(afterResume.getSocialLinks().size()).isEqualTo(beforeResume.getSocialLinks().size());
        // 更新したソーシャルリンクの値が正しい
        assertThat(afterResume.getSocialLinks().get(0).getName()).isEqualTo(updatedSocialLink.getName());
        assertThat(afterResume.getSocialLinks().get(0).getLink()).isEqualTo(updatedSocialLink.getLink());
        assertThat(afterResume.getSocialLinks().get(0).getId()).isEqualTo(beforeResume.getSocialLinks().get(0).getId());
    }

    @Test
    @DisplayName("ソーシャルリンクを削除する")
    void test26() {
        Resume beforeResume = createSampleResume();
        SocialLink newSocialLink = SocialLink.create(
                notification,
                "Facebook",
                Link.create(notification, "https://facebook.com/user"));

        Notification domainNotification = new Notification();

        Resume afterResume = beforeResume.addSociealLink(domainNotification, newSocialLink);

        // 削除1回目(2件 → 1件)
        Resume deletedResume = afterResume.removeSociealLink(newSocialLink.getId());
        // 削除したソーシャルリンクがリストに含まれていない
        assertThat(deletedResume.getSocialLinks().contains(newSocialLink)).isFalse();
        // ソーシャルリンクリストのサイズが減少している
        assertThat(deletedResume.getSocialLinks().size()).isEqualTo(afterResume.getSocialLinks().size() - 1);

        // 削除2回目(1件 → 0件)
        Resume deletedResume2 = deletedResume.removeSociealLink(deletedResume.getSocialLinks().get(0).getId());
        // ソーシャルリンクリストが空になっている
        assertThat(deletedResume2.getSocialLinks().isEmpty()).isTrue();
    }

    @Test
    @DisplayName("自己PRを追加する")
    void test27() {
        Resume beforeResume = createSampleResume();
        SelfPromotion newSelfPromotion = SelfPromotion.create(
                notification,
                "新しいタイトル",
                "新しい自己PRの内容");

        Notification domainNotification = new Notification();

        Resume afterResume = beforeResume.addSelfPromotion(domainNotification, newSelfPromotion);

        // 新しい自己PRがリストに含まれている
        assertThat(afterResume.getSelfPromotions().contains(newSelfPromotion)).isTrue();
        // 自己PRリストのサイズが増加してい。
        assertThat(afterResume.getSelfPromotions().size()).isEqualTo(beforeResume.getSelfPromotions().size() + 1);
    }

    @Test
    @DisplayName("自己PRを更新する")
    void test28() {
        Resume beforeResume = createSampleResume();
        SelfPromotion updatedSelfPromotion = SelfPromotion.reconstruct(
                beforeResume.getSelfPromotions().get(0).getId(),
                "更新されたタイトル",
                "更新された自己PRの内容");

        Notification domainNotification = new Notification();

        Resume afterResume = beforeResume.updateSelfPromotion(domainNotification, updatedSelfPromotion);

        // 更新した自己PRがリストに含まれている
        assertThat(afterResume.getSelfPromotions().contains(updatedSelfPromotion)).isTrue();
        // 自己PRリストのサイズが変わらない
        assertThat(afterResume.getSelfPromotions().size()).isEqualTo(beforeResume.getSelfPromotions().size());
        // 更新した自己PRの値が正しい
        assertAll(
                () -> assertThat(afterResume.getSelfPromotions().get(0).getTitle())
                        .isEqualTo(updatedSelfPromotion.getTitle()),
                () -> assertThat(afterResume.getSelfPromotions().get(0).getContent())
                        .isEqualTo(updatedSelfPromotion.getContent()),
                () -> assertThat(afterResume.getSelfPromotions().get(0).getId())
                        .isEqualTo(beforeResume.getSelfPromotions().get(0).getId()));
    }

    @Test
    @DisplayName("自己PRを削除する")
    void test29() {
        Resume beforeResume = createSampleResume();
        SelfPromotion newSelfPromotion = SelfPromotion.create(
                notification,
                "削除対象のタイトル",
                "削除対象の自己PRの内容");

        Notification domainNotification = new Notification();

        Resume afterResume = beforeResume.addSelfPromotion(domainNotification, newSelfPromotion);

        // 削除1回目(2件 → 1件)
        Resume deletedResume = afterResume.removeSelfPromotion(newSelfPromotion.getId());
        // 削除した自己PRがリストに含まれていない
        assertThat(deletedResume.getSelfPromotions().contains(newSelfPromotion)).isFalse();
        // 自己PRリストのサイズが減少している
        assertThat(deletedResume.getSelfPromotions().size()).isEqualTo(afterResume.getSelfPromotions().size() - 1);

        // 削除2回目(1件 → 0件)
        Resume deletedResume2 = deletedResume.removeSelfPromotion(deletedResume.getSelfPromotions().get(0).getId());
        // 自己PRリストが空になっている
        assertThat(deletedResume2.getSelfPromotions().isEmpty()).isTrue();
    }

    @Test
    @DisplayName("氏名を変更する")
    void test30() {
        Resume originalResume = createSampleResume();
        FullName newFullName = FullName.create(notification, "変更", "しました");
        Notification domainNotification = new Notification();

        Resume updatedResume = originalResume.ChangeFullName(domainNotification, newFullName);

        assertThat(updatedResume.getFullName()).isEqualTo(newFullName);
    }

    /**
     * 職務経歴書のサンプルエンティティを作成する補助メソッド
     */
    private Resume createSampleResume() {
        UUID userId = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        return Resume.create(
                notification,
                userId,
                ResumeName.create(notification, "職務経歴書A"),
                LocalDate.now(),
                FullName.create(notification, "山田", "太郎"),
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
        CompanyName companyName = CompanyName.create(notification, "株式会社ABC");
        return Career.create(notification, companyName, period);
    }

    /**
     * プロジェクトのサンプルエンティティを作成する補助メソッド
     */
    private Project createSampleProject() {
        Period period = Period.create(notification, YearMonth.of(2021, 1), YearMonth.of(2023, 12), false);
        CompanyName companyName = CompanyName.create(notification, "株式会社ABC");

        TechStack.Frontend frontend = TechStack.Frontend.create(
                List.of("TypeScript"),
                List.of("React"),
                List.of("MUI"),
                List.of("Vite"),
                List.of("npm"),
                List.of("ESLint"),
                List.of("Prettier"),
                List.of("Vitest"));

        TechStack.Backend backend = TechStack.Backend.create(
                List.of("Java", "Python"),
                List.of("Spring Framework"),
                List.of("Lombok", "Jackson"),
                List.of("Gradle"),
                List.of("Gradle"),
                List.of("CheckStyle"),
                List.of("Google Java Format"),
                List.of("JUnit", "Mockito"),
                List.of("MyBatis"),
                List.of("Spring Security"));

        TechStack.Infrastructure infrastructure = TechStack.Infrastructure.create(
                List.of("AWS"),
                List.of("RHEL9.4"),
                List.of("Docker"),
                List.of("PostgreSQL"),
                List.of("Nginx"),
                List.of("GitHub Actions"),
                List.of("Terraform"),
                List.of("Prometheus"),
                List.of("CloudWatch"));

        TechStack.Tools tools = TechStack.Tools.create(
                List.of("Git"),
                List.of("Jira"),
                List.of("Slack"),
                List.of("Confluence"),
                List.of("Postman"),
                List.of("Figma"),
                List.of("Visual Studio Code"),
                List.of("Windows"));

        TechStack techStack = TechStack.create(frontend, backend, infrastructure, tools);

        Project.Process process = Project.Process.create(true, true, true, true, true, true, true);
        return Project.create(
                notification, companyName, period, "プロジェクト名", "プロジェクト概要", "5人", "リーダー", "成果内容", process, techStack);
    }

    /**
     * 資格のサンプルエンティティを作成する補助メソッド
     */
    private Certification createSampleCertification() {
        return Certification.create(notification, "基本情報技術者", YearMonth.of(2025, 1));
    }

    /**
     * ポートフォリオのサンプルエンティティを作成する補助メソッド
     */
    private Portfolio createSamplePortfolio() {
        return Portfolio.create(notification, "ポートフォリオ名", "概要", "技術スタック",
                Link.create(notification, "https://portfolio.com"));
    }

    /**
     * ソーシャルリンクのサンプルエンティティを作成する補助メソッド
     */
    private SocialLink createSampleSociealLink() {
        return SocialLink.create(notification, "GitHub", Link.create(notification, "https://github.com/user"));
    }

    /**
     * 自己PRのサンプルエンティティを作成する補助メソッド
     */
    private SelfPromotion createSampleSelfPromotion() {
        return SelfPromotion.create(notification, "自己PRタイトル", "自己PR内容");
    }
}
