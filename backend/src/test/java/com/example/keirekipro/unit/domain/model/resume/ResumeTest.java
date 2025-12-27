package com.example.keirekipro.unit.domain.model.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
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
import com.example.keirekipro.domain.model.resume.SnsPlatform;
import com.example.keirekipro.domain.model.resume.TechStack;
import com.example.keirekipro.domain.shared.exception.DomainException;
import com.example.keirekipro.shared.ErrorCollector;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ResumeTest {

    @Mock
    private ErrorCollector errorCollector;

    @Test
    @DisplayName("新規構築用コンストラクタでインスタンス化する")
    void test1() {
        Resume resume = createSampleResume();

        assertThat(resume).isNotNull();
        assertThat(resume.getId()).isNotNull();
        assertThat(resume.getUserId()).isEqualTo(UUID.fromString("123e4567-e89b-12d3-a456-426614174000"));
        assertThat(resume.getName()).isEqualTo(ResumeName.create(errorCollector, "職務経歴書A"));
        assertThat(resume.getDate()).isEqualTo(LocalDate.now());
        assertThat(resume.getFullName()).isEqualTo(FullName.create(errorCollector, "山田", "太郎"));
        assertThat(resume.getCreatedAt()).isNotNull();
        assertThat(resume.getUpdatedAt()).isNotNull();
    }

    @Test
    @DisplayName("エラー収集オブジェクト内にエラーがある状態で、新規構築用コンストラクタでインスタンス化するとDomainExceptionをスローする")
    void test2() {
        ErrorCollector invaliderrorCollector = new ErrorCollector();
        invaliderrorCollector.addError("name", "職務経歴書名は入力必須です。");
        UUID userId = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> {
            Resume.create(
                    invaliderrorCollector,
                    userId,
                    null, // 名前がnull
                    LocalDate.now(),
                    FullName.create(errorCollector, "山田", "太郎"),
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
                ResumeName.create(errorCollector, "職務経歴書A"),
                LocalDate.of(2023, 1, 1),
                FullName.create(errorCollector, "山田", "太郎"),
                LocalDateTime.of(2023, 1, 1, 0, 0),
                LocalDateTime.of(2023, 1, 2, 0, 0),
                List.of(createSampleCareer()),
                List.of(createSampleProject()),
                List.of(createSampleCertification()),
                List.of(createSamplePortfolio()),
                List.of(createSampleSnsPlatform()),
                List.of(createSampleSelfPromotion()));

        assertThat(resume).isNotNull();
        assertThat(resume.getId()).isEqualTo(id);
        assertThat(resume.getUserId()).isEqualTo(userId);
        assertThat(resume.getName()).isEqualTo(ResumeName.create(errorCollector, "職務経歴書A"));
        assertThat(resume.getDate()).isEqualTo(LocalDate.of(2023, 1, 1));
        assertThat(resume.getFullName()).isEqualTo(FullName.create(errorCollector, "山田", "太郎"));
        assertThat(resume.getCreatedAt()).isEqualTo(LocalDateTime.of(2023, 1, 1, 0, 0));
        assertThat(resume.getUpdatedAt()).isEqualTo(LocalDateTime.of(2023, 1, 2, 0, 0));
        assertThat(resume.getCareers().size()).isEqualTo(1);
        assertThat(resume.getProjects().size()).isEqualTo(1);
        assertThat(resume.getCertifications().size()).isEqualTo(1);
        assertThat(resume.getPortfolios().size()).isEqualTo(1);
        assertThat(resume.getSnsPlatforms().size()).isEqualTo(1);
        assertThat(resume.getSelfPromotions().size()).isEqualTo(1);
    }

    @Test
    @DisplayName("職務経歴書名を変更する")
    void test4() {
        Resume originalResume = createSampleResume();
        ResumeName newName = ResumeName.create(errorCollector, "新しい履歴書名");
        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume updatedResume = originalResume.changeName(domainerrorCollector, newName);

        assertThat(updatedResume.getName()).isEqualTo(newName);
    }

    @Test
    @DisplayName("日付を変更する")
    void test5() {
        Resume originalResume = createSampleResume();
        LocalDate newDate = LocalDate.of(2025, 1, 1);
        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume updatedResume = originalResume.changeDate(domainerrorCollector, newDate);

        assertThat(updatedResume.getDate()).isEqualTo(newDate);
    }

    @Test
    @DisplayName("正常な値で職歴を追加する")
    void test6() {
        Resume beforeResume = createSampleResume();
        Career newCareer = Career.create(errorCollector, CompanyName.create(errorCollector, "株式会社DEF"),
                Period.create(errorCollector, YearMonth.of(2024, 1), null, true));
        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume afterResume = beforeResume.addCareer(domainerrorCollector, newCareer);

        assertThat(afterResume.getCareers().contains(newCareer)).isTrue();
        assertThat(afterResume.getCareers().size()).isEqualTo(beforeResume.getCareers().size() + 1);
    }

    @Test
    @DisplayName("継続中の職歴と期間が重なる職歴を追加するとDomainExceptionをスローする")
    void test7() {
        UUID userId = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        Resume resume = Resume.create(
                errorCollector,
                userId,
                ResumeName.create(errorCollector, "職務経歴書A"),
                LocalDate.now(),
                FullName.create(errorCollector, "山田", "太郎"),
                List.of(Career.create(errorCollector, CompanyName.create(errorCollector, "株式会社ABC"),
                        Period.create(errorCollector, YearMonth.of(2024, 1), null, true))),
                List.of(),
                List.of(),
                List.of(),
                List.of(),
                List.of());

        Career overlappingCareer = Career.create(errorCollector, CompanyName.create(errorCollector, "株式会社DEF"),
                Period.create(errorCollector, YearMonth.of(2024, 2), YearMonth.of(2024, 3), false));

        ErrorCollector domainerrorCollector = new ErrorCollector();

        assertThatThrownBy(() -> resume.addCareer(domainerrorCollector, overlappingCareer))
                .isInstanceOf(DomainException.class)
                .hasMessageContaining("「株式会社DEF」と「株式会社ABC」の期間が重複しています。");
    }

    @Test
    @DisplayName("同じ期間の職歴を追加するとDomainExceptionをスローする")
    void test8() {
        Resume resume = createSampleResume();

        Career overlappingCareer = Career.create(errorCollector, CompanyName.create(errorCollector, "株式会社DEF"),
                Period.create(errorCollector, YearMonth.of(2020, 1), YearMonth.of(2023, 12), false));

        ErrorCollector domainerrorCollector = new ErrorCollector();

        assertThatThrownBy(() -> resume.addCareer(domainerrorCollector, overlappingCareer))
                .isInstanceOf(DomainException.class)
                .hasMessageContaining("「株式会社DEF」と「株式会社ABC」の期間が重複しています。");
    }

    @Test
    @DisplayName("継続中の職歴が存在する状態で、継続中の職歴を追加するとDomainExceptionをスローする")
    void test9() {
        UUID userId = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        Resume resume = Resume.create(
                errorCollector,
                userId,
                ResumeName.create(errorCollector, "職務経歴書A"),
                LocalDate.now(),
                FullName.create(errorCollector, "山田", "太郎"),
                List.of(Career.create(errorCollector, CompanyName.create(errorCollector, "株式会社ABC"),
                        Period.create(errorCollector, YearMonth.of(2024, 1), null, true))),
                List.of(),
                List.of(),
                List.of(),
                List.of(),
                List.of());

        Career overlappingCareer = Career.create(errorCollector, CompanyName.create(errorCollector, "株式会社DEF"),
                Period.create(errorCollector, YearMonth.of(2024, 2), null, true));

        ErrorCollector domainerrorCollector = new ErrorCollector();

        assertThatThrownBy(() -> resume.addCareer(domainerrorCollector, overlappingCareer))
                .isInstanceOf(DomainException.class)
                .hasMessageContaining("「株式会社DEF」と「株式会社ABC」の期間が重複しています。");
    }

    @Test
    @DisplayName("期間が重なる職歴を追加するとDomainExceptionをスローする")
    void test10() {
        Resume resume = createSampleResume();

        Career overlappingCareer = Career.create(errorCollector, CompanyName.create(errorCollector, "株式会社DEF"),
                Period.create(errorCollector, YearMonth.of(2023, 10), YearMonth.of(2024, 11), false));

        ErrorCollector domainerrorCollector = new ErrorCollector();

        assertThatThrownBy(() -> resume.addCareer(domainerrorCollector, overlappingCareer))
                .isInstanceOf(DomainException.class)
                .hasMessageContaining("「株式会社DEF」と「株式会社ABC」の期間が重複しています。");
    }

    @Test
    @DisplayName("期間が一部重なる職歴を追加するとDomainExceptionをスローする")
    void test11() {
        Resume resume = createSampleResume();

        Career overlappingCareer = Career.create(errorCollector, CompanyName.create(errorCollector, "株式会社DEF"),
                Period.create(errorCollector, YearMonth.of(2023, 11), YearMonth.of(2024, 6), false));

        ErrorCollector domainerrorCollector = new ErrorCollector();

        assertThatThrownBy(() -> resume.addCareer(domainerrorCollector, overlappingCareer))
                .isInstanceOf(DomainException.class)
                .hasMessageContaining("「株式会社DEF」と「株式会社ABC」の期間が重複しています。");
    }

    @Test
    @DisplayName("正常な値で職歴を更新する")
    void test12() {
        Resume beforeResume = createSampleResume();
        Career newCareer = Career.reconstruct(beforeResume.getCareers().get(0).getId(),
                CompanyName.create(errorCollector, "株式会社DEF"),
                Period.create(errorCollector, YearMonth.of(2024, 1), null, true));
        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume afterResume = beforeResume.updateCareer(domainerrorCollector, newCareer);

        Career actualCareer = afterResume.getCareers().stream()
                .filter(career -> career.getId().equals(newCareer.getId()))
                .findFirst()
                .orElseThrow();

        // 更新した職歴がリストに含まれている
        assertThat(afterResume.getCareers().contains(newCareer)).isTrue();
        // 職歴リストのサイズが変わらない
        assertThat(afterResume.getCareers().size()).isEqualTo(beforeResume.getCareers().size());
        // 更新した職歴の値が正しい（順序に依存しない）
        assertAll(
                () -> assertThat(actualCareer.getId()).isEqualTo(newCareer.getId()),
                () -> assertThat(actualCareer.getCompanyName()).isEqualTo(newCareer.getCompanyName()),
                () -> assertThat(actualCareer.getPeriod()).isEqualTo(newCareer.getPeriod()));
    }

    @Test
    @DisplayName("職歴を削除する")
    void test13() {
        UUID userId = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        Career baseCareer = createSampleCareer();

        // プロジェクトが存在しない状態の職務経歴書を作成する
        Resume beforeResume = Resume.create(
                errorCollector,
                userId,
                ResumeName.create(errorCollector, "職務経歴書A"),
                LocalDate.now(),
                FullName.create(errorCollector, "山田", "太郎"),
                List.of(baseCareer),
                List.of(), // プロジェクトはなし
                List.of(createSampleCertification()),
                List.of(createSamplePortfolio()),
                List.of(createSampleSnsPlatform()),
                List.of(createSampleSelfPromotion()));

        Career newCareer = Career.create(errorCollector, CompanyName.create(errorCollector, "株式会社DEF"),
                Period.create(errorCollector, YearMonth.of(2024, 1), null, true));
        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume afterResume = beforeResume.addCareer(domainerrorCollector, newCareer);

        // 削除1回目(2件 → 1件) - 追加した職歴を削除
        Resume deletedResume = afterResume.removeCareer(newCareer.getId());

        // 削除した職歴がリストに含まれていない
        assertThat(deletedResume.getCareers().contains(newCareer)).isFalse();
        // 職歴リストのサイズが減少している
        assertThat(deletedResume.getCareers().size()).isEqualTo(afterResume.getCareers().size() - 1);

        // 削除2回目(1件 → 0件) - 残っている既存の職歴を削除
        Resume deletedResume2 = deletedResume.removeCareer(baseCareer.getId());
        // 職歴リストが空になっている
        assertThat(deletedResume2.getCareers().isEmpty()).isTrue();
    }

    @Test
    @DisplayName("正常な値でプロジェクトを追加する")
    void test14() {
        Resume beforeResume = createSampleResume();
        Project newProject = createSampleProject();
        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume afterResume = beforeResume.addProject(domainerrorCollector, newProject);

        // 新しいプロジェクトがリストに含まれている
        assertThat(afterResume.getProjects().contains(newProject)).isTrue();
        // プロジェクトリストのサイズが増加している
        assertThat(afterResume.getProjects().size()).isEqualTo(beforeResume.getProjects().size() + 1);
    }

    @Test
    @DisplayName("正常な値でプロジェクトを更新する")
    void test15() {
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

        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume afterResume = beforeResume.updateProject(domainerrorCollector, updatedProject);

        Project actualProject = afterResume.getProjects().stream()
                .filter(project -> project.getId().equals(updatedProject.getId()))
                .findFirst()
                .orElseThrow();

        // 更新したプロジェクトがリストに含まれている
        assertThat(afterResume.getProjects().contains(updatedProject)).isTrue();
        // プロジェクトリストのサイズが変わらない
        assertThat(afterResume.getProjects().size()).isEqualTo(beforeResume.getProjects().size());
        // 更新したプロジェクトの値が正しい（順序に依存しない）
        assertAll(
                () -> assertThat(actualProject.getId()).isEqualTo(originalProject.getId()),
                () -> assertThat(actualProject.getCompanyName()).isEqualTo(originalProject.getCompanyName()),
                () -> assertThat(actualProject.getPeriod()).isEqualTo(originalProject.getPeriod()),
                () -> assertThat(actualProject.getName()).isEqualTo("新しいプロジェクト名"),
                () -> assertThat(actualProject.getOverview()).isEqualTo("新しいプロジェクト概要"),
                () -> assertThat(actualProject.getTeamComp()).isEqualTo("10人"),
                () -> assertThat(actualProject.getRole()).isEqualTo("マネージャー"),
                () -> assertThat(actualProject.getAchievement()).isEqualTo("新しい成果内容"),
                () -> assertThat(actualProject.getProcess())
                        .isEqualTo(Project.Process.create(false, true, true, false, true, true, false)),
                () -> assertThat(actualProject.getTechStack().getFrontend().getLanguages())
                        .isEqualTo(List.of("JavaScript", "TypeScript")),
                () -> assertThat(actualProject.getTechStack().getFrontend().getFrameworks())
                        .isEqualTo(List.of("React")),
                () -> assertThat(actualProject.getTechStack().getInfrastructure().getClouds())
                        .isEqualTo(List.of("Azure")),
                () -> assertThat(actualProject.getTechStack().getTools().getSourceControls())
                        .isEqualTo(List.of("GitLab")));
    }

    @Test
    @DisplayName("プロジェクトを削除する")
    void test16() {
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
                errorCollector,
                CompanyName.create(errorCollector, "株式会社ABC"),
                Period.create(errorCollector, YearMonth.of(2022, 1), YearMonth.of(2023, 1), false),
                "プロジェクト概要",
                "プロジェクト名",
                "5人",
                "リーダー",
                "成果内容",
                Project.Process.create(true, false, true, false, true, false, true),
                techStack);

        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume afterResume = beforeResume.addProject(domainerrorCollector, newProject);

        // 削除1回目(2件 → 1件)
        Resume deletedResume = afterResume.removeProject(newProject.getId());
        // 削除したプロジェクトがリストに含まれていない
        assertThat(deletedResume.getProjects().contains(newProject)).isFalse();
        // プロジェクトリストのサイズが減少している
        assertThat(deletedResume.getProjects().size()).isEqualTo(afterResume.getProjects().size() - 1);

        // 削除2回目(1件 → 0件) - 残件のIDで削除（順序に依存しない）
        UUID remainingProjectId = deletedResume.getProjects().stream()
                .findFirst()
                .orElseThrow()
                .getId();

        Resume deletedResume2 = deletedResume.removeProject(remainingProjectId);
        // プロジェクトリストが空になっている
        assertThat(deletedResume2.getProjects().isEmpty()).isTrue();
    }

    @Test
    @DisplayName("資格を追加する")
    void test17() {
        Resume beforeResume = createSampleResume();
        Certification newCertification = Certification.create(errorCollector, "応用情報技術者", YearMonth.of(2025, 2));
        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume afterResume = beforeResume.addCertification(domainerrorCollector, newCertification);

        // 新しい資格がリストに含まれている
        assertThat(afterResume.getCertifications().contains(newCertification)).isTrue();
        // 資格リストのサイズが増加している
        assertThat(afterResume.getCertifications().size()).isEqualTo(beforeResume.getCertifications().size() + 1);
    }

    @Test
    @DisplayName("資格を更新する")
    void test18() {
        Resume beforeResume = createSampleResume();
        Certification newCertification = Certification.reconstruct(beforeResume.getCertifications().get(0).getId(),
                "応用情報技術者", YearMonth.of(2025, 2));
        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume afterResume = beforeResume.updateCertification(domainerrorCollector, newCertification);

        Certification actualCertification = afterResume.getCertifications().stream()
                .filter(certification -> certification.getId().equals(newCertification.getId()))
                .findFirst()
                .orElseThrow();

        // 更新した資格がリストに含まれている
        assertThat(afterResume.getCertifications().contains(newCertification)).isTrue();
        // 資格リストのサイズが変わらない
        assertThat(afterResume.getCertifications().size()).isEqualTo(beforeResume.getCertifications().size());
        // 更新した資格の値が正しい（順序に依存しない）
        assertAll(
                () -> assertThat(actualCertification.getName()).isEqualTo(newCertification.getName()),
                () -> assertThat(actualCertification.getDate()).isEqualTo(newCertification.getDate()),
                () -> assertThat(actualCertification.getId()).isEqualTo(newCertification.getId()));
    }

    @Test
    @DisplayName("資格を削除する")
    void test19() {
        Resume beforeResume = createSampleResume();
        Certification newCertification = Certification.create(errorCollector, "応用情報技術者", YearMonth.of(2025, 2));
        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume afterResume = beforeResume.addCertification(domainerrorCollector, newCertification);

        // 削除1回目(2件 → 1件)
        Resume deletedResume = afterResume.removeCertification(newCertification.getId());
        // 削除した職歴がリストに含まれていない
        assertThat(deletedResume.getCertifications().contains(newCertification)).isFalse();
        // 職歴リストのサイズが減少している
        assertThat(deletedResume.getCertifications().size()).isEqualTo(afterResume.getCertifications().size() - 1);

        // 削除2回目(1件 → 0件) - 残件のIDで削除（順序に依存しない）
        UUID remainingCertificationId = deletedResume.getCertifications().stream()
                .findFirst()
                .orElseThrow()
                .getId();

        Resume deletedResume2 = deletedResume.removeCertification(remainingCertificationId);
        // 職歴リストが空になっている
        assertThat(deletedResume2.getCertifications().isEmpty()).isTrue();
    }

    @Test
    @DisplayName("ポートフォリオを追加する")
    void test20() {
        Resume beforeResume = createSampleResume();
        Portfolio newPortfolio = Portfolio.create(
                errorCollector,
                "新しいポートフォリオ",
                "新しいポートフォリオの概要",
                "新しい技術スタック",
                Link.create(errorCollector, "https://new-portfolio.com"));

        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume afterResume = beforeResume.addPortfolio(domainerrorCollector, newPortfolio);

        // 新しいポートフォリオがリストに含まれている
        assertThat(afterResume.getPortfolios().contains(newPortfolio)).isTrue();
        // ポートフォリオリストのサイズが増加している
        assertThat(afterResume.getPortfolios().size()).isEqualTo(beforeResume.getPortfolios().size() + 1);
    }

    @Test
    @DisplayName("ポートフォリオを更新する")
    void test21() {
        Resume beforeResume = createSampleResume();
        Portfolio updatedPortfolio = Portfolio.reconstruct(
                beforeResume.getPortfolios().get(0).getId(),
                "更新されたポートフォリオ",
                "更新されたポートフォリオの概要",
                "更新された技術スタック",
                Link.create(errorCollector, "https://updated-portfolio.com"));

        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume afterResume = beforeResume.updatePortfolio(domainerrorCollector, updatedPortfolio);

        Portfolio actualPortfolio = afterResume.getPortfolios().stream()
                .filter(portfolio -> portfolio.getId().equals(updatedPortfolio.getId()))
                .findFirst()
                .orElseThrow();

        // 更新したポートフォリオがリストに含まれている
        assertThat(afterResume.getPortfolios().contains(updatedPortfolio)).isTrue();
        // ポートフォリオリストのサイズが変わらない
        assertThat(afterResume.getPortfolios().size()).isEqualTo(beforeResume.getPortfolios().size());
        // 更新したポートフォリオの値が正しい（順序に依存しない）
        assertAll(
                () -> assertThat(actualPortfolio.getName()).isEqualTo(updatedPortfolio.getName()),
                () -> assertThat(actualPortfolio.getOverview()).isEqualTo(updatedPortfolio.getOverview()),
                () -> assertThat(actualPortfolio.getTechStack()).isEqualTo(updatedPortfolio.getTechStack()),
                () -> assertThat(actualPortfolio.getLink()).isEqualTo(updatedPortfolio.getLink()),
                () -> assertThat(actualPortfolio.getId()).isEqualTo(updatedPortfolio.getId()));
    }

    @Test
    @DisplayName("ポートフォリオを削除する")
    void test22() {
        Resume beforeResume = createSampleResume();
        Portfolio newPortfolio = Portfolio.create(
                errorCollector,
                "削除対象のポートフォリオ",
                "削除対象の概要",
                "削除対象の技術スタック",
                Link.create(errorCollector, "https://delete-portfolio.com"));

        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume afterResume = beforeResume.addPortfolio(domainerrorCollector, newPortfolio);

        // 削除1回目(2件 → 1件)
        Resume deletedResume = afterResume.removePortfolio(newPortfolio.getId());
        // 削除したポートフォリオがリストに含まれていない
        assertThat(deletedResume.getPortfolios().contains(newPortfolio)).isFalse();
        // ポートフォリオリストのサイズが減少している
        assertThat(deletedResume.getPortfolios().size()).isEqualTo(afterResume.getPortfolios().size() - 1);

        // 削除2回目(1件 → 0件) - 残件のIDで削除（順序に依存しない）
        UUID remainingPortfolioId = deletedResume.getPortfolios().stream()
                .findFirst()
                .orElseThrow()
                .getId();

        Resume deletedResume2 = deletedResume.removePortfolio(remainingPortfolioId);
        // ポートフォリオリストが空になっている
        assertThat(deletedResume2.getPortfolios().isEmpty()).isTrue();
    }

    @Test
    @DisplayName("SNSプラットフォームを追加する")
    void test23() {
        Resume beforeResume = createSampleResume();
        SnsPlatform newSnsPlatform = SnsPlatform.create(
                errorCollector,
                "Twitter",
                Link.create(errorCollector, "https://twitter.com/user"));

        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume afterResume = beforeResume.addSnsPlatform(domainerrorCollector, newSnsPlatform);

        // 新しいSNSプラットフォームがリストに含まれている
        assertThat(afterResume.getSnsPlatforms().contains(newSnsPlatform)).isTrue();
        // SNSプラットフォームリストのサイズが増加している
        assertThat(afterResume.getSnsPlatforms().size()).isEqualTo(beforeResume.getSnsPlatforms().size() + 1);
    }

    @Test
    @DisplayName("SNSプラットフォームを更新する")
    void test24() {
        Resume beforeResume = createSampleResume();
        SnsPlatform updatedSnsPlatform = SnsPlatform.reconstruct(
                beforeResume.getSnsPlatforms().get(0).getId(),
                "LinkedIn",
                Link.create(errorCollector, "https://linkedin.com/in/user"));

        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume afterResume = beforeResume.updateSnsPlatform(domainerrorCollector, updatedSnsPlatform);

        SnsPlatform actualSnsPlatform = afterResume.getSnsPlatforms().stream()
                .filter(snsPlatform -> snsPlatform.getId().equals(updatedSnsPlatform.getId()))
                .findFirst()
                .orElseThrow();

        // 更新したSNSプラットフォームがリストに含まれている
        assertThat(afterResume.getSnsPlatforms().contains(updatedSnsPlatform)).isTrue();
        // SNSプラットフォームリストのサイズが変わらない
        assertThat(afterResume.getSnsPlatforms().size()).isEqualTo(beforeResume.getSnsPlatforms().size());
        // 更新したSNSプラットフォームの値が正しい（順序に依存しない）
        assertAll(
                () -> assertThat(actualSnsPlatform.getName()).isEqualTo(updatedSnsPlatform.getName()),
                () -> assertThat(actualSnsPlatform.getLink()).isEqualTo(updatedSnsPlatform.getLink()),
                () -> assertThat(actualSnsPlatform.getId()).isEqualTo(updatedSnsPlatform.getId()));
    }

    @Test
    @DisplayName("SNSプラットフォームを削除する")
    void test25() {
        Resume beforeResume = createSampleResume();
        SnsPlatform newSnsPlatform = SnsPlatform.create(
                errorCollector,
                "Facebook",
                Link.create(errorCollector, "https://facebook.com/user"));

        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume afterResume = beforeResume.addSnsPlatform(domainerrorCollector, newSnsPlatform);

        // 削除1回目(2件 → 1件)
        Resume deletedResume = afterResume.removeSnsPlatform(newSnsPlatform.getId());
        // 削除したSNSプラットフォームがリストに含まれていない
        assertThat(deletedResume.getSnsPlatforms().contains(newSnsPlatform)).isFalse();
        // SNSプラットフォームリストのサイズが減少している
        assertThat(deletedResume.getSnsPlatforms().size()).isEqualTo(afterResume.getSnsPlatforms().size() - 1);

        // 削除2回目(1件 → 0件) - 残件のIDで削除（順序に依存しない）
        UUID remainingSnsPlatformId = deletedResume.getSnsPlatforms().stream()
                .findFirst()
                .orElseThrow()
                .getId();

        Resume deletedResume2 = deletedResume.removeSnsPlatform(remainingSnsPlatformId);
        // SNSプラットフォームリストが空になっている
        assertThat(deletedResume2.getSnsPlatforms().isEmpty()).isTrue();
    }

    @Test
    @DisplayName("自己PRを追加する")
    void test26() {
        Resume beforeResume = createSampleResume();
        SelfPromotion newSelfPromotion = SelfPromotion.create(
                errorCollector,
                "新しいタイトル",
                "新しい自己PRの内容");

        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume afterResume = beforeResume.addSelfPromotion(domainerrorCollector, newSelfPromotion);

        // 新しい自己PRがリストに含まれている
        assertThat(afterResume.getSelfPromotions().contains(newSelfPromotion)).isTrue();
        // 自己PRリストのサイズが増加してい。
        assertThat(afterResume.getSelfPromotions().size()).isEqualTo(beforeResume.getSelfPromotions().size() + 1);
    }

    @Test
    @DisplayName("自己PRを更新する")
    void test27() {
        Resume beforeResume = createSampleResume();
        SelfPromotion updatedSelfPromotion = SelfPromotion.reconstruct(
                beforeResume.getSelfPromotions().get(0).getId(),
                "更新されたタイトル",
                "更新された自己PRの内容");

        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume afterResume = beforeResume.updateSelfPromotion(domainerrorCollector, updatedSelfPromotion);

        SelfPromotion actualSelfPromotion = afterResume.getSelfPromotions().stream()
                .filter(selfPromotion -> selfPromotion.getId().equals(updatedSelfPromotion.getId()))
                .findFirst()
                .orElseThrow();

        // 更新した自己PRがリストに含まれている
        assertThat(afterResume.getSelfPromotions().contains(updatedSelfPromotion)).isTrue();
        // 自己PRリストのサイズが変わらない
        assertThat(afterResume.getSelfPromotions().size()).isEqualTo(beforeResume.getSelfPromotions().size());
        // 更新した自己PRの値が正しい（順序に依存しない）
        assertAll(
                () -> assertThat(actualSelfPromotion.getTitle()).isEqualTo(updatedSelfPromotion.getTitle()),
                () -> assertThat(actualSelfPromotion.getContent()).isEqualTo(updatedSelfPromotion.getContent()),
                () -> assertThat(actualSelfPromotion.getId()).isEqualTo(updatedSelfPromotion.getId()));
    }

    @Test
    @DisplayName("自己PRを削除する")
    void test28() {
        Resume beforeResume = createSampleResume();
        SelfPromotion newSelfPromotion = SelfPromotion.create(
                errorCollector,
                "削除対象のタイトル",
                "削除対象の自己PRの内容");

        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume afterResume = beforeResume.addSelfPromotion(domainerrorCollector, newSelfPromotion);

        // 削除1回目(2件 → 1件)
        Resume deletedResume = afterResume.removeSelfPromotion(newSelfPromotion.getId());
        // 削除した自己PRがリストに含まれていない
        assertThat(deletedResume.getSelfPromotions().contains(newSelfPromotion)).isFalse();
        // 自己PRリストのサイズが減少している
        assertThat(deletedResume.getSelfPromotions().size()).isEqualTo(afterResume.getSelfPromotions().size() - 1);

        // 削除2回目(1件 → 0件) - 残件のIDで削除（順序に依存しない）
        UUID remainingSelfPromotionId = deletedResume.getSelfPromotions().stream()
                .findFirst()
                .orElseThrow()
                .getId();

        Resume deletedResume2 = deletedResume.removeSelfPromotion(remainingSelfPromotionId);
        // 自己PRリストが空になっている
        assertThat(deletedResume2.getSelfPromotions().isEmpty()).isTrue();
    }

    @Test
    @DisplayName("氏名を変更する")
    void test29() {
        Resume originalResume = createSampleResume();
        FullName newFullName = FullName.create(errorCollector, "変更", "しました");
        ErrorCollector domainerrorCollector = new ErrorCollector();

        Resume updatedResume = originalResume.ChangeFullName(domainerrorCollector, newFullName);

        assertThat(updatedResume.getFullName()).isEqualTo(newFullName);
    }

    @Test
    @DisplayName("エラー収集オブジェクト内にエラーがある状態で、職歴を追加するとDomainExceptionをスローする")
    void test30() {
        Resume resume = createSampleResume();

        Career newCareer = Career.create(errorCollector, CompanyName.create(errorCollector, "株式会社DEF"),
                Period.create(errorCollector, YearMonth.of(2024, 1), null, true));

        ErrorCollector invaliderrorCollector = new ErrorCollector();
        invaliderrorCollector.addError("dummy", "dummy error");

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> resume.addCareer(invaliderrorCollector, newCareer))
                .isInstanceOf(DomainException.class);
    }

    @Test
    @DisplayName("エラー収集オブジェクト内にエラーがある状態で、職歴を更新するとDomainExceptionをスローする")
    void test31() {
        Resume beforeResume = createSampleResume();

        Career updatedCareer = Career.reconstruct(beforeResume.getCareers().get(0).getId(),
                CompanyName.create(errorCollector, "株式会社DEF"),
                Period.create(errorCollector, YearMonth.of(2024, 1), null, true));

        ErrorCollector invaliderrorCollector = new ErrorCollector();
        invaliderrorCollector.addError("dummy", "dummy error");

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> beforeResume.updateCareer(invaliderrorCollector, updatedCareer))
                .isInstanceOf(DomainException.class);
    }

    @Test
    @DisplayName("エラー収集オブジェクト内にエラーがある状態で、プロジェクトを更新するとDomainExceptionをスローする")
    void test33() {
        Resume beforeResume = createSampleResume();
        Project originalProject = beforeResume.getProjects().get(0);

        Project updatedProject = Project.reconstruct(
                originalProject.getId(),
                originalProject.getCompanyName(),
                originalProject.getPeriod(),
                "更新されたプロジェクト名",
                "更新されたプロジェクト概要",
                "1人",
                "メンバー",
                "更新された成果内容",
                originalProject.getProcess(),
                originalProject.getTechStack());

        ErrorCollector invaliderrorCollector = new ErrorCollector();
        invaliderrorCollector.addError("dummy", "dummy error");

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> beforeResume.updateProject(invaliderrorCollector, updatedProject))
                .isInstanceOf(DomainException.class);
    }

    @Test
    @DisplayName("終了年月と開始年月が同一月でも職歴を追加できる（既存が終了・追加が継続中）")
    void test34() {
        UUID userId = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");

        Career existingCareer = Career.create(
                errorCollector,
                CompanyName.create(errorCollector, "会社A"),
                Period.create(errorCollector, YearMonth.of(2025, 11), YearMonth.of(2025, 12), false));

        Resume resume = Resume.create(
                errorCollector,
                userId,
                ResumeName.create(errorCollector, "職務経歴書A"),
                LocalDate.now(),
                FullName.create(errorCollector, "山田", "太郎"),
                List.of(existingCareer),
                List.of(),
                List.of(),
                List.of(),
                List.of(),
                List.of());

        Career newCareer = Career.create(
                errorCollector,
                CompanyName.create(errorCollector, "会社B"),
                Period.create(errorCollector, YearMonth.of(2025, 12), null, true));

        ErrorCollector domainerrorCollector = new ErrorCollector();

        assertThatCode(() -> resume.addCareer(domainerrorCollector, newCareer))
                .doesNotThrowAnyException();
    }

    @Test
    @DisplayName("終了年月と開始年月が同一月でも職歴を追加できる（両方が終了）")
    void test35() {
        UUID userId = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");

        Career existingCareer = Career.create(
                errorCollector,
                CompanyName.create(errorCollector, "会社A"),
                Period.create(errorCollector, YearMonth.of(2025, 11), YearMonth.of(2025, 12), false));

        Resume resume = Resume.create(
                errorCollector,
                userId,
                ResumeName.create(errorCollector, "職務経歴書A"),
                LocalDate.now(),
                FullName.create(errorCollector, "山田", "太郎"),
                List.of(existingCareer),
                List.of(),
                List.of(),
                List.of(),
                List.of(),
                List.of());

        Career newCareer = Career.create(
                errorCollector,
                CompanyName.create(errorCollector, "会社B"),
                Period.create(errorCollector, YearMonth.of(2025, 12), YearMonth.of(2025, 12), false));

        ErrorCollector domainerrorCollector = new ErrorCollector();

        assertThatCode(() -> resume.addCareer(domainerrorCollector, newCareer))
                .doesNotThrowAnyException();
    }

    @Test
    @DisplayName("終了年月と開始年月が同一月でも職歴を追加できる（追加が先・既存が後の境界一致）")
    void test36() {
        Resume resume = createSampleResume();

        Career boundaryCareer = Career.create(
                errorCollector,
                CompanyName.create(errorCollector, "株式会社XYZ"),
                Period.create(errorCollector, YearMonth.of(2019, 12), YearMonth.of(2020, 1), false));

        ErrorCollector domainerrorCollector = new ErrorCollector();

        assertThatCode(() -> resume.addCareer(domainerrorCollector, boundaryCareer))
                .doesNotThrowAnyException();
    }

    /**
     * 職務経歴書のサンプルエンティティを作成する補助メソッド
     */
    private Resume createSampleResume() {
        UUID userId = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        return Resume.create(
                errorCollector,
                userId,
                ResumeName.create(errorCollector, "職務経歴書A"),
                LocalDate.now(),
                FullName.create(errorCollector, "山田", "太郎"),
                List.of(createSampleCareer()),
                List.of(createSampleProject()),
                List.of(createSampleCertification()),
                List.of(createSamplePortfolio()),
                List.of(createSampleSnsPlatform()),
                List.of(createSampleSelfPromotion()));
    }

    /**
     * 職歴のサンプルエンティティを作成する補助メソッド
     */
    private Career createSampleCareer() {
        Period period = Period.create(errorCollector, YearMonth.of(2020, 1), YearMonth.of(2023, 12), false);
        CompanyName companyName = CompanyName.create(errorCollector, "株式会社ABC");
        return Career.create(errorCollector, companyName, period);
    }

    /**
     * プロジェクトのサンプルエンティティを作成する補助メソッド
     */
    private Project createSampleProject() {
        Period period = Period.create(errorCollector, YearMonth.of(2021, 1), YearMonth.of(2023, 12), false);
        CompanyName companyName = CompanyName.create(errorCollector, "株式会社ABC");

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
                errorCollector, companyName, period, "プロジェクト名", "プロジェクト概要", "5人", "リーダー", "成果内容", process, techStack);
    }

    /**
     * 資格のサンプルエンティティを作成する補助メソッド
     */
    private Certification createSampleCertification() {
        return Certification.create(errorCollector, "基本情報技術者", YearMonth.of(2025, 1));
    }

    /**
     * ポートフォリオのサンプルエンティティを作成する補助メソッド
     */
    private Portfolio createSamplePortfolio() {
        return Portfolio.create(errorCollector, "ポートフォリオ名", "概要", "技術スタック",
                Link.create(errorCollector, "https://portfolio.com"));
    }

    /**
     * SNSプラットフォームのサンプルエンティティを作成する補助メソッド
     */
    private SnsPlatform createSampleSnsPlatform() {
        return SnsPlatform.create(errorCollector, "GitHub", Link.create(errorCollector, "https://github.com/user"));
    }

    /**
     * 自己PRのサンプルエンティティを作成する補助メソッド
     */
    private SelfPromotion createSampleSelfPromotion() {
        return SelfPromotion.create(errorCollector, "自己PRタイトル", "自己PR内容");
    }
}
