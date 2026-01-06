package com.example.keirekipro.infrastructure.query.resume;

import java.time.LocalDate;
import java.time.YearMonth;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.usecase.query.resume.ResumeBackupQuery;
import com.example.keirekipro.usecase.query.resume.dto.ResumeBackupQueryDto;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.springframework.stereotype.Repository;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書バックアップ用クエリ実装
 */
@Repository
@RequiredArgsConstructor
public class MyBatisResumeBackupQuery implements ResumeBackupQuery {

    private final ResumeQueryMapper mapper;

    private final ObjectMapper objectMapper;

    @Override
    public Optional<ResumeBackupQueryDto> findByIdForBackup(UUID resumeId, UUID userId) {
        String json = mapper.selectResumeForBackup(resumeId, userId);
        if (json == null) {
            return Optional.empty();
        }

        try {
            JsonNode root = objectMapper.readTree(json);
            return Optional.of(parseResumeBackupQueryDto(root));
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("バックアップデータのパースに失敗しました", e);
        }
    }

    /**
     * JSONノードからResumeBackupQueryDtoを生成する
     *
     * @param root JSONルートノード
     * @return ResumeBackupQueryDto
     */
    private ResumeBackupQueryDto parseResumeBackupQueryDto(JsonNode root) {
        return ResumeBackupQueryDto.builder()
                .resumeName(getTextOrNull(root, "resumeName"))
                .date(parseLocalDate(root.get("date")))
                .lastName(getTextOrNull(root, "lastName"))
                .firstName(getTextOrNull(root, "firstName"))
                .careers(parseCareers(root.get("careers")))
                .projects(parseProjects(root.get("projects")))
                .certifications(parseCertifications(root.get("certifications")))
                .portfolios(parsePortfolios(root.get("portfolios")))
                .snsPlatforms(parseSnsPlatforms(root.get("snsPlatforms")))
                .selfPromotions(parseSelfPromotions(root.get("selfPromotions")))
                .build();
    }

    /**
     * 職歴リストをパースする
     */
    private List<ResumeBackupQueryDto.CareerDto> parseCareers(JsonNode careersNode) {
        List<ResumeBackupQueryDto.CareerDto> careers = new ArrayList<>();
        if (careersNode != null && careersNode.isArray()) {
            for (JsonNode node : careersNode) {
                careers.add(ResumeBackupQueryDto.CareerDto.builder()
                        .companyName(getTextOrNull(node, "companyName"))
                        .startDate(parseYearMonth(node.get("startDate")))
                        .endDate(parseYearMonth(node.get("endDate")))
                        .active(node.path("active").asBoolean(false))
                        .build());
            }
        }
        return careers;
    }

    /**
     * プロジェクトリストをパースする
     */
    private List<ResumeBackupQueryDto.ProjectDto> parseProjects(JsonNode projectsNode) {
        List<ResumeBackupQueryDto.ProjectDto> projects = new ArrayList<>();
        if (projectsNode != null && projectsNode.isArray()) {
            for (JsonNode node : projectsNode) {
                // processオブジェクトをパース
                JsonNode processNode = node.get("process");
                ResumeBackupQueryDto.ProcessDto process = ResumeBackupQueryDto.ProcessDto.builder()
                        .requirements(processNode != null && processNode.path("requirements").asBoolean(false))
                        .basicDesign(processNode != null && processNode.path("basicDesign").asBoolean(false))
                        .detailedDesign(processNode != null && processNode.path("detailedDesign").asBoolean(false))
                        .implementation(processNode != null && processNode.path("implementation").asBoolean(false))
                        .integrationTest(processNode != null && processNode.path("integrationTest").asBoolean(false))
                        .systemTest(processNode != null && processNode.path("systemTest").asBoolean(false))
                        .maintenance(processNode != null && processNode.path("maintenance").asBoolean(false))
                        .build();

                // techStackオブジェクトをパース
                JsonNode techStackNode = node.get("techStack");
                ResumeBackupQueryDto.TechStackDto techStack = parseTechStack(techStackNode);

                projects.add(ResumeBackupQueryDto.ProjectDto.builder()
                        .companyName(getTextOrNull(node, "companyName"))
                        .startDate(parseYearMonth(node.get("startDate")))
                        .endDate(parseYearMonth(node.get("endDate")))
                        .active(node.path("active").asBoolean(false))
                        .name(getTextOrNull(node, "name"))
                        .overview(getTextOrNull(node, "overview"))
                        .teamComp(getTextOrNull(node, "teamComp"))
                        .role(getTextOrNull(node, "role"))
                        .achievement(getTextOrNull(node, "achievement"))
                        .process(process)
                        .techStack(techStack)
                        .build());
            }
        }
        return projects;
    }

