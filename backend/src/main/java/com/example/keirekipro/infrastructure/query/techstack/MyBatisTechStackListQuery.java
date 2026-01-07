package com.example.keirekipro.infrastructure.query.techstack;

import java.util.ArrayList;
import java.util.List;

import com.example.keirekipro.usecase.query.techstack.TechStackListQuery;
import com.example.keirekipro.usecase.query.techstack.dto.TechStackListQueryDto;

import org.springframework.stereotype.Repository;

import lombok.RequiredArgsConstructor;

/**
 * 技術スタック一覧取得クエリ実装
 */
@Repository
@RequiredArgsConstructor
public class MyBatisTechStackListQuery implements TechStackListQuery {

    private final TechStackQueryMapper mapper;

    @Override
    public TechStackListQueryDto findAll() {
        List<TechStackQueryMapper.TechStackRow> rows = mapper.selectAll();

        // frontend
        List<String> frontendLanguages = new ArrayList<>();
        List<String> frontendFrameworks = new ArrayList<>();
        List<String> frontendLibraries = new ArrayList<>();
        List<String> frontendBuildTools = new ArrayList<>();
        List<String> frontendPackageManagers = new ArrayList<>();
        List<String> frontendLinters = new ArrayList<>();
        List<String> frontendFormatters = new ArrayList<>();
        List<String> frontendTestingTools = new ArrayList<>();

        // backend
        List<String> backendLanguages = new ArrayList<>();
        List<String> backendFrameworks = new ArrayList<>();
        List<String> backendLibraries = new ArrayList<>();
        List<String> backendBuildTools = new ArrayList<>();
        List<String> backendPackageManagers = new ArrayList<>();
        List<String> backendLinters = new ArrayList<>();
        List<String> backendFormatters = new ArrayList<>();
        List<String> backendTestingTools = new ArrayList<>();
        List<String> backendOrmTools = new ArrayList<>();
        List<String> backendAuth = new ArrayList<>();

        // infrastructure
        List<String> infraClouds = new ArrayList<>();
        List<String> infraOperatingSystems = new ArrayList<>();
        List<String> infraContainers = new ArrayList<>();
        List<String> infraDatabases = new ArrayList<>();
        List<String> infraWebServers = new ArrayList<>();
        List<String> infraCiCdTools = new ArrayList<>();
        List<String> infraIacTools = new ArrayList<>();
        List<String> infraMonitoringTools = new ArrayList<>();
        List<String> infraLoggingTools = new ArrayList<>();

        // tools
        List<String> toolsSourceControls = new ArrayList<>();
        List<String> toolsProjectManagements = new ArrayList<>();
        List<String> toolsCommunicationTools = new ArrayList<>();
        List<String> toolsDocumentationTools = new ArrayList<>();
        List<String> toolsApiDevelopmentTools = new ArrayList<>();
        List<String> toolsDesignTools = new ArrayList<>();
        List<String> toolsEditors = new ArrayList<>();
        List<String> toolsDevelopmentEnvironments = new ArrayList<>();

        for (TechStackQueryMapper.TechStackRow row : rows) {
            String main = row.getMainCategory();
            String sub = row.getSubCategory();
            String name = row.getName();

            switch (main) {
                case "frontend" -> {
                    switch (sub) {
                        case "languages" -> frontendLanguages.add(name);
                        case "framework" -> frontendFrameworks.add(name);
                        case "libraries" -> frontendLibraries.add(name);
                        case "buildTool" -> frontendBuildTools.add(name);
                        case "packageManager" -> frontendPackageManagers.add(name);
                        case "linters" -> frontendLinters.add(name);
                        case "formatters" -> frontendFormatters.add(name);
                        case "testingTools" -> frontendTestingTools.add(name);
                        default -> {
                        }
                    }
                }
                case "backend" -> {
                    switch (sub) {
                        case "languages" -> backendLanguages.add(name);
                        case "framework" -> backendFrameworks.add(name);
                        case "libraries" -> backendLibraries.add(name);
                        case "buildTool" -> backendBuildTools.add(name);
                        case "packageManager" -> backendPackageManagers.add(name);
                        case "linters" -> backendLinters.add(name);
                        case "formatters" -> backendFormatters.add(name);
                        case "testingTools" -> backendTestingTools.add(name);
                        case "ormTools" -> backendOrmTools.add(name);
                        case "auth" -> backendAuth.add(name);
                        default -> {
                        }
                    }
                }
                case "infrastructure" -> {
                    switch (sub) {
                        case "clouds" -> infraClouds.add(name);
                        case "operatingSystem" -> infraOperatingSystems.add(name);
                        case "containers" -> infraContainers.add(name);
                        case "database" -> infraDatabases.add(name);
                        case "webServer" -> infraWebServers.add(name);
                        case "ciCdTool" -> infraCiCdTools.add(name);
                        case "iacTools" -> infraIacTools.add(name);
                        case "monitoringTools" -> infraMonitoringTools.add(name);
                        case "loggingTools" -> infraLoggingTools.add(name);
                        default -> {
                        }
                    }
                }
                case "tools" -> {
                    switch (sub) {
                        case "sourceControl" -> toolsSourceControls.add(name);
                        case "projectManagement" -> toolsProjectManagements.add(name);
                        case "communicationTool" -> toolsCommunicationTools.add(name);
                        case "documentationTools" -> toolsDocumentationTools.add(name);
                        case "apiDevelopmentTools" -> toolsApiDevelopmentTools.add(name);
                        case "designTools" -> toolsDesignTools.add(name);
                        case "editor" -> toolsEditors.add(name);
                        case "developmentEnvironment" -> toolsDevelopmentEnvironments.add(name);
                        default -> {
                        }
                    }
                }
                default -> {
                }
            }
        }

        TechStackListQueryDto.FrontendDto frontend = TechStackListQueryDto.FrontendDto.builder()
                .languages(frontendLanguages)
                .frameworks(frontendFrameworks)
                .libraries(frontendLibraries)
                .buildTools(frontendBuildTools)
                .packageManagers(frontendPackageManagers)
                .linters(frontendLinters)
                .formatters(frontendFormatters)
                .testingTools(frontendTestingTools)
                .build();

        TechStackListQueryDto.BackendDto backend = TechStackListQueryDto.BackendDto.builder()
                .languages(backendLanguages)
                .frameworks(backendFrameworks)
                .libraries(backendLibraries)
                .buildTools(backendBuildTools)
                .packageManagers(backendPackageManagers)
                .linters(backendLinters)
                .formatters(backendFormatters)
                .testingTools(backendTestingTools)
                .ormTools(backendOrmTools)
                .auth(backendAuth)
                .build();

        TechStackListQueryDto.InfrastructureDto infrastructure = TechStackListQueryDto.InfrastructureDto.builder()
                .clouds(infraClouds)
                .operatingSystems(infraOperatingSystems)
                .containers(infraContainers)
                .databases(infraDatabases)
                .webServers(infraWebServers)
                .ciCdTools(infraCiCdTools)
                .iacTools(infraIacTools)
                .monitoringTools(infraMonitoringTools)
                .loggingTools(infraLoggingTools)
                .build();

        TechStackListQueryDto.ToolsDto tools = TechStackListQueryDto.ToolsDto.builder()
                .sourceControls(toolsSourceControls)
                .projectManagements(toolsProjectManagements)
                .communicationTools(toolsCommunicationTools)
                .documentationTools(toolsDocumentationTools)
                .apiDevelopmentTools(toolsApiDevelopmentTools)
                .designTools(toolsDesignTools)
                .editors(toolsEditors)
                .developmentEnvironments(toolsDevelopmentEnvironments)
                .build();

        return TechStackListQueryDto.builder()
                .frontend(frontend)
                .backend(backend)
                .infrastructure(infrastructure)
                .tools(tools)
                .build();
    }
}
