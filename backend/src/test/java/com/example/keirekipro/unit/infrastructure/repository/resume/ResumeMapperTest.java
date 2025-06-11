package com.example.keirekipro.unit.infrastructure.repository.resume;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.util.Collections;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.config.PostgresTestContainerConfig;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto.CareerDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto.CertificationDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto.PortfolioDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto.ProjectDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto.SelfPromotionDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto.SocialLinkDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeMapper;
import com.example.keirekipro.infrastructure.repository.user.UserDto;
import com.example.keirekipro.infrastructure.repository.user.UserMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mybatis.spring.boot.test.autoconfigure.MybatisTest;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.TestPropertySource;

import lombok.RequiredArgsConstructor;

@MybatisTest
@ActiveProfiles("test")
@TestPropertySource(properties = "spring.flyway.target=1")
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Import(PostgresTestContainerConfig.class)
class ResumeMapperTest {

    private final ResumeMapper resumeMapper;
    private final UserMapper userMapper;

    private static final UUID USER_ID = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static final UUID RESUME_ID_1 = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static final UUID RESUME_ID_2 = UUID.fromString("cccccccc-cccc-cccc-cccc-cccccccccccc");
    private static final UUID RANDOM_RESUME = UUID.fromString("dddddddd-dddd-dddd-dddd-dddddddddddd");

    private static final String NAME_1 = "Resume One";
    private static final String NAME_2 = "Resume Two";
    private static final LocalDate DATE_1 = LocalDate.of(2025, 1, 1);
    private static final LocalDate DATE_2 = LocalDate.of(2025, 2, 2);
    private static final String LAST_NAME_1 = "LastOne";
    private static final String FIRST_NAME_1 = "FirstOne";
    private static final String LAST_NAME_2 = "LastTwo";
    private static final String FIRST_NAME_2 = "FirstTwo";
    private static final LocalDateTime CREATED = LocalDateTime.of(2025, 1, 1, 0, 0);
    private static final LocalDateTime UPDATED = LocalDateTime.of(2025, 1, 2, 0, 0);

    @Test
    @DisplayName("selectAllByUserId_該当ユーザーに職務経歴書が存在しない場合、空リストが返る")
    void test1() {
        // ユーザー作成
        userMapper.upsertUser(createUserDto());

        List<ResumeDto> list = resumeMapper.selectAllByUserId(USER_ID);
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("selectAllByUserId_複数の職務経歴書が存在する場合、各DTOの全フィールドが正しくマッピングされる")
    void test2() {
        // ユーザー作成
        userMapper.upsertUser(createUserDto());

        ResumeDto dto1 = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(dto1);

        ResumeDto dto2 = createResumeDto(
                RESUME_ID_2,
                USER_ID,
                NAME_2,
                DATE_2,
                LAST_NAME_2,
                FIRST_NAME_2,
                CREATED,
                UPDATED);
        resumeMapper.upsert(dto2);

        List<ResumeDto> list = resumeMapper.selectAllByUserId(USER_ID);
        assertThat(list).hasSize(2);

        ResumeDto first = list.get(0);
        assertThat(first.getId()).isEqualTo(RESUME_ID_1);
        assertThat(first.getUserId()).isEqualTo(USER_ID);
        assertThat(first.getName()).isEqualTo(NAME_1);
        assertThat(first.getDate()).isEqualTo(DATE_1);
        assertThat(first.getLastName()).isEqualTo(LAST_NAME_1);
        assertThat(first.getFirstName()).isEqualTo(FIRST_NAME_1);
        assertThat(first.getCreatedAt()).isEqualTo(CREATED);
        assertThat(first.getUpdatedAt()).isEqualTo(UPDATED);

        ResumeDto second = list.get(1);
        assertThat(second.getId()).isEqualTo(RESUME_ID_2);
        assertThat(second.getUserId()).isEqualTo(USER_ID);
        assertThat(second.getName()).isEqualTo(NAME_2);
        assertThat(second.getDate()).isEqualTo(DATE_2);
        assertThat(second.getLastName()).isEqualTo(LAST_NAME_2);
        assertThat(second.getFirstName()).isEqualTo(FIRST_NAME_2);
        assertThat(second.getCreatedAt()).isEqualTo(CREATED);
        assertThat(second.getUpdatedAt()).isEqualTo(UPDATED);
    }

    @Test
    @DisplayName("selectByResumeId_職務経歴書が存在する場合、DTOのすべてのフィールドが正しく取得できる")
    void test3() {
        // ユーザー作成
        userMapper.upsertUser(createUserDto());

        ResumeDto dto = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(dto);

        Optional<ResumeDto> opt = resumeMapper.selectByResumeId(RESUME_ID_1);
        assertThat(opt).isPresent();
        ResumeDto loaded = opt.get();
        assertThat(loaded.getId()).isEqualTo(RESUME_ID_1);
        assertThat(loaded.getUserId()).isEqualTo(USER_ID);
        assertThat(loaded.getName()).isEqualTo(NAME_1);
        assertThat(loaded.getDate()).isEqualTo(DATE_1);
        assertThat(loaded.getLastName()).isEqualTo(LAST_NAME_1);
        assertThat(loaded.getFirstName()).isEqualTo(FIRST_NAME_1);
        assertThat(loaded.getCreatedAt()).isEqualTo(CREATED);
        assertThat(loaded.getUpdatedAt()).isEqualTo(UPDATED);
    }

    @Test
    @DisplayName("selectByResumeId_職務経歴書が存在しない場合、空のOptionalが返る")
    void test4() {
        // ユーザー作成
        userMapper.upsertUser(createUserDto());

        Optional<ResumeDto> opt = resumeMapper.selectByResumeId(RANDOM_RESUME);
        assertThat(opt).isEmpty();
    }

    @Test
    @DisplayName("upsert_職務経歴書を新規作成できる")
    void test5() {
        // ユーザー作成
        userMapper.upsertUser(createUserDto());

        // 職務経歴書を新規作成
        ResumeDto dto = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                "New Resume",
                LocalDate.of(2025, 3, 3),
                "NewLast",
                "NewFirst",
                CREATED,
                UPDATED);
        resumeMapper.upsert(dto);

        // 検証
        Optional<ResumeDto> opt = resumeMapper.selectByResumeId(RESUME_ID_1);
        assertThat(opt).isPresent();
        ResumeDto loaded = opt.get();
        assertThat(loaded.getId()).isEqualTo(RESUME_ID_1);
        assertThat(loaded.getUserId()).isEqualTo(USER_ID);
        assertThat(loaded.getName()).isEqualTo("New Resume");
        assertThat(loaded.getDate()).isEqualTo(LocalDate.of(2025, 3, 3));
        assertThat(loaded.getLastName()).isEqualTo("NewLast");
        assertThat(loaded.getFirstName()).isEqualTo("NewFirst");
        assertThat(loaded.getCreatedAt()).isEqualTo(CREATED);
        assertThat(loaded.getUpdatedAt()).isEqualTo(UPDATED);
    }

