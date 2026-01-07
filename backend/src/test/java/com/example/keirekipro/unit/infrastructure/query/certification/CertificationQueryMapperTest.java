package com.example.keirekipro.unit.infrastructure.query.certification;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;

import com.example.keirekipro.config.PostgresTestContainerConfig;
import com.example.keirekipro.infrastructure.query.certification.CertificationQueryMapper;
import com.example.keirekipro.infrastructure.query.certification.CertificationQueryMapper.CertificationRow;

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
class CertificationQueryMapperTest {

    private final CertificationQueryMapper mapper;
    private final JdbcTemplate jdbcTemplate;

    @Test
    @DisplayName("selectAll_資格マスタが存在しない場合、空リストが返る")
    void test1() {
        List<CertificationRow> list = mapper.selectAll();
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("selectAll_複数資格が存在する場合、資格名が正しく取得できる")
    void test2() {
        // 資格マスタを登録
        insertCertification(10, "基本情報技術者");
        insertCertification(20, "応用情報技術者");
        insertCertification(30, "AWS SAA");

        // 実行
        List<CertificationRow> list = mapper.selectAll();

        // 件数検証
        assertThat(list).hasSize(3);

        // 資格名の検証
        assertThat(list).extracting(CertificationRow::getName)
                .containsExactlyInAnyOrder("基本情報技術者", "応用情報技術者", "AWS SAA");
    }

    /**
     * certification_mstにテストデータを挿入するヘルパーメソッド
     */
    private void insertCertification(int id, String name) {
        jdbcTemplate.update(
                "INSERT INTO certification_mst (id, name) VALUES (?, ?)",
                id,
                name);
    }
}