    /**
     * 技術スタックをパースする
     */
    private ResumeBackupQueryDto.TechStackDto parseTechStack(JsonNode techStackNode) {
        if (techStackNode == null || techStackNode.isNull()) {
            return createEmptyTechStack();
        }

        JsonNode frontendNode = techStackNode.get("frontend");
        JsonNode backendNode = techStackNode.get("backend");
        JsonNode infrastructureNode = techStackNode.get("infrastructure");
        JsonNode toolsNode = techStackNode.get("tools");

        return ResumeBackupQueryDto.TechStackDto.builder()
                .frontend(ResumeBackupQueryDto.FrontendDto.builder()
                        .languages(parseStringList(frontendNode != null ? frontendNode.get("languages") : null))
                        .frameworks(parseStringList(frontendNode != null ? frontendNode.get("frameworks") : null))
                        .libraries(parseStringList(frontendNode != null ? frontendNode.get("libraries") : null))
                        .buildTools(parseStringList(frontendNode != null ? frontendNode.get("buildTools") : null))
                        .packageManagers(
                                parseStringList(frontendNode != null ? frontendNode.get("packageManagers") : null))
                        .linters(parseStringList(frontendNode != null ? frontendNode.get("linters") : null))
                        .formatters(parseStringList(frontendNode != null ? frontendNode.get("formatters") : null))
                        .testingTools(parseStringList(frontendNode != null ? frontendNode.get("testingTools") : null))
                        .build())
                .backend(ResumeBackupQueryDto.BackendDto.builder()
                        .languages(parseStringList(backendNode != null ? backendNode.get("languages") : null))
                        .frameworks(parseStringList(backendNode != null ? backendNode.get("frameworks") : null))
                        .libraries(parseStringList(backendNode != null ? backendNode.get("libraries") : null))
                        .buildTools(parseStringList(backendNode != null ? backendNode.get("buildTools") : null))
                        .packageManagers(
                                parseStringList(backendNode != null ? backendNode.get("packageManagers") : null))
                        .linters(parseStringList(backendNode != null ? backendNode.get("linters") : null))
                        .formatters(parseStringList(backendNode != null ? backendNode.get("formatters") : null))
                        .testingTools(parseStringList(backendNode != null ? backendNode.get("testingTools") : null))
                        .ormTools(parseStringList(backendNode != null ? backendNode.get("ormTools") : null))
                        .auth(parseStringList(backendNode != null ? backendNode.get("auth") : null))
                        .build())
                .infrastructure(ResumeBackupQueryDto.InfrastructureDto.builder()
                        .clouds(parseStringList(infrastructureNode != null ? infrastructureNode.get("clouds") : null))
                        .operatingSystems(parseStringList(
                                infrastructureNode != null ? infrastructureNode.get("operatingSystems") : null))
                        .containers(
                                parseStringList(
                                        infrastructureNode != null ? infrastructureNode.get("containers") : null))
                        .databases(
                                parseStringList(
                                        infrastructureNode != null ? infrastructureNode.get("databases") : null))
                        .webServers(
                                parseStringList(
                                        infrastructureNode != null ? infrastructureNode.get("webServers") : null))
                        .ciCdTools(
                                parseStringList(
                                        infrastructureNode != null ? infrastructureNode.get("ciCdTools") : null))
                        .iacTools(
                                parseStringList(infrastructureNode != null ? infrastructureNode.get("iacTools") : null))
                        .monitoringTools(parseStringList(
                                infrastructureNode != null ? infrastructureNode.get("monitoringTools") : null))
                        .loggingTools(parseStringList(
                                infrastructureNode != null ? infrastructureNode.get("loggingTools") : null))
                        .build())
                .tools(ResumeBackupQueryDto.ToolsDto.builder()
                        .sourceControls(parseStringList(toolsNode != null ? toolsNode.get("sourceControls") : null))
                        .projectManagements(
                                parseStringList(toolsNode != null ? toolsNode.get("projectManagements") : null))
                        .communicationTools(
                                parseStringList(toolsNode != null ? toolsNode.get("communicationTools") : null))
                        .documentationTools(
                                parseStringList(toolsNode != null ? toolsNode.get("documentationTools") : null))
                        .apiDevelopmentTools(
                                parseStringList(toolsNode != null ? toolsNode.get("apiDevelopmentTools") : null))
                        .designTools(parseStringList(toolsNode != null ? toolsNode.get("designTools") : null))
                        .editors(parseStringList(toolsNode != null ? toolsNode.get("editors") : null))
                        .developmentEnvironments(
                                parseStringList(toolsNode != null ? toolsNode.get("developmentEnvironments") : null))
                        .build())
                .build();
    }

