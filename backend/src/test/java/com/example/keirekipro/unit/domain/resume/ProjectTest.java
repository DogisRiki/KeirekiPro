package com.example.keirekipro.unit.domain.resume;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.time.YearMonth;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Project;
import com.example.keirekipro.domain.model.resume.TechStack;
import com.example.keirekipro.domain.shared.Notification;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

class ProjectTest {

    @Mock
    private Notification notification;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
    }

    @Test
    @DisplayName("新規構築用コンストラクタでインスタンス化する")
    void test1() {
        Period period = Period.create(notification, YearMonth.of(2023, 1), YearMonth.of(2023, 12), false);
        TechStack techStack = createSampleTechStack();
        Project.Process process = createSampleProcess();
        Project project = Project.create(0, "株式会社ABC", period, "プロジェクト名", "プロジェクト概要", "5人", "リーダー", "成果内容", process,
                techStack);
        // インスタンスがnullでない。
        assertNotNull(project);
        // idが生成されている。
        assertNotNull(project.getId());
        // 並び順が正しい値である。
        assertEquals(0, project.getOrderNo());
        // 各フィールドの値が正しい。
        assertEquals("株式会社ABC", project.getCompanyName());
        assertEquals(period, project.getPeriod());
        assertEquals("プロジェクト名", project.getName());
        assertEquals("プロジェクト概要", project.getOverview());
        assertEquals("5人", project.getTeamComp());
        assertEquals("リーダー", project.getRole());
        assertEquals("成果内容", project.getAchievement());
        assertEquals(process, project.getProcess());
        assertEquals(techStack, project.getTechStack());
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
        // インスタンスがnullでない。
        assertNotNull(project);
        // idが正しい値である。
        assertEquals(id, project.getId());
        // 並び順が正しい値である。
        assertEquals(0, project.getOrderNo());
        // 各フィールドの値が正しい。
        assertEquals("株式会社ABC", project.getCompanyName());
        assertEquals(period, project.getPeriod());
        assertEquals("プロジェクト名", project.getName());
        assertEquals("プロジェクト概要", project.getOverview());
        assertEquals("5人", project.getTeamComp());
        assertEquals("リーダー", project.getRole());
        assertEquals("成果内容", project.getAchievement());
        assertEquals(process, project.getProcess());
        assertEquals(techStack, project.getTechStack());
    }

    @Test
    @DisplayName("会社名を変更する")
    void test3() {
        Project project = createSampleProject();
        Project updatedProject = project.changeCompanyName("新しい会社名");
        // 変更した会社名が正しい値である。
        assertEquals("新しい会社名", updatedProject.getCompanyName());
    }

    @Test
    @DisplayName("期間を変更する")
    void test4() {
        Project project = createSampleProject();
        Period newPeriod = Period.create(notification, YearMonth.of(2025, 1), YearMonth.of(2025, 12), false);
        Project updatedProject = project.changePeriod(newPeriod);
        // 変更した期間が正しい値である。
        assertEquals(newPeriod, updatedProject.getPeriod());
    }

    @Test
    @DisplayName("プロジェクト概要を変更する")
    void test5() {
        Project project = createSampleProject();
        Project updatedProject = project.changeOverview("新しいプロジェクト概要");
        // 変更したプロジェクト概要が正しい値である。
        assertEquals("新しいプロジェクト概要", updatedProject.getOverview());
    }

    @Test
    @DisplayName("チーム構成を変更する")
    void test6() {
        Project project = createSampleProject();
        Project updatedProject = project.changeTeamComp("10人");
        // 変更したチーム構成が正しい値である。
        assertEquals("10人", updatedProject.getTeamComp());
    }

    @Test
    @DisplayName("役割を変更する")
    void test7() {
        Project project = createSampleProject();
        Project updatedProject = project.changeRole("メンバー");
        // 変更した役割が正しい値である。
        assertEquals("メンバー", updatedProject.getRole());
    }

    @Test
    @DisplayName("成果を変更する")
    void test8() {
        Project project = createSampleProject();
        Project updatedProject = project.changeAchievement("新しい成果");
        // 変更した成果が正しい値である。
        assertEquals("新しい成果", updatedProject.getAchievement());
    }

    @Test
    @DisplayName("作業工程を変更する")
    void test9() {
        Project project = createSampleProject();
        Project.Process newProcess = createSampleProcess();
        Project updatedProject = project.changeProcess(newProcess);
        // 変更した作業工程が正しい値である。
        assertEquals(newProcess, updatedProject.getProcess());
    }

    @Test
    @DisplayName("技術スタックを変更する")
    void test10() {
        Project project = createSampleProject();
        TechStack newTechStack = createSampleTechStack();
        Project updatedProject = project.changeTechStack(newTechStack);
        // 変更した技術スタックが正しい値である。
        assertEquals(newTechStack, updatedProject.getTechStack());
    }

    @Test
    @DisplayName("プロジェクト名を変更する")
    void test11() {
        Project project = createSampleProject();
        Project updatedProject = project.changeName("新しいプロジェクト名");
        // 変更したプロジェクト名が正しい値である。
        assertEquals("新しいプロジェクト名", updatedProject.getName());
    }

    @Test
    @DisplayName("すべてのフィールドを変更する")
    void test12() {
        // 初期データ作成
        Project initialProject = createSampleProject();

        // 新しい値の準備
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

        // アサーション
        assertEquals("新しい会社名", updatedProject.getCompanyName());
        assertEquals(newPeriod, updatedProject.getPeriod());
        assertEquals("新しいプロジェクト名", updatedProject.getName());
        assertEquals("新しいプロジェクト概要", updatedProject.getOverview());
        assertEquals("15人", updatedProject.getTeamComp());
        assertEquals("プロジェクトマネージャー", updatedProject.getRole());
        assertEquals("大きな成功を達成", updatedProject.getAchievement());
        assertEquals(newProcess, updatedProject.getProcess());
        assertEquals(newTechStack, updatedProject.getTechStack());
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
