package com.example.keirekipro.unit.architecture;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.classes;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.methods;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;
import static com.tngtech.archunit.library.dependencies.SlicesRuleDefinition.slices;

import java.util.List;

import com.tngtech.archunit.core.domain.JavaClass;
import com.tngtech.archunit.core.domain.JavaClasses;
import com.tngtech.archunit.core.domain.JavaMethod;
import com.tngtech.archunit.core.domain.JavaModifier;
import com.tngtech.archunit.core.importer.ImportOption;
import com.tngtech.archunit.junit.AnalyzeClasses;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.lang.ArchCondition;
import com.tngtech.archunit.lang.ConditionEvents;
import com.tngtech.archunit.lang.SimpleConditionEvent;

import org.junit.jupiter.api.DisplayName;

@AnalyzeClasses(packages = "com.example.keirekipro", importOptions = ImportOption.DoNotIncludeTests.class)
class BackendArchitectureTest {

    private static final String PRESENTATION = "..presentation..";
    private static final String USECASE = "..usecase..";
    private static final String DOMAIN = "..domain..";
    private static final String INFRASTRUCTURE = "..infrastructure..";

    @DisplayName("ドメイン層は外側の層に依存しない")
    @ArchTest
    static void domainLayerShouldNotDependOnOuterLayers(JavaClasses classesToCheck) {
        noClasses()
                .that().resideInAPackage(DOMAIN)
                .should().dependOnClassesThat().resideInAnyPackage(PRESENTATION, USECASE, INFRASTRUCTURE)
                .check(classesToCheck);
    }

    @DisplayName("ユースケース層はプレゼンテーション層とインフラストラクチャ層に依存しない")
    @ArchTest
    static void usecaseLayerShouldNotDependOnPresentationOrInfrastructure(JavaClasses classesToCheck) {
        noClasses()
                .that().resideInAPackage(USECASE)
                .should().dependOnClassesThat().resideInAnyPackage(PRESENTATION, INFRASTRUCTURE)
                .check(classesToCheck);
    }

    @DisplayName("ユースケース層はプレゼンテーションDTOを使用しない")
    @ArchTest
    static void usecaseLayerShouldNotUsePresentationDtos(JavaClasses classesToCheck) {
        noClasses()
                .that().resideInAPackage(USECASE)
                .should().dependOnClassesThat().resideInAPackage("..presentation..dto..")
                .check(classesToCheck);
    }

    @DisplayName("コントローラーは公開handleメソッドを1つだけ持つ")
    @ArchTest
    static void controllersExposeExactlyOnePublicHandleMethod(JavaClasses classesToCheck) {
        classes()
                .that().resideInAPackage("..presentation..controller..")
                .and().haveSimpleNameEndingWith("Controller")
                .should(haveExactlyOnePublicMethodNamed("handle"))
                .check(classesToCheck);
    }

    @DisplayName("ユースケースは公開executeメソッドを1つだけ持つ")
    @ArchTest
    static void usecasesExposeExactlyOnePublicExecuteMethod(JavaClasses classesToCheck) {
        classes()
                .that().resideInAPackage(USECASE)
                .and().haveSimpleNameEndingWith("UseCase")
                .should(haveExactlyOnePublicMethodNamed("execute"))
                .check(classesToCheck);
    }

    @DisplayName("コマンドクラスはcommandパッケージに配置する")
    @ArchTest
    static void commandClassesLiveInCommandPackages(JavaClasses classesToCheck) {
        classes()
                .that().haveSimpleNameEndingWith("Command")
                .and().resideInAPackage(USECASE)
                .should().resideInAPackage("..usecase..command..")
                .check(classesToCheck);
    }

    @DisplayName("クエリ型はqueryパッケージに配置する")
    @ArchTest
    static void queryTypesLiveInQueryPackages(JavaClasses classesToCheck) {
        classes()
                .that().haveSimpleNameEndingWith("Query")
                .should().resideInAnyPackage("..usecase..query..", "..infrastructure..query..")
                .check(classesToCheck);
    }

    @DisplayName("マッパー型はインフラストラクチャ層に配置する")
    @ArchTest
    static void mapperTypesStayInInfrastructure(JavaClasses classesToCheck) {
        classes()
                .that().haveSimpleNameEndingWith("Mapper")
                .should().resideInAPackage("..infrastructure..")
                .check(classesToCheck);
    }

    @DisplayName("インフラストラクチャDTOは許可されたインフラストラクチャ配下に配置する")
    @ArchTest
    static void infrastructureDtosStayInApprovedInfrastructurePackages(JavaClasses classesToCheck) {
        classes()
                .that().haveSimpleNameEndingWith("Dto")
                .and().resideInAPackage("..infrastructure..")
                .should().resideInAnyPackage(
                        "..infrastructure..repository..",
                        "..infrastructure..query..",
                        "..infrastructure..auth..oidc..dto..")
                .check(classesToCheck);
    }

