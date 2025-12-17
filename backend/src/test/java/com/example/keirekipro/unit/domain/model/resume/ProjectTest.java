package com.example.keirekipro.unit.domain.model.resume;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.YearMonth;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.CompanyName;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Project;
import com.example.keirekipro.domain.model.resume.TechStack;
import com.example.keirekipro.shared.Notification;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ProjectTest {

    @Mock
    private Notification notification;

    @Test
    @DisplayName("新規構築用コンストラクタでインスタンス化する")
    void test1() {
        Period period = Period.create(notification, YearMonth.of(2023, 1), YearMonth.of(2023, 12), false);
        TechStack techStack = createSampleTechStack();
        Project.Process process = createSampleProcess();
        CompanyName companyName = CompanyName.create(notification, "株式会社ABC");
        Project project = Project.create(notification, companyName, period, "プロジェクト名", "プロジェクト概要", "5人", "リーダー",
                "成果内容", process, techStack);

        assertThat(project).isNotNull();
        assertThat(project.getId()).isNotNull();
        assertThat(project.getCompanyName().getValue()).isEqualTo("株式会社ABC");
        assertThat(project.getPeriod()).isEqualTo(period);
        assertThat(project.getName()).isEqualTo("プロジェクト名");
        assertThat(project.getOverview()).isEqualTo("プロジェクト概要");
        assertThat(project.getTeamComp()).isEqualTo("5人");
        assertThat(project.getRole()).isEqualTo("リーダー");
        assertThat(project.getAchievement()).isEqualTo("成果内容");
        assertThat(project.getProcess()).isEqualTo(process);
        assertThat(project.getTechStack()).isEqualTo(techStack);
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test2() {
        Period period = Period.create(notification, YearMonth.of(2023, 1), YearMonth.of(2023, 12), false);
        TechStack techStack = createSampleTechStack();
        Project.Process process = createSampleProcess();
        CompanyName companyName = CompanyName.create(notification, "株式会社ABC");
        UUID id = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        Project project = Project.reconstruct(id, companyName, period, "プロジェクト名", "プロジェクト概要", "5人", "リーダー",
                "成果内容",
                process,
                techStack);

        assertThat(project).isNotNull();
        assertThat(project.getId()).isEqualTo(id);
        assertThat(project.getCompanyName().getValue()).isEqualTo("株式会社ABC");
        assertThat(project.getPeriod()).isEqualTo(period);
        assertThat(project.getName()).isEqualTo("プロジェクト名");
        assertThat(project.getOverview()).isEqualTo("プロジェクト概要");
        assertThat(project.getTeamComp()).isEqualTo("5人");
        assertThat(project.getRole()).isEqualTo("リーダー");
        assertThat(project.getAchievement()).isEqualTo("成果内容");
        assertThat(project.getProcess()).isEqualTo(process);
        assertThat(project.getTechStack()).isEqualTo(techStack);
    }

    @Test
    @DisplayName("会社名を変更する")
    void test3() {
        Project project = createSampleProject();
        CompanyName newCompanyName = CompanyName.create(notification, "新しい会社名");
        Project updatedProject = project.changeCompanyName(notification, newCompanyName);

        assertThat(updatedProject.getCompanyName().getValue()).isEqualTo("新しい会社名");
    }

    @Test
    @DisplayName("期間を変更する")
    void test4() {
        Project project = createSampleProject();
        Period newPeriod = Period.create(notification, YearMonth.of(2025, 1), YearMonth.of(2025, 12), false);
        Project updatedProject = project.changePeriod(notification, newPeriod);

        assertThat(updatedProject.getPeriod()).isEqualTo(newPeriod);
    }

    @Test
    @DisplayName("プロジェクト概要を変更する")
    void test5() {
        Project project = createSampleProject();
        Project updatedProject = project.changeOverview(notification, "新しいプロジェクト概要");

        assertThat(updatedProject.getOverview()).isEqualTo("新しいプロジェクト概要");
    }

    @Test
    @DisplayName("チーム構成を変更する")
    void test6() {
        Project project = createSampleProject();
        Project updatedProject = project.changeTeamComp(notification, "10人");

        assertThat(updatedProject.getTeamComp()).isEqualTo("10人");
    }

    @Test
    @DisplayName("役割を変更する")
    void test7() {
        Project project = createSampleProject();
        Project updatedProject = project.changeRole(notification, "メンバー");

        assertThat(updatedProject.getRole()).isEqualTo("メンバー");
    }

    @Test
    @DisplayName("成果を変更する")
    void test8() {
        Project project = createSampleProject();
        Project updatedProject = project.changeAchievement(notification, "新しい成果");

        assertThat(updatedProject.getAchievement()).isEqualTo("新しい成果");
    }

    @Test
    @DisplayName("作業工程を変更する")
    void test9() {
        Project project = createSampleProject();
        Project.Process newProcess = createSampleProcess();
        Project updatedProject = project.changeProcess(newProcess);

        assertThat(updatedProject.getProcess()).isEqualTo(newProcess);
    }

    @Test
    @DisplayName("技術スタックを変更する")
    void test10() {
        Project project = createSampleProject();
        TechStack newTechStack = createSampleTechStack();
        Project updatedProject = project.changeTechStack(newTechStack);

        assertThat(updatedProject.getTechStack()).isEqualTo(newTechStack);
    }

    @Test
    @DisplayName("プロジェクト名を変更する")
    void test11() {
        Project project = createSampleProject();
        Project updatedProject = project.changeName(notification, "新しいプロジェクト名");

        assertThat(updatedProject.getName()).isEqualTo("新しいプロジェクト名");
    }

    @Test
    @DisplayName("すべてのフィールドを変更する")
    void test12() {
        Project initialProject = createSampleProject();

        Period newPeriod = Period.create(notification, YearMonth.of(2026, 1), YearMonth.of(2027, 12), false);

        TechStack.Frontend newFrontend = TechStack.Frontend.create(
                List.of("Kotlin/JS"),
                List.of("React"),
                List.of("MUI"),
                List.of("Vite"),
                List.of("npm"),
                List.of("ESLint"),
                List.of("Prettier"),
                List.of("Vitest"));

        TechStack.Backend newBackend = TechStack.Backend.create(
                List.of("Kotlin", "Go"),
                List.of("Spring Boot"),
                List.of("Guava", "Gson"),
                List.of("Gradle"),
                List.of("Gradle"),
                List.of("Detekt"),
                List.of("Google Java Format"),
                List.of("JUnit5", "TestNG"),
                List.of("Hibernate"),
                List.of("Keycloak"));

        TechStack.Infrastructure newInfrastructure = TechStack.Infrastructure.create(
                List.of("Azure"),
                List.of("Ubuntu 22.04"),
                List.of("Podman"),
                List.of("MySQL"),
                List.of("Apache"),
                List.of("GitLab CI"),
                List.of("Pulumi"),
                List.of("Zabbix"),
                List.of("Splunk"));

        TechStack.Tools newTools = TechStack.Tools.create(
                List.of("Mercurial"),
                List.of("Trello"),
                List.of("Discord"),
                List.of("Notion"),
                List.of("Insomnia"),
                List.of("Sketch"),
                List.of("IntelliJ IDEA"),
                List.of("Docker Desktop"));

        TechStack newTechStack = TechStack.create(newFrontend, newBackend, newInfrastructure, newTools);

        Project.Process newProcess = Project.Process.create(
                true, false, true, false, true, false, true);

        Project updatedProject = initialProject
                .changeCompanyName(notification, CompanyName.create(notification, "新しい会社名"))
                .changePeriod(notification, newPeriod)
                .changeName(notification, "新しいプロジェクト名")
                .changeOverview(notification, "新しいプロジェクト概要")
                .changeTeamComp(notification, "15人")
                .changeRole(notification, "プロジェクトマネージャー")
                .changeAchievement(notification, "大きな成功を達成")
                .changeProcess(newProcess)
                .changeTechStack(newTechStack);

        assertThat(updatedProject.getCompanyName().getValue()).isEqualTo("新しい会社名");
        assertThat(updatedProject.getPeriod()).isEqualTo(newPeriod);
        assertThat(updatedProject.getName()).isEqualTo("新しいプロジェクト名");
        assertThat(updatedProject.getOverview()).isEqualTo("新しいプロジェクト概要");
        assertThat(updatedProject.getTeamComp()).isEqualTo("15人");
        assertThat(updatedProject.getRole()).isEqualTo("プロジェクトマネージャー");
        assertThat(updatedProject.getAchievement()).isEqualTo("大きな成功を達成");
        assertThat(updatedProject.getProcess()).isEqualTo(newProcess);
        assertThat(updatedProject.getTechStack()).isEqualTo(newTechStack);
    }

    @Test
    @DisplayName("必須項目が未入力の場合、エラーが通知される")
    void test13() {
        Notification notification = new Notification();
        CompanyName companyName = CompanyName.create(notification, "株式会社ABC");
        Period period = Period.create(notification, YearMonth.of(2023, 1), YearMonth.of(2023, 12), false);
        TechStack techStack = createSampleTechStack();
        Project.Process process = createSampleProcess();

        Project.create(notification, companyName, period, "", "", "", "", "", process, techStack);

        assertThat(notification.getErrors().get("name")).containsExactly("プロジェクト名は入力必須です。");
        assertThat(notification.getErrors().get("overview")).containsExactly("プロジェクト概要は入力必須です。");
        assertThat(notification.getErrors().get("teamComp")).containsExactly("チーム構成は入力必須です。");
        assertThat(notification.getErrors().get("role")).containsExactly("役割は入力必須です。");
        assertThat(notification.getErrors().get("achievement")).containsExactly("成果は入力必須です。");
    }

    @Test
    @DisplayName("各項目が最大文字数を超える場合、エラーが通知される")
    void test14() {
        Notification notification = new Notification();
        CompanyName companyName = CompanyName.create(notification, "株式会社ABC");
        Period period = Period.create(notification, YearMonth.of(2023, 1), YearMonth.of(2023, 12), false);
        TechStack techStack = createSampleTechStack();
        Project.Process process = createSampleProcess();

        String longName = "a".repeat(51);
        String longOverview = "a".repeat(1001);
        String longTeamComp = "a".repeat(101);
        String longRole = "a".repeat(1001);
        String longAchievement = "a".repeat(1001);

        Project.create(notification, companyName, period, longName, longOverview, longTeamComp, longRole,
                longAchievement, process, techStack);

        assertThat(notification.getErrors().get("name")).containsExactly("プロジェクト名は50文字以内で入力してください。");
        assertThat(notification.getErrors().get("overview")).containsExactly("プロジェクト概要は1000文字以内で入力してください。");
        assertThat(notification.getErrors().get("teamComp")).containsExactly("チーム構成は100文字以内で入力してください。");
        assertThat(notification.getErrors().get("role")).containsExactly("役割は1000文字以内で入力してください。");
        assertThat(notification.getErrors().get("achievement")).containsExactly("成果は1000文字以内で入力してください。");
    }

    @Test
    @DisplayName("会社名がnullの場合、エラーが通知される")
    void test15() {
        Notification notification = new Notification();
        Period period = Period.create(notification, YearMonth.of(2023, 1), YearMonth.of(2023, 12), false);
        TechStack techStack = createSampleTechStack();
        Project.Process process = createSampleProcess();

        Project.create(notification, null, period, "プロジェクト名", "プロジェクト概要", "5人", "リーダー", "成果内容", process, techStack);

        assertThat(notification.getErrors().get("companyName")).containsExactly("会社名は入力必須です。");
    }

    private Project createSampleProject() {
        Period period = Period.create(notification, YearMonth.of(2023, 1), YearMonth.of(2023, 12), false);
        TechStack techStack = createSampleTechStack();
        Project.Process process = createSampleProcess();
        CompanyName companyName = CompanyName.create(notification, "株式会社ABC");
        return Project.create(notification, companyName, period, "プロジェクト名", "プロジェクト概要", "5人", "リーダー", "成果内容",
                process, techStack);
    }

    private TechStack createSampleTechStack() {
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

        return TechStack.create(frontend, backend, infrastructure, tools);
    }

    private Project.Process createSampleProcess() {
        return Project.Process.create(true, true, true, true, true, true, true);
    }
}
