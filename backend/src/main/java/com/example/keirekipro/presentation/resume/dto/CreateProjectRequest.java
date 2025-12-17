package com.example.keirekipro.presentation.resume.dto;

import java.time.YearMonth;
import java.util.List;

import com.example.keirekipro.presentation.shared.validator.YearMonthRange;
import com.fasterxml.jackson.annotation.JsonFormat;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * 職務経歴書 プロジェクト新規作成リクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class CreateProjectRequest {

    @NotBlank(message = "会社名は入力必須です。")
    @Size(max = 50, message = "会社名は50文字以内で入力してください。")
    private String companyName;

    @NotNull(message = "開始年月は入力必須です。")
    @YearMonthRange(message = "開始年月が不正です。")
    @JsonFormat(pattern = "yyyy-MM")
    private YearMonth startDate;

    @YearMonthRange(message = "終了年月が不正です。")
    @JsonFormat(pattern = "yyyy-MM")
    private YearMonth endDate;

    @NotNull(message = "継続中は入力必須です。")
    private Boolean isActive;

    @NotBlank(message = "プロジェクト名は入力必須です。")
    @Size(max = 50, message = "プロジェクト名は50文字以内で入力してください。")
    private String name;

    @NotBlank(message = "プロジェクト概要は入力必須です。")
    @Size(max = 1000, message = "プロジェクト概要は1000文字以内で入力してください。")
    private String overview;

    @NotBlank(message = "チーム構成は入力必須です。")
    @Size(max = 100, message = "チーム構成は100文字以内で入力してください。")
    private String teamComp;

    @NotBlank(message = "役割は入力必須です。")
    @Size(max = 1000, message = "役割は1000文字以内で入力してください。")
    private String role;

    @NotBlank(message = "成果は入力必須です。")
    @Size(max = 1000, message = "成果は1000文字以内で入力してください。")
    private String achievement;

    // 作業工程
    @NotNull
    private Boolean requirements;

    @NotNull
    private Boolean basicDesign;

    @NotNull
    private Boolean detailedDesign;

    @NotNull
    private Boolean implementation;

    @NotNull
    private Boolean integrationTest;

    @NotNull
    private Boolean systemTest;

    @NotNull
    private Boolean maintenance;

    // TechStack - Frontend
    private List<String> frontendLanguages;
    private List<String> frontendFrameworks;
    private List<String> frontendLibraries;
    private List<String> frontendBuildTools;
    private List<String> frontendPackageManagers;
    private List<String> frontendLinters;
    private List<String> frontendFormatters;
    private List<String> frontendTestingTools;

    // TechStack - Backend
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

    // TechStack - Infrastructure
    private List<String> clouds;
    private List<String> operatingSystems;
    private List<String> containers;
    private List<String> databases;
    private List<String> webServers;
    private List<String> ciCdTools;
    private List<String> iacTools;
    private List<String> monitoringTools;
    private List<String> loggingTools;

    // TechStack - Tools
    private List<String> sourceControls;
    private List<String> projectManagements;
    private List<String> communicationTools;
    private List<String> documentationTools;
    private List<String> apiDevelopmentTools;
    private List<String> designTools;
    private List<String> editors;
    private List<String> developmentEnvironments;
}
