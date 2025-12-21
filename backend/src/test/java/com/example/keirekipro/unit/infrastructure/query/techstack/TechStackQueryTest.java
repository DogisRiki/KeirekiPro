package com.example.keirekipro.unit.infrastructure.query.techstack;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.List;

import com.example.keirekipro.infrastructure.query.techstack.TechStackDto;
import com.example.keirekipro.infrastructure.query.techstack.TechStackMapper;
import com.example.keirekipro.infrastructure.query.techstack.TechStackQuery;
import com.example.keirekipro.usecase.query.techstack.dto.TechStackListItemDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class TechStackQueryTest {

    @Mock
    private TechStackMapper techStackMapper;

    @InjectMocks
    private TechStackQuery techStackQuery;

    @Test
    @DisplayName("技術スタックマスタが1件も存在しない場合、全てのリストが空で返る")
    void test1() {
        // モック準備
        when(techStackMapper.selectAll()).thenReturn(List.of());

        // 実行
        TechStackListItemDto actual = techStackQuery.selectTechStackListItem();

        // 検証
        assertThat(actual).isNotNull();

        // frontend
        assertThat(actual.getFrontend().getLanguages()).isEmpty();
        assertThat(actual.getFrontend().getFrameworks()).isEmpty();
        assertThat(actual.getFrontend().getLibraries()).isEmpty();
        assertThat(actual.getFrontend().getBuildTools()).isEmpty();
        assertThat(actual.getFrontend().getPackageManagers()).isEmpty();
        assertThat(actual.getFrontend().getLinters()).isEmpty();
        assertThat(actual.getFrontend().getFormatters()).isEmpty();
        assertThat(actual.getFrontend().getTestingTools()).isEmpty();

        // backend
        assertThat(actual.getBackend().getLanguages()).isEmpty();
        assertThat(actual.getBackend().getFrameworks()).isEmpty();
        assertThat(actual.getBackend().getLibraries()).isEmpty();
        assertThat(actual.getBackend().getBuildTools()).isEmpty();
        assertThat(actual.getBackend().getPackageManagers()).isEmpty();
        assertThat(actual.getBackend().getLinters()).isEmpty();
        assertThat(actual.getBackend().getFormatters()).isEmpty();
        assertThat(actual.getBackend().getTestingTools()).isEmpty();
        assertThat(actual.getBackend().getOrmTools()).isEmpty();
        assertThat(actual.getBackend().getAuth()).isEmpty();

        // infrastructure
        assertThat(actual.getInfrastructure().getClouds()).isEmpty();
        assertThat(actual.getInfrastructure().getOperatingSystems()).isEmpty();
        assertThat(actual.getInfrastructure().getContainers()).isEmpty();
        assertThat(actual.getInfrastructure().getDatabases()).isEmpty();
        assertThat(actual.getInfrastructure().getWebServers()).isEmpty();
        assertThat(actual.getInfrastructure().getCiCdTools()).isEmpty();
        assertThat(actual.getInfrastructure().getIacTools()).isEmpty();
        assertThat(actual.getInfrastructure().getMonitoringTools()).isEmpty();
        assertThat(actual.getInfrastructure().getLoggingTools()).isEmpty();

        // tools
        assertThat(actual.getTools().getSourceControls()).isEmpty();
        assertThat(actual.getTools().getProjectManagements()).isEmpty();
        assertThat(actual.getTools().getCommunicationTools()).isEmpty();
        assertThat(actual.getTools().getDocumentationTools()).isEmpty();
        assertThat(actual.getTools().getApiDevelopmentTools()).isEmpty();
        assertThat(actual.getTools().getDesignTools()).isEmpty();
        assertThat(actual.getTools().getEditors()).isEmpty();
        assertThat(actual.getTools().getDevelopmentEnvironments()).isEmpty();

        verify(techStackMapper).selectAll();
    }

    @Test
    @DisplayName("各mainCategory/subCategoryに対応する技術スタックが存在する場合、DTOに正しくマッピングされる")
    void test2() {
        // モック準備
        List<TechStackDto> rows = List.of(
                // frontend
                createTechStack("frontend", "languages", "JavaScript"),
                createTechStack("frontend", "framework", "React"),
                createTechStack("frontend", "libraries", "Zustand"),
                createTechStack("frontend", "buildTool", "Vite"),
                createTechStack("frontend", "packageManager", "npm"),
                createTechStack("frontend", "linters", "ESLint"),
                createTechStack("frontend", "formatters", "Prettier"),
                createTechStack("frontend", "testingTools", "Jest"),

                // backend
                createTechStack("backend", "languages", "Java"),
                createTechStack("backend", "framework", "Spring Boot"),
                createTechStack("backend", "libraries", "Lombok"),
                createTechStack("backend", "buildTool", "Gradle"),
                createTechStack("backend", "packageManager", "Maven"),
                createTechStack("backend", "linters", "Checkstyle"),
                createTechStack("backend", "formatters", "google-java-format"),
                createTechStack("backend", "testingTools", "JUnit"),
                createTechStack("backend", "ormTools", "Hibernate"),
                createTechStack("backend", "auth", "Spring Security"),

                // infrastructure
                createTechStack("infrastructure", "clouds", "AWS"),
                createTechStack("infrastructure", "operatingSystem", "Ubuntu"),
                createTechStack("infrastructure", "containers", "Docker"),
                createTechStack("infrastructure", "database", "PostgreSQL"),
                createTechStack("infrastructure", "webServer", "Nginx"),
                createTechStack("infrastructure", "ciCdTool", "GitHub Actions"),
                createTechStack("infrastructure", "iacTools", "Terraform"),
                createTechStack("infrastructure", "monitoringTools", "CloudWatch"),
                createTechStack("infrastructure", "loggingTools", "Fluentd"),

                // tools
                createTechStack("tools", "sourceControl", "Git"),
                createTechStack("tools", "projectManagement", "Redmine"),
                createTechStack("tools", "communicationTool", "Slack"),
                createTechStack("tools", "documentationTools", "Confluence"),
                createTechStack("tools", "apiDevelopmentTools", "Postman"),
                createTechStack("tools", "designTools", "Figma"),
                createTechStack("tools", "editor", "VS Code"),
                createTechStack("tools", "developmentEnvironment", "WSL2"));
        when(techStackMapper.selectAll()).thenReturn(rows);

        // 実行
        TechStackListItemDto actual = techStackQuery.selectTechStackListItem();

        // 検証
        assertThat(actual).isNotNull();

        // frontend
        assertThat(actual.getFrontend().getLanguages()).containsExactly("JavaScript");
        assertThat(actual.getFrontend().getFrameworks()).containsExactly("React");
        assertThat(actual.getFrontend().getLibraries()).containsExactly("Zustand");
        assertThat(actual.getFrontend().getBuildTools()).containsExactly("Vite");
        assertThat(actual.getFrontend().getPackageManagers()).containsExactly("npm");
        assertThat(actual.getFrontend().getLinters()).containsExactly("ESLint");
        assertThat(actual.getFrontend().getFormatters()).containsExactly("Prettier");
        assertThat(actual.getFrontend().getTestingTools()).containsExactly("Jest");

        // backend
        assertThat(actual.getBackend().getLanguages()).containsExactly("Java");
        assertThat(actual.getBackend().getFrameworks()).containsExactly("Spring Boot");
        assertThat(actual.getBackend().getLibraries()).containsExactly("Lombok");
        assertThat(actual.getBackend().getBuildTools()).containsExactly("Gradle");
        assertThat(actual.getBackend().getPackageManagers()).containsExactly("Maven");
        assertThat(actual.getBackend().getLinters()).containsExactly("Checkstyle");
        assertThat(actual.getBackend().getFormatters()).containsExactly("google-java-format");
        assertThat(actual.getBackend().getTestingTools()).containsExactly("JUnit");
        assertThat(actual.getBackend().getOrmTools()).containsExactly("Hibernate");
        assertThat(actual.getBackend().getAuth()).containsExactly("Spring Security");

        // infrastructure
        assertThat(actual.getInfrastructure().getClouds()).containsExactly("AWS");
        assertThat(actual.getInfrastructure().getOperatingSystems()).containsExactly("Ubuntu");
        assertThat(actual.getInfrastructure().getContainers()).containsExactly("Docker");
        assertThat(actual.getInfrastructure().getDatabases()).containsExactly("PostgreSQL");
        assertThat(actual.getInfrastructure().getWebServers()).containsExactly("Nginx");
        assertThat(actual.getInfrastructure().getCiCdTools()).containsExactly("GitHub Actions");
        assertThat(actual.getInfrastructure().getIacTools()).containsExactly("Terraform");
        assertThat(actual.getInfrastructure().getMonitoringTools()).containsExactly("CloudWatch");
        assertThat(actual.getInfrastructure().getLoggingTools()).containsExactly("Fluentd");

        // tools
        assertThat(actual.getTools().getSourceControls()).containsExactly("Git");
        assertThat(actual.getTools().getProjectManagements()).containsExactly("Redmine");
        assertThat(actual.getTools().getCommunicationTools()).containsExactly("Slack");
        assertThat(actual.getTools().getDocumentationTools()).containsExactly("Confluence");
        assertThat(actual.getTools().getApiDevelopmentTools()).containsExactly("Postman");
        assertThat(actual.getTools().getDesignTools()).containsExactly("Figma");
        assertThat(actual.getTools().getEditors()).containsExactly("VS Code");
        assertThat(actual.getTools().getDevelopmentEnvironments()).containsExactly("WSL2");

        verify(techStackMapper).selectAll();
    }

    @Test
    @DisplayName("想定外のmainCategoryやsubCategoryは無視される")
    void test3() {
        // モック準備（想定外のmain/subを含む）
        List<TechStackDto> rows = List.of(
                // 想定外のmainCategory
                createTechStack("unknown", "languages", "X-Lang"),
                // 想定外のsubCategory（frontendの未知サブカテゴリ）
                createTechStack("frontend", "unknownSub", "Unknown-Frontend"),
                // 想定外のsubCategory（backendの未知サブカテゴリ）
                createTechStack("backend", "unknownSub", "Unknown-Backend"),
                // 想定外のsubCategory（infrastructureの未知サブカテゴリ）
                createTechStack("infrastructure", "unknownSub", "Unknown-Infra"),
                // 想定外のsubCategory（toolsの未知サブカテゴリ）
                createTechStack("tools", "unknownSub", "Unknown-Tools"));
        when(techStackMapper.selectAll()).thenReturn(rows);

        // 実行
        TechStackListItemDto actual = techStackQuery.selectTechStackListItem();

        // 検証：全て無視され、全リストが空であること
        assertThat(actual.getFrontend().getLanguages()).isEmpty();
        assertThat(actual.getFrontend().getFrameworks()).isEmpty();
        assertThat(actual.getFrontend().getLibraries()).isEmpty();
        assertThat(actual.getFrontend().getBuildTools()).isEmpty();
        assertThat(actual.getFrontend().getPackageManagers()).isEmpty();
        assertThat(actual.getFrontend().getLinters()).isEmpty();
        assertThat(actual.getFrontend().getFormatters()).isEmpty();
        assertThat(actual.getFrontend().getTestingTools()).isEmpty();

        assertThat(actual.getBackend().getLanguages()).isEmpty();
        assertThat(actual.getBackend().getFrameworks()).isEmpty();
        assertThat(actual.getBackend().getLibraries()).isEmpty();
        assertThat(actual.getBackend().getBuildTools()).isEmpty();
        assertThat(actual.getBackend().getPackageManagers()).isEmpty();
        assertThat(actual.getBackend().getLinters()).isEmpty();
        assertThat(actual.getBackend().getFormatters()).isEmpty();
        assertThat(actual.getBackend().getTestingTools()).isEmpty();
        assertThat(actual.getBackend().getOrmTools()).isEmpty();
        assertThat(actual.getBackend().getAuth()).isEmpty();

        assertThat(actual.getInfrastructure().getClouds()).isEmpty();
        assertThat(actual.getInfrastructure().getOperatingSystems()).isEmpty();
        assertThat(actual.getInfrastructure().getContainers()).isEmpty();
        assertThat(actual.getInfrastructure().getDatabases()).isEmpty();
        assertThat(actual.getInfrastructure().getWebServers()).isEmpty();
        assertThat(actual.getInfrastructure().getCiCdTools()).isEmpty();
        assertThat(actual.getInfrastructure().getIacTools()).isEmpty();
        assertThat(actual.getInfrastructure().getMonitoringTools()).isEmpty();
        assertThat(actual.getInfrastructure().getLoggingTools()).isEmpty();

        assertThat(actual.getTools().getSourceControls()).isEmpty();
        assertThat(actual.getTools().getProjectManagements()).isEmpty();
        assertThat(actual.getTools().getCommunicationTools()).isEmpty();
        assertThat(actual.getTools().getDocumentationTools()).isEmpty();
        assertThat(actual.getTools().getApiDevelopmentTools()).isEmpty();
        assertThat(actual.getTools().getDesignTools()).isEmpty();
        assertThat(actual.getTools().getEditors()).isEmpty();
        assertThat(actual.getTools().getDevelopmentEnvironments()).isEmpty();

        verify(techStackMapper).selectAll();
    }

    /**
     * TechStackDtoを生成するヘルパーメソッド
     */
    private TechStackDto createTechStack(String mainCategory, String subCategory, String name) {
        TechStackDto dto = new TechStackDto();
        dto.setMainCategory(mainCategory);
        dto.setSubCategory(subCategory);
        dto.setName(name);
        return dto;
    }
}
