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
        TechStack.Dependencies dependencies = TechStack.Dependencies.create(
                List.of("Spring Framework", "Django", "React"),
                List.of("Jackson", "Flyway", "numpy", "ESLint", "Prettier"),
                List.of("JUnit", "pytest", "Jest"),
                List.of("MyBatis"),
                List.of("npm", "Poetry"));

        TechStack.Infrastructure infrastructure = TechStack.Infrastructure.create(
                List.of("AWS"),
                List.of("Docker"),
                List.of("PostgreSQL"),
                List.of("Nginx"),
                List.of("Github Actions"),
                List.of("Terraform"),
                List.of("Datadog", "Grafana"),
                List.of("CloudWatch Logs"));

        TechStack.Tools tools = TechStack.Tools.create(
                List.of("Git"),
                List.of("Jira", "Redmine"),
                List.of("Slack", "Microsoft Teams"),
                List.of("Confluence"),
                List.of("Postman", "Swagger"),
                List.of("Figma"));

        TechStack techStack = TechStack.create(
                List.of("Java", "Python", "JavaScript", "TypeScript"),
                dependencies,
                infrastructure,
                tools);

        assertThat(techStack).isNotNull();
        assertThat(techStack.getLanguages().size()).isEqualTo(4);
        assertThat(techStack.getDependencies().getFrameworks().size()).isEqualTo(3);
        assertThat(techStack.getInfrastructure().getContainers().get(0)).isEqualTo("Docker");
        assertThat(techStack.getTools().getDesignTools().get(0)).isEqualTo("Figma");
    }

    @Test
    @DisplayName("一部の値が空の状態でインスタンス化する")
    void test2() {
        TechStack.Dependencies dependencies = TechStack.Dependencies.create(
                List.of("Spring Framework"),
                List.of(), // libraries: 空
                List.of("JUnit"),
                List.of("MyBatis"),
                List.of() // packageManagers: 空
        );

        TechStack.Infrastructure infrastructure = TechStack.Infrastructure.create(
                List.of("AWS"),
                List.of(), // containers: 空
                List.of("PostgreSQL"),
                List.of(), // webServers: 空
                List.of("Github Actions"),
                List.of("Terraform"),
                List.of(), // monitoringTools: 空
                List.of() // loggingTools: 空
        );

        TechStack.Tools tools = TechStack.Tools.create(
                List.of("Git"),
                List.of("Jira"),
                List.of(), // communicationTools: 空
                List.of("Confluence"),
                List.of(), // apiDevelopmentTools: 空
                List.of("Figma"));

        TechStack techStack = TechStack.create(
                List.of("Java"),
                dependencies,
                infrastructure,
                tools);

        assertThat(techStack).isNotNull();
        assertThat(techStack.getLanguages().size()).isEqualTo(1);
        assertThat(techStack.getDependencies().getLibraries().size()).isEqualTo(0);
        assertThat(techStack.getInfrastructure().getContainers().size()).isEqualTo(0);
        assertThat(techStack.getTools().getDesignTools().size()).isEqualTo(1);
    }
}
