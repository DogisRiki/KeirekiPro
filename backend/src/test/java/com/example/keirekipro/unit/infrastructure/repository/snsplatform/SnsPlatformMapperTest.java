package com.example.keirekipro.unit.infrastructure.repository.snsplatform;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;

import com.example.keirekipro.config.PostgresTestContainerConfig;
import com.example.keirekipro.infrastructure.repository.snsplatform.SnsPlatformDto;
import com.example.keirekipro.infrastructure.repository.snsplatform.SnsPlatformMapper;

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
class SnsPlatformMapperTest {

    private final SnsPlatformMapper snsPlatformMapper;
    private final JdbcTemplate jdbcTemplate;

    @Test
    @DisplayName("selectAll_SNSプラットフォームマスタが存在しない場合、空リストが返る")
    void test1() {
        List<SnsPlatformDto> list = snsPlatformMapper.selectAll();
        assertThat(list).isEmpty();
    }

    @Test
    @DisplayName("selectAll_複数SNSプラットフォームが存在する場合、プラットフォーム名が正しく取得できる")
    void test2() {
        // SNSプラットフォームマスタを登録
        insertSnsPlatform(10, "X");
        insertSnsPlatform(20, "Instagram");
        insertSnsPlatform(30, "YouTube");

        // 実行
        List<SnsPlatformDto> list = snsPlatformMapper.selectAll();

        // 件数検証
        assertThat(list).hasSize(3);

        // プラットフォーム名の検証
        assertThat(list).extracting(SnsPlatformDto::getName)
                .containsExactlyInAnyOrder("X", "Instagram", "YouTube");
    }

    /**
     * sns_platform_mstにテストデータを挿入するヘルパーメソッド
     */
    private void insertSnsPlatform(int id, String name) {
        jdbcTemplate.update(
                "INSERT INTO sns_platform_mst (id, name) VALUES (?, ?)",
                id,
                name);
    }
}
