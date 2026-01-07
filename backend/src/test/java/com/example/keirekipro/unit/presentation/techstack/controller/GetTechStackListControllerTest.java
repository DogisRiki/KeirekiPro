package com.example.keirekipro.unit.presentation.techstack.controller;

import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;

import com.example.keirekipro.presentation.techstack.controller.GetTechStackListController;
import com.example.keirekipro.usecase.query.techstack.TechStackListQuery;
import com.example.keirekipro.usecase.query.techstack.dto.TechStackListQueryDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.TestConstructor.AutowireMode;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(GetTechStackListController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = AutowireMode.ALL)
@RequiredArgsConstructor
class GetTechStackListControllerTest {

    @MockitoBean
    private TechStackListQuery techStackListQuery;

    private final MockMvc mockMvc;

    private static final String ENDPOINT = "/api/tech-stacks";

    @Test
    @DisplayName("正常なリクエストの場合、200と技術スタック一覧がレスポンスとして返る")
    void test1() throws Exception {
        // Queryから返却されるDTOを準備
        TechStackListQueryDto.FrontendDto frontend = TechStackListQueryDto.FrontendDto.builder()
                .languages(List.of("JavaScript"))
                .frameworks(List.of("React"))
                .libraries(List.of("Zustand"))
                .buildTools(List.of("Vite"))
                .packageManagers(List.of("npm"))
                .linters(List.of("ESLint"))
                .formatters(List.of("Prettier"))
                .testingTools(List.of("Jest"))
                .build();

        TechStackListQueryDto.BackendDto backend = TechStackListQueryDto.BackendDto.builder()
                .languages(List.of("Java"))
                .frameworks(List.of("Spring Boot"))
                .libraries(List.of("Lombok"))
                .buildTools(List.of("Gradle"))
                .packageManagers(List.of("Maven"))
                .linters(List.of("Checkstyle"))
                .formatters(List.of("google-java-format"))
                .testingTools(List.of("JUnit"))
                .ormTools(List.of("Hibernate"))
                .auth(List.of("Spring Security"))
                .build();

        TechStackListQueryDto.InfrastructureDto infrastructure = TechStackListQueryDto.InfrastructureDto.builder()
                .clouds(List.of("AWS"))
                .operatingSystems(List.of("Ubuntu"))
                .containers(List.of("Docker"))
                .databases(List.of("PostgreSQL"))
                .webServers(List.of("Nginx"))
                .ciCdTools(List.of("GitHub Actions"))
                .iacTools(List.of("Terraform"))
                .monitoringTools(List.of("CloudWatch"))
                .loggingTools(List.of("Fluentd"))
                .build();

        TechStackListQueryDto.ToolsDto tools = TechStackListQueryDto.ToolsDto.builder()
                .sourceControls(List.of("Git"))
                .projectManagements(List.of("Redmine"))
                .communicationTools(List.of("Slack"))
                .documentationTools(List.of("Confluence"))
                .apiDevelopmentTools(List.of("Postman"))
                .designTools(List.of("Figma"))
                .editors(List.of("VS Code"))
                .developmentEnvironments(List.of("WSL2"))
                .build();

        TechStackListQueryDto dto = TechStackListQueryDto.builder()
                .frontend(frontend)
                .backend(backend)
                .infrastructure(infrastructure)
                .tools(tools)
                .build();

        // モック設定
        when(techStackListQuery.findAll()).thenReturn(dto);

        // 実行&検証
        mockMvc.perform(get(ENDPOINT))
                .andExpect(status().isOk())
                // frontend
                .andExpect(jsonPath("$.frontend.languages[0]").value("JavaScript"))
                .andExpect(jsonPath("$.frontend.frameworks[0]").value("React"))
                .andExpect(jsonPath("$.frontend.libraries[0]").value("Zustand"))
                .andExpect(jsonPath("$.frontend.buildTools[0]").value("Vite"))
                .andExpect(jsonPath("$.frontend.packageManagers[0]").value("npm"))
                .andExpect(jsonPath("$.frontend.linters[0]").value("ESLint"))
                .andExpect(jsonPath("$.frontend.formatters[0]").value("Prettier"))
                .andExpect(jsonPath("$.frontend.testingTools[0]").value("Jest"))

                // backend
                .andExpect(jsonPath("$.backend.languages[0]").value("Java"))
                .andExpect(jsonPath("$.backend.frameworks[0]").value("Spring Boot"))
                .andExpect(jsonPath("$.backend.libraries[0]").value("Lombok"))
                .andExpect(jsonPath("$.backend.buildTools[0]").value("Gradle"))
                .andExpect(jsonPath("$.backend.packageManagers[0]").value("Maven"))
                .andExpect(jsonPath("$.backend.linters[0]").value("Checkstyle"))
                .andExpect(jsonPath("$.backend.formatters[0]").value("google-java-format"))
                .andExpect(jsonPath("$.backend.testingTools[0]").value("JUnit"))
                .andExpect(jsonPath("$.backend.ormTools[0]").value("Hibernate"))
                .andExpect(jsonPath("$.backend.auth[0]").value("Spring Security"))

                // infrastructure
                .andExpect(jsonPath("$.infrastructure.clouds[0]").value("AWS"))
                .andExpect(jsonPath("$.infrastructure.operatingSystems[0]").value("Ubuntu"))
                .andExpect(jsonPath("$.infrastructure.containers[0]").value("Docker"))
                .andExpect(jsonPath("$.infrastructure.databases[0]").value("PostgreSQL"))
                .andExpect(jsonPath("$.infrastructure.webServers[0]").value("Nginx"))
                .andExpect(jsonPath("$.infrastructure.ciCdTools[0]").value("GitHub Actions"))
                .andExpect(jsonPath("$.infrastructure.iacTools[0]").value("Terraform"))
                .andExpect(jsonPath("$.infrastructure.monitoringTools[0]").value("CloudWatch"))
                .andExpect(jsonPath("$.infrastructure.loggingTools[0]").value("Fluentd"))

                // tools
                .andExpect(jsonPath("$.tools.sourceControls[0]").value("Git"))
                .andExpect(jsonPath("$.tools.projectManagements[0]").value("Redmine"))
                .andExpect(jsonPath("$.tools.communicationTools[0]").value("Slack"))
                .andExpect(jsonPath("$.tools.documentationTools[0]").value("Confluence"))
                .andExpect(jsonPath("$.tools.apiDevelopmentTools[0]").value("Postman"))
                .andExpect(jsonPath("$.tools.designTools[0]").value("Figma"))
                .andExpect(jsonPath("$.tools.editors[0]").value("VS Code"))
                .andExpect(jsonPath("$.tools.developmentEnvironments[0]").value("WSL2"));

        verify(techStackListQuery).findAll();
    }