    /**
     * 空の技術スタックを作成する
     */
    private ResumeBackupQueryDto.TechStackDto createEmptyTechStack() {
        return ResumeBackupQueryDto.TechStackDto.builder()
                .frontend(ResumeBackupQueryDto.FrontendDto.builder()
                        .languages(List.of())
                        .frameworks(List.of())
                        .libraries(List.of())
                        .buildTools(List.of())
                        .packageManagers(List.of())
                        .linters(List.of())
                        .formatters(List.of())
                        .testingTools(List.of())
                        .build())
                .backend(ResumeBackupQueryDto.BackendDto.builder()
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
                        .build())
                .infrastructure(ResumeBackupQueryDto.InfrastructureDto.builder()
                        .clouds(List.of())
                        .operatingSystems(List.of())
                        .containers(List.of())
                        .databases(List.of())
                        .webServers(List.of())
                        .ciCdTools(List.of())
                        .iacTools(List.of())
                        .monitoringTools(List.of())
                        .loggingTools(List.of())
                        .build())
                .tools(ResumeBackupQueryDto.ToolsDto.builder()
                        .sourceControls(List.of())
                        .projectManagements(List.of())
                        .communicationTools(List.of())
                        .documentationTools(List.of())
                        .apiDevelopmentTools(List.of())
                        .designTools(List.of())
                        .editors(List.of())
                        .developmentEnvironments(List.of())
                        .build())
                .build();
    }

    /**
     * 資格リストをパースする
     */
    private List<ResumeBackupQueryDto.CertificationDto> parseCertifications(JsonNode certificationsNode) {
        List<ResumeBackupQueryDto.CertificationDto> certifications = new ArrayList<>();
        if (certificationsNode != null && certificationsNode.isArray()) {
            for (JsonNode node : certificationsNode) {
                certifications.add(ResumeBackupQueryDto.CertificationDto.builder()
                        .name(getTextOrNull(node, "name"))
                        .date(parseYearMonth(node.get("date")))
                        .build());
            }
        }
        return certifications;
    }

    /**
     * ポートフォリオリストをパースする
     */
    private List<ResumeBackupQueryDto.PortfolioDto> parsePortfolios(JsonNode portfoliosNode) {
        List<ResumeBackupQueryDto.PortfolioDto> portfolios = new ArrayList<>();
        if (portfoliosNode != null && portfoliosNode.isArray()) {
            for (JsonNode node : portfoliosNode) {
                portfolios.add(ResumeBackupQueryDto.PortfolioDto.builder()
                        .name(getTextOrNull(node, "name"))
                        .overview(getTextOrNull(node, "overview"))
                        .techStack(getTextOrNull(node, "techStack"))
                        .link(getTextOrNull(node, "link"))
                        .build());
            }
        }
        return portfolios;
    }

    /**
     * SNSプラットフォームリストをパースする
     */
    private List<ResumeBackupQueryDto.SnsPlatformDto> parseSnsPlatforms(JsonNode snsPlatformsNode) {
        List<ResumeBackupQueryDto.SnsPlatformDto> snsPlatforms = new ArrayList<>();
        if (snsPlatformsNode != null && snsPlatformsNode.isArray()) {
            for (JsonNode node : snsPlatformsNode) {
                snsPlatforms.add(ResumeBackupQueryDto.SnsPlatformDto.builder()
                        .name(getTextOrNull(node, "name"))
                        .link(getTextOrNull(node, "link"))
                        .build());
            }
        }
        return snsPlatforms;
    }

    /**
     * 自己PRリストをパースする
     */
    private List<ResumeBackupQueryDto.SelfPromotionDto> parseSelfPromotions(JsonNode selfPromotionsNode) {
        List<ResumeBackupQueryDto.SelfPromotionDto> selfPromotions = new ArrayList<>();
        if (selfPromotionsNode != null && selfPromotionsNode.isArray()) {
            for (JsonNode node : selfPromotionsNode) {
                selfPromotions.add(ResumeBackupQueryDto.SelfPromotionDto.builder()
                        .title(getTextOrNull(node, "title"))
                        .content(getTextOrNull(node, "content"))
                        .build());
            }
        }
        return selfPromotions;
    }

    /**
     * 文字列リストをパースする
     */
    private List<String> parseStringList(JsonNode arrayNode) {
        List<String> list = new ArrayList<>();
        if (arrayNode != null && arrayNode.isArray()) {
            for (JsonNode node : arrayNode) {
                if (!node.isNull()) {
                    list.add(node.asText());
                }
            }
        }
        return list;
    }

    /**
     * JsonNodeからテキストを取得（nullの場合はnullを返す）
     */
    private String getTextOrNull(JsonNode node, String fieldName) {
        JsonNode fieldNode = node.get(fieldName);
        if (fieldNode == null || fieldNode.isNull()) {
            return null;
        }
        return fieldNode.asText();
    }

    /**
     * LocalDateをパースする
     */
    private LocalDate parseLocalDate(JsonNode node) {
        if (node == null || node.isNull()) {
            return null;
        }
        return LocalDate.parse(node.asText());
    }

    /**
     * YearMonthをパースする（yyyy-MM-dd形式から）
     */
    private YearMonth parseYearMonth(JsonNode node) {
        if (node == null || node.isNull()) {
            return null;
        }
        String dateStr = node.asText();
        // DBのDATE型はyyyy-MM-dd形式で返される
        LocalDate localDate = LocalDate.parse(dateStr, DateTimeFormatter.ISO_LOCAL_DATE);
        return YearMonth.of(localDate.getYear(), localDate.getMonth());
    }
}
