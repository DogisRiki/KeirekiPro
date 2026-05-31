package com.example.keirekipro.usecase.resume.command;

import java.time.YearMonth;
import java.util.List;
import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * プロジェクト更新ユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class UpdateProjectCommand {

    private UUID userId;
    private String resumeId;
    private UUID projectId;
    private String companyName;
    private YearMonth startDate;
    private YearMonth endDate;
    private Boolean active;

    private String name;
    private String overview;
    private String teamComp;
    private String role;
    private String achievement;
    private Boolean requirements;
    private Boolean basicDesign;
    private Boolean detailedDesign;
    private Boolean implementation;
    private Boolean integrationTest;
    private Boolean systemTest;
    private Boolean maintenance;
    private List<String> frontendLanguages;
    private List<String> frontendFrameworks;
    private List<String> frontendLibraries;
    private List<String> frontendBuildTools;
    private List<String> frontendPackageManagers;
    private List<String> frontendLinters;
    private List<String> frontendFormatters;
    private List<String> frontendTestingTools;
    private List<String> backendLanguages;
    private List<String> backendFrameworks;
    private List<String> backendLibraries;
    private List<String> backendBuildTools;
    private List<String> backendPackageManagers;
    private List<String> backendLinters;
    private List<String> backendFormatters;
    private List<String> backendTestingTools;
    private List<String> ormTools;
    private List<String> auth;
    private List<String> clouds;
    private List<String> operatingSystems;
    private List<String> containers;
    private List<String> databases;
    private List<String> webServers;
    private List<String> ciCdTools;
    private List<String> iacTools;
    private List<String> monitoringTools;
    private List<String> loggingTools;
    private List<String> sourceControls;
    private List<String> projectManagements;
    private List<String> communicationTools;
    private List<String> documentationTools;
    private List<String> apiDevelopmentTools;
    private List<String> designTools;
    private List<String> editors;
    private List<String> developmentEnvironments;
}