    @DisplayName("ドメインイベントは外側の層に依存しない")
    @ArchTest
    static void domainEventsAreIndependentFromOuterLayers(JavaClasses classesToCheck) {
        noClasses()
                .that().resideInAPackage("..domain..event..")
                .should().dependOnClassesThat().resideInAnyPackage(PRESENTATION, USECASE, INFRASTRUCTURE)
                .check(classesToCheck);
    }

    @DisplayName("セキュリティ関連コードはドメイン層に漏れ込まない")
    @ArchTest
    static void securityCodeMustNotLeakIntoDomain(JavaClasses classesToCheck) {
        noClasses()
                .that().resideInAPackage(DOMAIN)
                .should().dependOnClassesThat()
                .resideInAnyPackage("..presentation..security..", "..infrastructure..security..")
                .check(classesToCheck);
    }

    @DisplayName("RedisとAWS依存はインフラストラクチャ層に閉じる")
    @ArchTest
    static void redisAndAwsDependenciesStayInInfrastructure(JavaClasses classesToCheck) {
        noClasses()
                .that().resideOutsideOfPackage(INFRASTRUCTURE)
                .should().dependOnClassesThat().resideInAnyPackage(
                        "org.springframework.data.redis..",
                        "software.amazon.awssdk..",
                        "io.awspring.cloud..")
                .check(classesToCheck);
    }

    @DisplayName("エクスポート実装はインフラストラクチャ層に配置する")
    @ArchTest
    static void exportImplementationsStayInInfrastructure(JavaClasses classesToCheck) {
        noClasses()
                .that().resideOutsideOfPackage("..infrastructure..export..")
                .should().dependOnClassesThat().resideInAPackage("..infrastructure..export..")
                .check(classesToCheck);
    }

    @DisplayName("ロギングAspectはインフラストラクチャのlogging配下に配置する")
    @ArchTest
    static void loggingAspectsStayInInfrastructureLogging(JavaClasses classesToCheck) {
        classes()
                .that().haveSimpleNameEndingWith("Aspect")
                .should().resideInAPackage("..infrastructure..logging..")
                .check(classesToCheck);
    }

    @DisplayName("本番コードは使用禁止APIを呼び出さない")
    @ArchTest
    static void productionCodeDoesNotUseForbiddenApis(JavaClasses classesToCheck) {
        noClasses()
                .should().callMethod(System.class, "exit", int.class)
                .orShould().callMethod(Thread.class, "sleep", long.class)
                .orShould().callMethod(Throwable.class, "printStackTrace")
                .check(classesToCheck);
    }

    @DisplayName("トップレベルパッケージ間に循環依存がない")
    @ArchTest
    static void topLevelPackagesAreFreeOfCycles(JavaClasses classesToCheck) {
        slices()
                .matching("com.example.keirekipro.(*)..")
                .should().beFreeOfCycles()
                .check(classesToCheck);
    }

    @DisplayName("本番コードはテストライブラリに依存しない")
    @ArchTest
    static void productionCodeDoesNotDependOnTestLibraries(JavaClasses classesToCheck) {
        noClasses()
                .should().dependOnClassesThat().resideInAnyPackage(
                        "org.junit..",
                        "org.mockito..",
                        "org.assertj..",
                        "org.springframework.boot.test..",
                        "org.testcontainers..")
                .check(classesToCheck);
    }

    @DisplayName("コントローラーの公開ハンドラメソッド名はhandleに統一する")
    @ArchTest
    static void controllerPublicHandlerMethodsAreNamedHandle(JavaClasses classesToCheck) {
        methods()
                .that().arePublic()
                .and().areDeclaredInClassesThat().resideInAPackage("..presentation..controller..")
                .and().areDeclaredInClassesThat().haveSimpleNameEndingWith("Controller")
                .should().haveName("handle")
                .check(classesToCheck);
    }

    private static ArchCondition<JavaClass> haveExactlyOnePublicMethodNamed(String expectedName) {
        return new ArchCondition<>("publicメソッドを1つだけ持ち、名前は" + expectedName) {
            @Override
            public void check(JavaClass javaClass, ConditionEvents events) {
                List<JavaMethod> publicMethods = javaClass.getMethods().stream()
                        .filter(method -> method.getModifiers().contains(JavaModifier.PUBLIC))
                        .toList();
                boolean valid = publicMethods.size() == 1 && expectedName.equals(publicMethods.getFirst().getName());
                if (!valid) {
                    String methodNames = publicMethods.stream()
                            .map(JavaMethod::getName)
                            .sorted()
                            .toList()
                            .toString();
                    events.add(SimpleConditionEvent.violated(
                            javaClass,
                            javaClass.getName() + " のpublicメソッド: " + methodNames));
                }
            }
        };
    }
}