    @Test
    @DisplayName("upsert_既存の職務経歴書を更新すると、職務経歴書情報が更新される")
    void test6() {
        // ユーザー作成
        userMapper.upsertUser(createUserDto());

        // まず初期データを挿入
        ResumeDto original = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                "Original Resume",
                LocalDate.of(2025, 4, 4),
                "OrigLast",
                "OrigFirst",
                CREATED,
                UPDATED);
        resumeMapper.upsert(original);

        // 更新用DTO
        LocalDateTime newUpdated = UPDATED.plusDays(1);
        ResumeDto updated = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                "Updated Resume",
                LocalDate.of(2025, 5, 5),
                "UpdLast",
                "UpdFirst",
                CREATED,
                newUpdated);
        resumeMapper.upsert(updated);

        // 検証
        Optional<ResumeDto> opt2 = resumeMapper.selectByResumeId(RESUME_ID_1);
        assertThat(opt2).isPresent();
        ResumeDto loaded2 = opt2.get();
        // 作成日時は変わらず
        assertThat(loaded2.getCreatedAt()).isEqualTo(CREATED);
        // 更新日時やその他フィールドが反映される
        assertThat(loaded2.getUpdatedAt()).isEqualTo(newUpdated);
        assertThat(loaded2.getName()).isEqualTo("Updated Resume");
        assertThat(loaded2.getDate()).isEqualTo(LocalDate.of(2025, 5, 5));
        assertThat(loaded2.getLastName()).isEqualTo("UpdLast");
        assertThat(loaded2.getFirstName()).isEqualTo("UpdFirst");
    }

    @Test
    @DisplayName("delete_特定の職務経歴書を削除後、取得結果が空のOptionalを返す")
    void test7() {
        // ユーザー作成
        userMapper.upsertUser(createUserDto());

        // まず職務経歴書を作成して保存
        ResumeDto dto = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                "To Be Deleted",
                LocalDate.of(2025, 6, 6),
                "DelLast",
                "DelFirst",
                CREATED,
                UPDATED);
        resumeMapper.upsert(dto);

        // 削除実行
        resumeMapper.delete(RESUME_ID_1);

        // 削除後は取得できないこと
        Optional<ResumeDto> opt = resumeMapper.selectByResumeId(RESUME_ID_1);
        assertThat(opt).isEmpty();
    }

    @Test
    @DisplayName("selectCareersByResumeId_職歴が存在しない場合、空リストが返る")
    void test8() {
        // ユーザー作成
        userMapper.upsertUser(createUserDto());
        // 親レコードのみ登録
        ResumeDto resume = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(resume);

        List<CareerDto> list = resumeMapper.selectCareersByResumeId(RESUME_ID_1);
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("insertCareer_職歴を新規作成できる")
    void test9() {
        userMapper.upsertUser(createUserDto());
        // 親レコード登録
        ResumeDto resume = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(resume);

        UUID careerId = UUID.fromString("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee");
        CareerDto career = createCareerDto(
                careerId,
                RESUME_ID_1,
                "CompanyX",
                YearMonth.of(2024, 1),
                YearMonth.of(2024, 12),
                true);
        resumeMapper.insertCareer(career);

        List<CareerDto> list = resumeMapper.selectCareersByResumeId(RESUME_ID_1);
        assertThat(list).hasSize(1);
        CareerDto loaded = list.get(0);
        assertThat(loaded.getId()).isEqualTo(careerId);
        assertThat(loaded.getCompanyName()).isEqualTo("CompanyX");
        assertThat(loaded.getStartDate()).isEqualTo(YearMonth.of(2024, 1));
        assertThat(loaded.getEndDate()).isEqualTo(YearMonth.of(2024, 12));
        assertThat(loaded.getIsActive()).isTrue();
    }

    @Test
    @DisplayName("updateCareer_既存の職歴を更新すると、職歴情報が更新される")
    void test10() {
        userMapper.upsertUser(createUserDto());
        // 親レコード登録
        ResumeDto resume = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(resume);

        UUID careerId = UUID.fromString("ffffffff-ffff-ffff-ffff-ffffffffffff");
        // 初期挿入
        CareerDto original = createCareerDto(
                careerId,
                RESUME_ID_1,
                "OldCompany",
                YearMonth.of(2023, 2),
                YearMonth.of(2023, 8),
                false);
        resumeMapper.insertCareer(original);

        // 更新
        CareerDto updated = createCareerDto(
                careerId,
                RESUME_ID_1,
                "NewCompany",
                YearMonth.of(2023, 3),
                YearMonth.of(2023, 9),
                true);
        resumeMapper.updateCareer(updated);

        List<CareerDto> list = resumeMapper.selectCareersByResumeId(RESUME_ID_1);
        assertThat(list).hasSize(1);
        CareerDto loaded = list.get(0);
        assertThat(loaded.getCompanyName()).isEqualTo("NewCompany");
        assertThat(loaded.getStartDate()).isEqualTo(YearMonth.of(2023, 3));
        assertThat(loaded.getEndDate()).isEqualTo(YearMonth.of(2023, 9));
        assertThat(loaded.getIsActive()).isTrue();
    }

    @Test
    @DisplayName("deleteCareer_特定の職務経歴書を削除後、取得結果が空のOptionalを返す")
    void test11() {
        userMapper.upsertUser(createUserDto());
        // 親レコード登録
        ResumeDto resume = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(resume);

        UUID careerId = UUID.fromString("aaaaaaaa-0000-0000-0000-aaaaaaaa0000");
        CareerDto career = createCareerDto(
                careerId,
                RESUME_ID_1,
                "DelCompany",
                YearMonth.of(2022, 5),
                YearMonth.of(2022, 10),
                false);
        resumeMapper.insertCareer(career);

        // 削除実行
        resumeMapper.deleteCareer(careerId);

        List<CareerDto> list = resumeMapper.selectCareersByResumeId(RESUME_ID_1);
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("deleteCareersByResumeId_すべての職歴を削除後、取得結果が空リストを返す")
    void test12() {
        userMapper.upsertUser(createUserDto());
        // 親レコード登録
        ResumeDto resume = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(resume);

        // 複数挿入
        resumeMapper.insertCareer(createCareerDto(
                UUID.randomUUID(),
                RESUME_ID_1,
                "C1",
                YearMonth.of(2021, 1),
                YearMonth.of(2021, 6),
                true));
        resumeMapper.insertCareer(createCareerDto(
                UUID.randomUUID(),
                RESUME_ID_1,
                "C2",
                YearMonth.of(2021, 7),
                YearMonth.of(2021, 12),
                false));

        // 全削除
        resumeMapper.deleteCareersByResumeId(RESUME_ID_1);

        List<CareerDto> list = resumeMapper.selectCareersByResumeId(RESUME_ID_1);
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("selectProjectsByResumeId_プロジェクトが存在しない場合、空リストが返る")
    void test13() {
        // ユーザー作成
        userMapper.upsertUser(createUserDto());
        // 親レコードのみ登録
        ResumeDto resume = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(resume);

        List<ProjectDto> list = resumeMapper.selectProjectsByResumeId(RESUME_ID_1);
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("insertProject_プロジェクトを新規作成できる")
    void test14() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(resume);

        UUID projectId = UUID.fromString("11111111-1111-1111-1111-111111111111");
        ProjectDto project = createProjectDto(
                projectId,
                RESUME_ID_1,
                "CompanyProj",
                YearMonth.of(2023, 1),
                YearMonth.of(2023, 12),
                true,
                "ProjName",
                "Overview",
                "Team",
                "Role",
                "Achievement",
                false, false, false, false, false, false, false,
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList());
        resumeMapper.insertProject(project);

        List<ProjectDto> list = resumeMapper.selectProjectsByResumeId(RESUME_ID_1);
        assertThat(list).hasSize(1);
        ProjectDto loaded = list.get(0);
        assertThat(loaded.getId()).isEqualTo(projectId);
        assertThat(loaded.getCompanyName()).isEqualTo("CompanyProj");
        assertThat(loaded.getStartDate()).isEqualTo(YearMonth.of(2023, 1));
        assertThat(loaded.getEndDate()).isEqualTo(YearMonth.of(2023, 12));
        assertThat(loaded.getIsActive()).isTrue();
        assertThat(loaded.getName()).isEqualTo("ProjName");
        assertThat(loaded.getOverview()).isEqualTo("Overview");
        assertThat(loaded.getTeamComp()).isEqualTo("Team");
        assertThat(loaded.getRole()).isEqualTo("Role");
        assertThat(loaded.getAchievement()).isEqualTo("Achievement");
    }

    @Test
    @DisplayName("updateProject_既存のプロジェクトを更新すると、プロジェクト情報が更新される")
    void test15() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(resume);

        UUID projectId = UUID.fromString("22222222-2222-2222-2222-222222222222");
        // 初期挿入
        ProjectDto original = createProjectDto(
                projectId,
                RESUME_ID_1,
                "OldCompany",
                YearMonth.of(2022, 2),
                YearMonth.of(2022, 8),
                false,
                "OldProj",
                "OldOverview",
                "OldTeam",
                "OldRole",
                "OldAch",
                false, false, false, false, false, false, false,
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList());
        resumeMapper.insertProject(original);

        // 更新
        ProjectDto updated = createProjectDto(
                projectId,
                RESUME_ID_1,
                "NewCompany",
                YearMonth.of(2022, 3),
                YearMonth.of(2022, 9),
                true,
                "NewProj",
                "NewOverview",
                "NewTeam",
                "NewRole",
                "NewAch",
                true, true, true, true, true, true, true,
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList());
        resumeMapper.updateProject(updated);

        List<ProjectDto> list = resumeMapper.selectProjectsByResumeId(RESUME_ID_1);
        assertThat(list).hasSize(1);
        ProjectDto loaded = list.get(0);
        assertThat(loaded.getCompanyName()).isEqualTo("NewCompany");
        assertThat(loaded.getStartDate()).isEqualTo(YearMonth.of(2022, 3));
        assertThat(loaded.getEndDate()).isEqualTo(YearMonth.of(2022, 9));
        assertThat(loaded.getIsActive()).isTrue();
        assertThat(loaded.getName()).isEqualTo("NewProj");
        assertThat(loaded.getOverview()).isEqualTo("NewOverview");
        assertThat(loaded.getTeamComp()).isEqualTo("NewTeam");
        assertThat(loaded.getRole()).isEqualTo("NewRole");
        assertThat(loaded.getAchievement()).isEqualTo("NewAch");
    }

    @Test
    @DisplayName("deleteProject_特定のproject_idを削除後、selectProjectsByResumeIdに含まれなくなる")
    void test16() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(resume);

        UUID projectId = UUID.fromString("33333333-3333-3333-3333-333333333333");
        ProjectDto project = createProjectDto(
                projectId,
                RESUME_ID_1,
                "DelCompany",
                YearMonth.of(2021, 5),
                YearMonth.of(2021, 10),
                false,
                "DelProj",
                "DelOverview",
                "DelTeam",
                "DelRole",
                "DelAch",
                false, false, false, false, false, false, false,
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList());
        resumeMapper.insertProject(project);

        resumeMapper.deleteProject(projectId);

        List<ProjectDto> list = resumeMapper.selectProjectsByResumeId(RESUME_ID_1);
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("deleteProjectsByResumeId_すべてのプロジェクトを削除後、selectProjectsByResumeIdが空リストを返す")
    void test17() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(resume);

        // 複数挿入
        resumeMapper.insertProject(createProjectDto(
                UUID.randomUUID(), RESUME_ID_1,
                "P1", YearMonth.of(2020, 1), YearMonth.of(2020, 6), true,
                "Proj1", "Ov1", "Team1", "Role1", "Ach1",
                false, false, false, false, false, false, false,
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList()));
        resumeMapper.insertProject(createProjectDto(
                UUID.randomUUID(), RESUME_ID_1,
                "P2", YearMonth.of(2020, 7), YearMonth.of(2020, 12), false,
                "Proj2", "Ov2", "Team2", "Role2", "Ach2",
                false, false, false, false, false, false, false,
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList(),
                Collections.<String>emptyList(), Collections.<String>emptyList()));

        resumeMapper.deleteProjectsByResumeId(RESUME_ID_1);

        List<ProjectDto> list = resumeMapper.selectProjectsByResumeId(RESUME_ID_1);
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("selectCertificationsByResumeId_該当resume_idで資格が存在しない場合、空リストが返る")
    void test18() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(resume);

        List<CertificationDto> list = resumeMapper.selectCertificationsByResumeId(RESUME_ID_1);
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("insertCertification_資格を挿入後、selectCertificationsByResumeIdで取得できる")
    void test19() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(resume);

        UUID certId = UUID.fromString("55555555-5555-5555-5555-555555555555");
        CertificationDto cert = createCertificationDto(
                certId,
                RESUME_ID_1,
                "CertName",
                YearMonth.of(2021, 1));
        resumeMapper.insertCertification(cert);

        List<CertificationDto> list = resumeMapper.selectCertificationsByResumeId(RESUME_ID_1);
        assertThat(list).hasSize(1);
        CertificationDto loaded = list.get(0);
        assertThat(loaded.getId()).isEqualTo(certId);
        assertThat(loaded.getName()).isEqualTo("CertName");
        assertThat(loaded.getDate()).isEqualTo(YearMonth.of(2021, 1));
    }

    @Test
    @DisplayName("updateCertification_既存の資格を更新すると、各フィールドが反映される")
    void test20() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(resume);

        UUID certId = UUID.fromString("66666666-6666-6666-6666-666666666666");
        CertificationDto original = createCertificationDto(
                certId,
                RESUME_ID_1,
                "OldCert",
                YearMonth.of(2020, 1));
        resumeMapper.insertCertification(original);

        CertificationDto updated = createCertificationDto(
                certId,
                RESUME_ID_1,
                "NewCert",
                YearMonth.of(2020, 2));
        resumeMapper.updateCertification(updated);

        List<CertificationDto> list = resumeMapper.selectCertificationsByResumeId(RESUME_ID_1);
        assertThat(list).hasSize(1);
        CertificationDto loaded = list.get(0);
        assertThat(loaded.getName()).isEqualTo("NewCert");
        assertThat(loaded.getDate()).isEqualTo(YearMonth.of(2020, 2));
    }

    @Test
    @DisplayName("deleteCertification_特定のcertification_idを削除後、selectCertificationsByResumeIdに含まれなくなる")
    void test21() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(resume);

        UUID certId = UUID.fromString("77777777-7777-7777-7777-777777777777");
        CertificationDto cert = createCertificationDto(
                certId,
                RESUME_ID_1,
                "ToDelete",
                YearMonth.of(2019, 1));
        resumeMapper.insertCertification(cert);

        resumeMapper.deleteCertification(certId);

        List<CertificationDto> list = resumeMapper.selectCertificationsByResumeId(RESUME_ID_1);
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("deleteCertificationsByResumeId_すべての資格を削除後、selectCertificationsByResumeIdが空リストを返す")
    void test22() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(resume);

        resumeMapper.insertCertification(createCertificationDto(
                UUID.randomUUID(), RESUME_ID_1, "C1", YearMonth.of(2018, 1)));
        resumeMapper.insertCertification(createCertificationDto(
                UUID.randomUUID(), RESUME_ID_1, "C2", YearMonth.of(2018, 2)));

        resumeMapper.deleteCertificationsByResumeId(RESUME_ID_1);

        List<CertificationDto> list = resumeMapper.selectCertificationsByResumeId(RESUME_ID_1);
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("selectPortfoliosByResumeId_該当resume_idでポートフォリオが存在しない場合、空リストが返る")
    void test23() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(resume);

        List<PortfolioDto> list = resumeMapper.selectPortfoliosByResumeId(RESUME_ID_1);
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("insertPortfolio_ポートフォリオを挿入後、selectPortfoliosByResumeIdで取得できる")
    void test24() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(resume);

        UUID portId = UUID.fromString("88888888-8888-8888-8888-888888888888");
        PortfolioDto port = createPortfolioDto(
                portId,
                RESUME_ID_1,
                "PortName",
                "PortOverview",
                "TechStack",
                "http://link");
        resumeMapper.insertPortfolio(port);

        List<PortfolioDto> list = resumeMapper.selectPortfoliosByResumeId(RESUME_ID_1);
        assertThat(list).hasSize(1);
        PortfolioDto loaded = list.get(0);
        assertThat(loaded.getId()).isEqualTo(portId);
        assertThat(loaded.getName()).isEqualTo("PortName");
        assertThat(loaded.getOverview()).isEqualTo("PortOverview");
        assertThat(loaded.getTechStack()).isEqualTo("TechStack");
        assertThat(loaded.getLink()).isEqualTo("http://link");
    }

    @Test
    @DisplayName("updatePortfolio_既存のポートフォリオを更新すると、各フィールドが反映される")
    void test25() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(resume);

        UUID portId = UUID.fromString("99999999-9999-9999-9999-999999999999");
        PortfolioDto original = createPortfolioDto(
                portId,
                RESUME_ID_1,
                "OldName",
                "OldOv",
                "OldTech",
                "http://old");
        resumeMapper.insertPortfolio(original);

        PortfolioDto updated = createPortfolioDto(
                portId,
                RESUME_ID_1,
                "NewName",
                "NewOv",
                "NewTech",
                "http://new");
        resumeMapper.updatePortfolio(updated);

        List<PortfolioDto> list = resumeMapper.selectPortfoliosByResumeId(RESUME_ID_1);
        assertThat(list).hasSize(1);
        PortfolioDto loaded = list.get(0);
        assertThat(loaded.getName()).isEqualTo("NewName");
        assertThat(loaded.getOverview()).isEqualTo("NewOv");
        assertThat(loaded.getTechStack()).isEqualTo("NewTech");
        assertThat(loaded.getLink()).isEqualTo("http://new");
    }

    @Test
    @DisplayName("deletePortfolio_特定のportfolio_idを削除後、selectPortfoliosByResumeIdに含まれなくなる")
    void test26() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1,
                USER_ID,
                NAME_1,
                DATE_1,
                LAST_NAME_1,
                FIRST_NAME_1,
                CREATED,
                UPDATED);
        resumeMapper.upsert(resume);

        UUID portId = UUID.fromString("aaaaaaaa-1111-2222-3333-aaaaaaaa1111");
        PortfolioDto port = createPortfolioDto(
                portId,
                RESUME_ID_1,
                "DelName",
                "DelOv",
                "DelTech",
                "http://del");
        resumeMapper.insertPortfolio(port);

        resumeMapper.deletePortfolio(portId);

        List<PortfolioDto> list = resumeMapper.selectPortfoliosByResumeId(RESUME_ID_1);
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("deletePortfoliosByResumeId_すべてのポートフォリオを削除後、selectPortfoliosByResumeIdが空リストを返す")
    void test27() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1, USER_ID, NAME_1, DATE_1, LAST_NAME_1, FIRST_NAME_1, CREATED, UPDATED);
        resumeMapper.upsert(resume);

        resumeMapper.insertPortfolio(createPortfolioDto(
                UUID.randomUUID(), RESUME_ID_1, "P1", "Ov1", "T1", "L1"));
        resumeMapper.insertPortfolio(createPortfolioDto(
                UUID.randomUUID(), RESUME_ID_1, "P2", "Ov2", "T2", "L2"));

        resumeMapper.deletePortfoliosByResumeId(RESUME_ID_1);

        List<PortfolioDto> list = resumeMapper.selectPortfoliosByResumeId(RESUME_ID_1);
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("selectSocialLinksByResumeId_該当resume_idでソーシャルリンクが存在しない場合、空リストが返る")
    void test28() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1, USER_ID, NAME_1, DATE_1, LAST_NAME_1, FIRST_NAME_1, CREATED, UPDATED);
        resumeMapper.upsert(resume);

        List<SocialLinkDto> list = resumeMapper.selectSocialLinksByResumeId(RESUME_ID_1);
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("insertSocialLink_ソーシャルリンクを挿入後、selectSocialLinksByResumeIdで各フィールドが取得できる")
    void test29() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1, USER_ID, NAME_1, DATE_1, LAST_NAME_1, FIRST_NAME_1, CREATED, UPDATED);
        resumeMapper.upsert(resume);

        UUID linkId = UUID.fromString("aaaaaaaa-1234-1234-1234-aaaaaaaa1234");
        SocialLinkDto link = createSocialLinkDto(
                linkId,
                RESUME_ID_1,
                "LinkedIn",
                "https://linkedin.com/in/test");
        resumeMapper.insertSocialLink(link);

        List<SocialLinkDto> list = resumeMapper.selectSocialLinksByResumeId(RESUME_ID_1);
        assertThat(list).hasSize(1);
        SocialLinkDto loaded = list.get(0);
        assertThat(loaded.getId()).isEqualTo(linkId);
        assertThat(loaded.getName()).isEqualTo("LinkedIn");
        assertThat(loaded.getLink()).isEqualTo("https://linkedin.com/in/test");
    }

    @Test
    @DisplayName("updateSocialLink_既存のソーシャルリンクを更新すると、各フィールドが反映される")
    void test30() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1, USER_ID, NAME_1, DATE_1, LAST_NAME_1, FIRST_NAME_1, CREATED, UPDATED);
        resumeMapper.upsert(resume);

        UUID linkId = UUID.fromString("bbbbbbbb-2345-2345-2345-bbbbbbbb2345");
        SocialLinkDto original = createSocialLinkDto(
                linkId,
                RESUME_ID_1,
                "GitHub",
                "https://github.com/test");
        resumeMapper.insertSocialLink(original);

        SocialLinkDto updated = createSocialLinkDto(
                linkId,
                RESUME_ID_1,
                "GitHubUpdated",
                "https://github.com/test-updated");
        resumeMapper.updateSocialLink(updated);

        List<SocialLinkDto> list = resumeMapper.selectSocialLinksByResumeId(RESUME_ID_1);
        assertThat(list).hasSize(1);
        SocialLinkDto loaded = list.get(0);
        assertThat(loaded.getName()).isEqualTo("GitHubUpdated");
        assertThat(loaded.getLink()).isEqualTo("https://github.com/test-updated");
    }

    @Test
    @DisplayName("deleteSocialLink_特定のsocialLink_idを削除後、selectSocialLinksByResumeIdに含まれなくなる")
    void test31() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1, USER_ID, NAME_1, DATE_1, LAST_NAME_1, FIRST_NAME_1, CREATED, UPDATED);
        resumeMapper.upsert(resume);

        UUID linkId = UUID.fromString("cccccccc-3456-3456-3456-cccccccc3456");
        SocialLinkDto link = createSocialLinkDto(
                linkId,
                RESUME_ID_1,
                "Twitter",
                "https://twitter.com/test");
        resumeMapper.insertSocialLink(link);

        resumeMapper.deleteSocialLink(linkId);

        List<SocialLinkDto> list = resumeMapper.selectSocialLinksByResumeId(RESUME_ID_1);
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("deleteSocialLinksByResumeId_すべてのソーシャルリンクを削除後、selectSocialLinksByResumeIdが空リストを返す")
    void test32() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1, USER_ID, NAME_1, DATE_1, LAST_NAME_1, FIRST_NAME_1, CREATED, UPDATED);
        resumeMapper.upsert(resume);

        resumeMapper.insertSocialLink(createSocialLinkDto(
                UUID.randomUUID(), RESUME_ID_1, "Link1", "http://l1"));
        resumeMapper.insertSocialLink(createSocialLinkDto(
                UUID.randomUUID(), RESUME_ID_1, "Link2", "http://l2"));

        resumeMapper.deleteSocialLinksByResumeId(RESUME_ID_1);

        List<SocialLinkDto> list = resumeMapper.selectSocialLinksByResumeId(RESUME_ID_1);
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("selectSelfPromotionsByResumeId_該当resume_idで自己PRが存在しない場合、空リストが返る")
    void test33() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1, USER_ID, NAME_1, DATE_1, LAST_NAME_1, FIRST_NAME_1, CREATED, UPDATED);
        resumeMapper.upsert(resume);

        List<SelfPromotionDto> list = resumeMapper.selectSelfPromotionsByResumeId(RESUME_ID_1);
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("insertSelfPromotion_自己PRを挿入後、selectSelfPromotionsByResumeIdで各フィールドが取得できる")
    void test34() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1, USER_ID, NAME_1, DATE_1, LAST_NAME_1, FIRST_NAME_1, CREATED, UPDATED);
        resumeMapper.upsert(resume);

        UUID promoId = UUID.fromString("dddddddd-4567-4567-4567-dddddddd4567");
        SelfPromotionDto promo = createSelfPromotionDto(
                promoId,
                RESUME_ID_1,
                "Title1",
                "Content1");
        resumeMapper.insertSelfPromotion(promo);

        List<SelfPromotionDto> list = resumeMapper.selectSelfPromotionsByResumeId(RESUME_ID_1);
        assertThat(list).hasSize(1);
        SelfPromotionDto loaded = list.get(0);
        assertThat(loaded.getId()).isEqualTo(promoId);
        assertThat(loaded.getTitle()).isEqualTo("Title1");
        assertThat(loaded.getContent()).isEqualTo("Content1");
    }

    @Test
    @DisplayName("updateSelfPromotion_既存の自己PRを更新すると、各フィールド)が反映される")
    void test35() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1, USER_ID, NAME_1, DATE_1, LAST_NAME_1, FIRST_NAME_1, CREATED, UPDATED);
        resumeMapper.upsert(resume);

        UUID promoId = UUID.fromString("eeeeeeee-5678-5678-5678-eeeeeeee5678");
        SelfPromotionDto original = createSelfPromotionDto(
                promoId,
                RESUME_ID_1,
                "OldTitle",
                "OldContent");
        resumeMapper.insertSelfPromotion(original);

        SelfPromotionDto updated = createSelfPromotionDto(
                promoId,
                RESUME_ID_1,
                "NewTitle",
                "NewContent");
        resumeMapper.updateSelfPromotion(updated);

        List<SelfPromotionDto> list = resumeMapper.selectSelfPromotionsByResumeId(RESUME_ID_1);
        assertThat(list).hasSize(1);
        SelfPromotionDto loaded = list.get(0);
        assertThat(loaded.getTitle()).isEqualTo("NewTitle");
        assertThat(loaded.getContent()).isEqualTo("NewContent");
    }

    @Test
    @DisplayName("deleteSelfPromotion_特定のselfPromotion_idを削除後、selectSelfPromotionsByResumeIdに含まれなくなる")
    void test36() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1, USER_ID, NAME_1, DATE_1, LAST_NAME_1, FIRST_NAME_1, CREATED, UPDATED);
        resumeMapper.upsert(resume);

        UUID promoId = UUID.fromString("ffffffff-6789-6789-6789-ffffffff6789");
        SelfPromotionDto promo = createSelfPromotionDto(
                promoId,
                RESUME_ID_1,
                "ToDelete",
                "DelContent");
        resumeMapper.insertSelfPromotion(promo);

        resumeMapper.deleteSelfPromotion(promoId);

        List<SelfPromotionDto> list = resumeMapper.selectSelfPromotionsByResumeId(RESUME_ID_1);
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("deleteSelfPromotionsByResumeId_すべての自己PRを削除後、selectSelfPromotionsByResumeIdが空リストを返す")
    void test37() {
        userMapper.upsertUser(createUserDto());
        ResumeDto resume = createResumeDto(
                RESUME_ID_1, USER_ID, NAME_1, DATE_1, LAST_NAME_1, FIRST_NAME_1, CREATED, UPDATED);
        resumeMapper.upsert(resume);

        resumeMapper.insertSelfPromotion(createSelfPromotionDto(
                UUID.randomUUID(), RESUME_ID_1, "SP1", "C1"));
        resumeMapper.insertSelfPromotion(createSelfPromotionDto(
                UUID.randomUUID(), RESUME_ID_1, "SP2", "C2"));

        resumeMapper.deleteSelfPromotionsByResumeId(RESUME_ID_1);

        List<SelfPromotionDto> list = resumeMapper.selectSelfPromotionsByResumeId(RESUME_ID_1);
        assertThat(list).isEmpty();
    }

    private ResumeDto createResumeDto(
            UUID id,
            UUID userId,
            String name,
            LocalDate date,
            String lastName,
            String firstName,
            LocalDateTime createdAt,
            LocalDateTime updatedAt) {
        ResumeDto dto = new ResumeDto();
        dto.setId(id);
        dto.setUserId(userId);
        dto.setName(name);
        dto.setDate(date);
        dto.setLastName(lastName);
        dto.setFirstName(firstName);
        dto.setCreatedAt(createdAt);
        dto.setUpdatedAt(updatedAt);

        // 子リストは空リストで初期化
        dto.setCareers(Collections.emptyList());
        dto.setProjects(Collections.emptyList());
        dto.setCertifications(Collections.emptyList());
        dto.setPortfolios(Collections.emptyList());
        dto.setSocialLinks(Collections.emptyList());
        dto.setSelfPromotions(Collections.emptyList());
        return dto;
    }

    private CareerDto createCareerDto(
            UUID id,
            UUID resumeId,
            String companyName,
            YearMonth startDate,
            YearMonth endDate,
            Boolean isActive) {
        CareerDto d = new CareerDto();
        d.setId(id);
        d.setResumeId(resumeId);
        d.setCompanyName(companyName);
        d.setStartDate(startDate);
        d.setEndDate(endDate);
        d.setIsActive(isActive);
        return d;
    }

    private ProjectDto createProjectDto(
            UUID id,
            UUID resumeId,
            String companyName,
            YearMonth startDate,
            YearMonth endDate,
            Boolean isActive,
            String name,
            String overview,
            String teamComp,
            String role,
            String achievement,
            Boolean requirements,
            Boolean basicDesign,
            Boolean detailedDesign,
            Boolean implementation,
            Boolean integrationTest,
            Boolean systemTest,
            Boolean maintenance,
            List<String> languages,
            List<String> frameworks,
            List<String> libraries,
            List<String> testingTools,
            List<String> ormTools,
            List<String> packageManagers,
            List<String> clouds,
            List<String> containers,
            List<String> databases,
            List<String> webServers,
            List<String> ciCdTools,
            List<String> iacTools,
            List<String> monitoringTools,
            List<String> loggingTools,
            List<String> sourceControls,
            List<String> projectManagements,
            List<String> communicationTools,
            List<String> documentationTools,
            List<String> apiDevelopmentTools,
            List<String> designTools) {
        ProjectDto d = new ProjectDto();
        d.setId(id);
        d.setResumeId(resumeId);
        d.setCompanyName(companyName);
        d.setStartDate(startDate);
        d.setEndDate(endDate);
        d.setIsActive(isActive);
        d.setName(name);
        d.setOverview(overview);
        d.setTeamComp(teamComp);
        d.setRole(role);
        d.setAchievement(achievement);
        d.setRequirements(requirements);
        d.setBasicDesign(basicDesign);
        d.setDetailedDesign(detailedDesign);
        d.setImplementation(implementation);
        d.setIntegrationTest(integrationTest);
        d.setSystemTest(systemTest);
        d.setMaintenance(maintenance);
        d.setLanguages(languages);
        d.setFrameworks(frameworks);
        d.setLibraries(libraries);
        d.setTestingTools(testingTools);
        d.setOrmTools(ormTools);
        d.setPackageManagers(packageManagers);
        d.setClouds(clouds);
        d.setContainers(containers);
        d.setDatabases(databases);
        d.setWebServers(webServers);
        d.setCiCdTools(ciCdTools);
        d.setIacTools(iacTools);
        d.setMonitoringTools(monitoringTools);
        d.setLoggingTools(loggingTools);
        d.setSourceControls(sourceControls);
        d.setProjectManagements(projectManagements);
        d.setCommunicationTools(communicationTools);
        d.setDocumentationTools(documentationTools);
        d.setApiDevelopmentTools(apiDevelopmentTools);
        d.setDesignTools(designTools);
        return d;
    }

    private CertificationDto createCertificationDto(
            UUID id,
            UUID resumeId,
            String name,
            YearMonth date) {
        CertificationDto d = new CertificationDto();
        d.setId(id);
        d.setResumeId(resumeId);
        d.setName(name);
        d.setDate(date);
        return d;
    }

    private PortfolioDto createPortfolioDto(
            UUID id,
            UUID resumeId,
            String name,
            String overview,
            String techStack,
            String link) {
        PortfolioDto d = new PortfolioDto();
        d.setId(id);
        d.setResumeId(resumeId);
        d.setName(name);
        d.setOverview(overview);
        d.setTechStack(techStack);
        d.setLink(link);
        return d;
    }

    private SocialLinkDto createSocialLinkDto(
            UUID id,
            UUID resumeId,
            String name,
            String link) {
        SocialLinkDto d = new SocialLinkDto();
        d.setId(id);
        d.setResumeId(resumeId);
        d.setName(name);
        d.setLink(link);
        return d;
    }

    private SelfPromotionDto createSelfPromotionDto(
            UUID id,
            UUID resumeId,
            String title,
            String content) {
        SelfPromotionDto d = new SelfPromotionDto();
        d.setId(id);
        d.setResumeId(resumeId);
        d.setTitle(title);
        d.setContent(content);
        return d;
    }

    /**
     * UserDtoを作成するヘルパーメソッド
     */
    private UserDto createUserDto() {
        UserDto dto = new UserDto();
        dto.setId(USER_ID);
        dto.setEmail("test@keirekipro.click");
        dto.setPassword("passwordHash");
        dto.setUsername("user");
        dto.setProfileImage("profile/test-user.jpg");
        dto.setTwoFactorAuthEnabled(true);
        dto.setCreatedAt(CREATED);
        dto.setUpdatedAt(UPDATED);
        dto.setAuthProviders(Collections.emptyList());
        return dto;
    }
}