    @Test
    @DisplayName("技術スタックが1つも存在しない場合、200と空リスト群がレスポンスとして返る")
    void test2() throws Exception {
        // すべて空リストのDTOを準備
        TechStackListQueryDto.FrontendDto frontend = TechStackListQueryDto.FrontendDto.builder()
                .languages(List.of())
                .frameworks(List.of())
                .libraries(List.of())
                .buildTools(List.of())
                .packageManagers(List.of())
                .linters(List.of())
                .formatters(List.of())
                .testingTools(List.of())
                .build();

        TechStackListQueryDto.BackendDto backend = TechStackListQueryDto.BackendDto.builder()
                .languages(List.of())
                .frameworks(List.of())
                .libraries(List.of())
                .buildTools(List.of())
                .packageManagers(List.of())
                .linters(List.of())
                .formatters(List.of())
                .testingTools(List.of())
                .ormTools(List.of())
                .auth(List.of())
                .build();

        TechStackListQueryDto.InfrastructureDto infrastructure = TechStackListQueryDto.InfrastructureDto.builder()
                .clouds(List.of())
                .operatingSystems(List.of())
                .containers(List.of())
                .databases(List.of())
                .webServers(List.of())
                .ciCdTools(List.of())
                .iacTools(List.of())
                .monitoringTools(List.of())
                .loggingTools(List.of())
                .build();

        TechStackListQueryDto.ToolsDto tools = TechStackListQueryDto.ToolsDto.builder()
                .sourceControls(List.of())
                .projectManagements(List.of())
                .communicationTools(List.of())
                .documentationTools(List.of())
                .apiDevelopmentTools(List.of())
                .designTools(List.of())
                .editors(List.of())
                .developmentEnvironments(List.of())
                .build();

        TechStackListQueryDto dto = TechStackListQueryDto.builder()
                .frontend(frontend)
                .backend(backend)
                .infrastructure(infrastructure)
                .tools(tools)
                .build();

        // モック設定
        when(techStackListQuery.findAll()).thenReturn(dto);

        // 実行&検証
        mockMvc.perform(get(ENDPOINT))
                .andExpect(status().isOk())
                // frontend
                .andExpect(jsonPath("$.frontend.languages").isEmpty())
                .andExpect(jsonPath("$.frontend.frameworks").isEmpty())
                .andExpect(jsonPath("$.frontend.libraries").isEmpty())
                .andExpect(jsonPath("$.frontend.buildTools").isEmpty())
                .andExpect(jsonPath("$.frontend.packageManagers").isEmpty())
                .andExpect(jsonPath("$.frontend.linters").isEmpty())
                .andExpect(jsonPath("$.frontend.formatters").isEmpty())
                .andExpect(jsonPath("$.frontend.testingTools").isEmpty())

                // backend
                .andExpect(jsonPath("$.backend.languages").isEmpty())
                .andExpect(jsonPath("$.backend.frameworks").isEmpty())
                .andExpect(jsonPath("$.backend.libraries").isEmpty())
                .andExpect(jsonPath("$.backend.buildTools").isEmpty())
                .andExpect(jsonPath("$.backend.packageManagers").isEmpty())
                .andExpect(jsonPath("$.backend.linters").isEmpty())
                .andExpect(jsonPath("$.backend.formatters").isEmpty())
                .andExpect(jsonPath("$.backend.testingTools").isEmpty())
                .andExpect(jsonPath("$.backend.ormTools").isEmpty())
                .andExpect(jsonPath("$.backend.auth").isEmpty())

                // infrastructure
                .andExpect(jsonPath("$.infrastructure.clouds").isEmpty())
                .andExpect(jsonPath("$.infrastructure.operatingSystems").isEmpty())
                .andExpect(jsonPath("$.infrastructure.containers").isEmpty())
                .andExpect(jsonPath("$.infrastructure.databases").isEmpty())
                .andExpect(jsonPath("$.infrastructure.webServers").isEmpty())
                .andExpect(jsonPath("$.infrastructure.ciCdTools").isEmpty())
                .andExpect(jsonPath("$.infrastructure.iacTools").isEmpty())
                .andExpect(jsonPath("$.infrastructure.monitoringTools").isEmpty())
                .andExpect(jsonPath("$.infrastructure.loggingTools").isEmpty())

                // tools
                .andExpect(jsonPath("$.tools.sourceControls").isEmpty())
                .andExpect(jsonPath("$.tools.projectManagements").isEmpty())
                .andExpect(jsonPath("$.tools.communicationTools").isEmpty())
                .andExpect(jsonPath("$.tools.documentationTools").isEmpty())
                .andExpect(jsonPath("$.tools.apiDevelopmentTools").isEmpty())
                .andExpect(jsonPath("$.tools.designTools").isEmpty())
                .andExpect(jsonPath("$.tools.editors").isEmpty())
                .andExpect(jsonPath("$.tools.developmentEnvironments").isEmpty());

        verify(techStackListQuery).findAll();
    }
}
