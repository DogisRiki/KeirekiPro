package com.example.keirekipro.unit.domain.model.resume;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;

import com.example.keirekipro.domain.model.resume.TechStack;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class TechStackTest {

    @Test
    @DisplayName("全ての値が正しく設定されている状態でインスタンス化する")
    void test1() {
        TechStack.Frontend frontend = TechStack.Frontend.create(
                List.of("HTML", "CSS", "TypeScript"),
                List.of("React"),
                List.of("MUI", "axios", "Tanstack Query", "React Router", "zustand", "Draft.js", "day.js"),
                List.of("Vite"),
                List.of("npm"),
                List.of("ESLint"),
                List.of("Prettier"),
                List.of("Vitest", "React Testing Library", "StoryBook", "happy-dom"));

        TechStack.Backend backend = TechStack.Backend.create(
                List.of("Java"),
                List.of("Spring Framework"),
                List.of("Apache PDFBox", "ICU4J", "Flyway", "AspectJ", "Jackson", "Apache Commons Validator",
                        "FreeMarker"),
                List.of("Gradle"),
                List.of("Gradle"),
                List.of("CheckStyle"),
                List.of("Google Java Style"),
                List.of("JUnit"),
                List.of("MyBatis"),
                List.of("Spring Security"));

        TechStack.Infrastructure infrastructure = TechStack.Infrastructure.create(
                List.of("AWS"),
                List.of("RHEL9.4"),
                List.of("Docker"),
                List.of("PostgreSQL"),
                List.of("nginx"),
                List.of("Jenkins"),
                List.of("Terraform"),
                List.of("Datadog", "Grafana"),
                List.of("CloudWatch Logs"));

        TechStack.Tools tools = TechStack.Tools.create(
                List.of("GitBucket"),
                List.of("Redmine"),
                List.of("Teams"),
                List.of("Excel", "Marmaid", "Draw.io", "PlantUML"),
                List.of("OpenAPI", "Postman", "Prism"),
                List.of("Figma"),
                List.of("Visual Studio Code"),
                List.of("Windows"));

        TechStack techStack = TechStack.create(frontend, backend, infrastructure, tools);

        assertThat(techStack).isNotNull();
        assertThat(techStack.getFrontend().getLanguages()).hasSize(3);
        assertThat(techStack.getBackend().getOrmTools()).containsExactly("MyBatis");
        assertThat(techStack.getInfrastructure().getOperatingSystems()).containsExactly("RHEL9.4");
        assertThat(techStack.getTools().getSourceControls()).containsExactly("GitBucket");
    }

    @Test
    @DisplayName("一部の値が空の状態でインスタンス化する")
    void test2() {
        TechStack.Frontend frontend = TechStack.Frontend.create(
                List.of("HTML"),
                List.of("React"),
                List.of(), // libraries: 空
                List.of("Vite"),
                List.of("npm"),
                List.of(), // linters: 空
                List.of(), // formatters: 空
                List.of("Vitest"));

        TechStack.Backend backend = TechStack.Backend.create(
                List.of("Java"),
                List.of("Spring Framework"),
                List.of(), // libraries: 空
                List.of("Gradle"),
                List.of("Gradle"),
                List.of(), // linters: 空
                List.of(), // formatters: 空
                List.of("JUnit"),
                List.of(), // ormTools: 空
                List.of()); // auth: 空

        TechStack.Infrastructure infrastructure = TechStack.Infrastructure.create(
                List.of(), // clouds: 空
                List.of("RHEL9.4"),
                List.of(), // containers: 空
                List.of("PostgreSQL"),
                List.of(), // webServers: 空
                List.of(), // ciCdTools: 空
                List.of(), // iacTools: 空
                List.of(), // monitoringTools: 空
                List.of()); // loggingTools: 空

        TechStack.Tools tools = TechStack.Tools.create(
                List.of("GitBucket"),
                List.of("Redmine"),
                List.of(), // communicationTools: 空
                List.of(), // documentationTools: 空
                List.of(), // apiDevelopmentTools: 空
                List.of("Figma"),
                List.of(), // editors: 空
                List.of()); // developmentEnvironments: 空

        TechStack techStack = TechStack.create(frontend, backend, infrastructure, tools);

        assertThat(techStack).isNotNull();
        assertThat(techStack.getFrontend().getLanguages()).hasSize(1);
        assertThat(techStack.getFrontend().getLibraries()).isEmpty();
        assertThat(techStack.getBackend().getOrmTools()).isEmpty();
        assertThat(techStack.getInfrastructure().getClouds()).isEmpty();
        assertThat(techStack.getTools().getDesignTools()).containsExactly("Figma");
    }
}
