package com.example.keirekipro.usecase.techstack;

import java.util.ArrayList;
import java.util.List;

import com.example.keirekipro.infrastructure.repository.techstack.TechStackDto;
import com.example.keirekipro.infrastructure.repository.techstack.TechStackMapper;
import com.example.keirekipro.usecase.techstack.dto.TechStackListUseCaseDto;

import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * 技術スタック一覧取得ユースケース
 */
@Service
@RequiredArgsConstructor
public class GetTechStackListUseCase {

    private final TechStackMapper techStackMapper;

    /**
     * 技術スタック一覧取得ユースケースを実行する
     *
     * @return 技術スタック一覧ユースケースDTO
     */
    public TechStackListUseCaseDto execute() {

        List<TechStackDto> rows = techStackMapper.selectAll();

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

        for (TechStackDto row : rows) {
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
                            // 想定外は何もしない
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

        TechStackListUseCaseDto.Frontend frontend = TechStackListUseCaseDto.Frontend.create(
                frontendLanguages,
                frontendFrameworks,
                frontendLibraries,
                frontendBuildTools,
                frontendPackageManagers,
                frontendLinters,
                frontendFormatters,
                frontendTestingTools);

        TechStackListUseCaseDto.Backend backend = TechStackListUseCaseDto.Backend.create(
                backendLanguages,
                backendFrameworks,
                backendLibraries,
                backendBuildTools,
                backendPackageManagers,
                backendLinters,
                backendFormatters,
                backendTestingTools,
                backendOrmTools,
                backendAuth);

        TechStackListUseCaseDto.Infrastructure infrastructure = TechStackListUseCaseDto.Infrastructure.create(
                infraClouds,
                infraOperatingSystems,
                infraContainers,
                infraDatabases,
                infraWebServers,
                infraCiCdTools,
                infraIacTools,
                infraMonitoringTools,
                infraLoggingTools);

        TechStackListUseCaseDto.Tools tools = TechStackListUseCaseDto.Tools.create(
                toolsSourceControls,
                toolsProjectManagements,
                toolsCommunicationTools,
                toolsDocumentationTools,
                toolsApiDevelopmentTools,
                toolsDesignTools,
                toolsEditors,
                toolsDevelopmentEnvironments);

        return TechStackListUseCaseDto.create(frontend, backend, infrastructure, tools);
    }
}
