package com.example.keirekipro.unit.infrastructure.query.techstack;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;

import com.example.keirekipro.config.PostgresTestContainerConfig;
import com.example.keirekipro.infrastructure.query.techstack.TechStackDto;
import com.example.keirekipro.infrastructure.query.techstack.TechStackMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mybatis.spring.boot.test.autoconfigure.MybatisTest;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
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
class TechStackMapperTest {

    private final TechStackMapper techStackMapper;
    private final JdbcTemplate jdbcTemplate;

    private static final String CATEGORY_CODE_A = "TEST_CAT_A";
    private static final String CATEGORY_CODE_B = "TEST_CAT_B";
    private static final String CATEGORY_CODE_C = "TEST_CAT_C";

    private static final String MAIN_CATEGORY_A = "mainA";
    private static final String SUB_CATEGORY_A = "subA";
    private static final String SUB_CATEGORY_B = "subB";

    private static final String MAIN_CATEGORY_B = "mainB";

    @Test
    @DisplayName("selectAll_技術スタックマスタが存在しない場合、空リストが返る")
    void test1() {
        List<TechStackDto> list = techStackMapper.selectAll();
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("selectAll_複数カテゴリ・複数技術が存在する場合、各フィールドが正しくマッピングされ並び順も定義通りとなる")
    void test2() {
        // カテゴリマスタを登録
        insertCategory(CATEGORY_CODE_A, MAIN_CATEGORY_A, SUB_CATEGORY_A);
        insertCategory(CATEGORY_CODE_B, MAIN_CATEGORY_A, SUB_CATEGORY_B);
        insertCategory(CATEGORY_CODE_C, MAIN_CATEGORY_B, SUB_CATEGORY_A);

        // 技術スタックマスタを登録
        insertTechStack(10, "A-First", CATEGORY_CODE_A);
        insertTechStack(20, "A-Second", CATEGORY_CODE_A);
        insertTechStack(30, "B-Only", CATEGORY_CODE_B);
        insertTechStack(40, "C-Only", CATEGORY_CODE_C);

        // 実行
        List<TechStackDto> list = techStackMapper.selectAll();

        // 件数検証
        assertThat(list).hasSize(4);

        // 並び順検証
        TechStackDto first = list.get(0);
        assertThat(first.getMainCategory()).isEqualTo(MAIN_CATEGORY_A);
        assertThat(first.getSubCategory()).isEqualTo(SUB_CATEGORY_A);
        assertThat(first.getName()).isEqualTo("A-First");

        TechStackDto second = list.get(1);
        assertThat(second.getMainCategory()).isEqualTo(MAIN_CATEGORY_A);
        assertThat(second.getSubCategory()).isEqualTo(SUB_CATEGORY_A);
        assertThat(second.getName()).isEqualTo("A-Second");

        TechStackDto third = list.get(2);
        assertThat(third.getMainCategory()).isEqualTo(MAIN_CATEGORY_A);
        assertThat(third.getSubCategory()).isEqualTo(SUB_CATEGORY_B);
        assertThat(third.getName()).isEqualTo("B-Only");

        TechStackDto fourth = list.get(3);
        assertThat(fourth.getMainCategory()).isEqualTo(MAIN_CATEGORY_B);
        assertThat(fourth.getSubCategory()).isEqualTo(SUB_CATEGORY_A);
        assertThat(fourth.getName()).isEqualTo("C-Only");
    }

    /**
     * tech_stack_category_mst にテストデータを挿入するヘルパーメソッド
     */
    private void insertCategory(String code, String mainCategory, String subCategory) {
        jdbcTemplate.update(
                "INSERT INTO tech_stack_category_mst (code, main_category, sub_category) VALUES (?, ?, ?)",
                code,
                mainCategory,
                subCategory);
    }

    /**
     * tech_stack_mst にテストデータを挿入するヘルパーメソッド
     */
    private void insertTechStack(int id, String name, String categoryCode) {
        jdbcTemplate.update(
                "INSERT INTO tech_stack_mst (id, name, category_code) VALUES (?, ?, ?)",
                id,
                name,
                categoryCode);
    }
}
