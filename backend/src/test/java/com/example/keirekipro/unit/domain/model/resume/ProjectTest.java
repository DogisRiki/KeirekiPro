package com.example.keirekipro.unit.domain.model.resume;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.YearMonth;
import java.util.List;
import java.util.UUID;

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
        Project project = Project.create(0, "株式会社ABC", period, "プロジェクト名", "プロジェクト概要", "5人", "リーダー", "成果内容", process,
                techStack);

        assertThat(project).isNotNull();
        assertThat(project.getId()).isNotNull();
        assertThat(project.getOrderNo()).isEqualTo(0);
        assertThat(project.getCompanyName()).isEqualTo("株式会社ABC");
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
        UUID id = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        Project project = Project.reconstruct(id, 0, "株式会社ABC", period, "プロジェクト名", "プロジェクト概要", "5人", "リーダー", "成果内容",
                process,
                techStack);

        assertThat(project).isNotNull();
        assertThat(project.getId()).isEqualTo(id);
        assertThat(project.getOrderNo()).isEqualTo(0);
        assertThat(project.getCompanyName()).isEqualTo("株式会社ABC");
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
        Project updatedProject = project.changeCompanyName("新しい会社名");

        assertThat(updatedProject.getCompanyName()).isEqualTo("新しい会社名");
    }

    @Test
    @DisplayName("期間を変更する")
    void test4() {
        Project project = createSampleProject();
        Period newPeriod = Period.create(notification, YearMonth.of(2025, 1), YearMonth.of(2025, 12), false);
        Project updatedProject = project.changePeriod(newPeriod);

        assertThat(updatedProject.getPeriod()).isEqualTo(newPeriod);
    }

    @Test
    @DisplayName("プロジェクト概要を変更する")
    void test5() {
        Project project = createSampleProject();
        Project updatedProject = project.changeOverview("新しいプロジェクト概要");

        assertThat(updatedProject.getOverview()).isEqualTo("新しいプロジェクト概要");
    }

    @Test
    @DisplayName("チーム構成を変更する")
    void test6() {
        Project project = createSampleProject();
        Project updatedProject = project.changeTeamComp("10人");

        assertThat(updatedProject.getTeamComp()).isEqualTo("10人");
    }

    @Test
    @DisplayName("役割を変更する")
    void test7() {
        Project project = createSampleProject();
        Project updatedProject = project.changeRole("メンバー");

        assertThat(updatedProject.getRole()).isEqualTo("メンバー");
    }

    @Test
    @DisplayName("成果を変更する")
    void test8() {
        Project project = createSampleProject();
        Project updatedProject = project.changeAchievement("新しい成果");

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
        Project updatedProject = project.changeName("新しいプロジェクト名");

        assertThat(updatedProject.getName()).isEqualTo("新しいプロジェクト名");
    }

    @Test
    @DisplayName("すべてのフィールドを変更する")
    void test12() {
        Project initialProject = createSampleProject();

        Period newPeriod = Period.create(notification, YearMonth.of(2026, 1), YearMonth.of(2027, 12), false);
        TechStack newTechStack = TechStack.create(
                List.of("Kotlin", "Go"),
                TechStack.Dependencies.create(
                        List.of("Spring Boot", "Echo"),
                        List.of("Guava", "Gson"),
                        List.of("JUnit5", "TestNG"),
                        List.of("Hibernate"),
                        List.of("Gradle", "npm")),
                TechStack.Infrastructure.create(
                        List.of("Azure"),
                        List.of("Podman"),
                        List.of("MySQL"),
                        List.of("Apache"),
                        List.of("GitLab CI"),
                        List.of("Pulumi"),
                        List.of("Zabbix"),
                        List.of("Splunk")),
                TechStack.Tools.create(
                        List.of("Mercurial"),
                        List.of("Trello"),
                        List.of("Discord"),
                        List.of("Notion"),
                        List.of("Insomnia"),
                        List.of("Sketch")));
        Project.Process newProcess = Project.Process.create(
                true, false, true, false, true, false, true);

        Project updatedProject = initialProject
                .changeCompanyName("新しい会社名")
                .changePeriod(newPeriod)
                .changeName("新しいプロジェクト名")
                .changeOverview("新しいプロジェクト概要")
                .changeTeamComp("15人")
                .changeRole("プロジェクトマネージャー")
                .changeAchievement("大きな成功を達成")
                .changeProcess(newProcess)
                .changeTechStack(newTechStack);

        assertThat(updatedProject.getCompanyName()).isEqualTo("新しい会社名");
        assertThat(updatedProject.getPeriod()).isEqualTo(newPeriod);
        assertThat(updatedProject.getName()).isEqualTo("新しいプロジェクト名");
        assertThat(updatedProject.getOverview()).isEqualTo("新しいプロジェクト概要");
        assertThat(updatedProject.getTeamComp()).isEqualTo("15人");
        assertThat(updatedProject.getRole()).isEqualTo("プロジェクトマネージャー");
        assertThat(updatedProject.getAchievement()).isEqualTo("大きな成功を達成");
        assertThat(updatedProject.getProcess()).isEqualTo(newProcess);
        assertThat(updatedProject.getTechStack()).isEqualTo(newTechStack);
    }

    private Project createSampleProject() {
        Period period = Period.create(notification, YearMonth.of(2023, 1), YearMonth.of(2023, 12), false);
        TechStack techStack = createSampleTechStack();
        Project.Process process = createSampleProcess();
        return Project.create(0, "株式会社ABC", period, "プロジェクト名", "プロジェクト概要", "5人", "リーダー", "成果内容", process, techStack);
    }

    private TechStack createSampleTechStack() {
        TechStack.Dependencies dependencies = TechStack.Dependencies.create(
                List.of("Spring", "Django"),
                List.of("Lombok", "Jackson"),
                List.of("JUnit", "Mockito"),
                List.of("MyBatis"),
                List.of("Maven"));

        TechStack.Infrastructure infrastructure = TechStack.Infrastructure.create(
                List.of("AWS"),
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
                List.of("Figma"));

        return TechStack.create(List.of("Java", "Python"), dependencies, infrastructure, tools);
    }

    private Project.Process createSampleProcess() {
        return Project.Process.create(true, true, true, true, true, true, true);
    }
}
