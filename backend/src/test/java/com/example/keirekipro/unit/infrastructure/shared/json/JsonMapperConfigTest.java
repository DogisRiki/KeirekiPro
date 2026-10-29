package com.example.keirekipro.unit.infrastructure.shared.json;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

import com.example.keirekipro.infrastructure.shared.json.JsonMapperConfig;

import tools.jackson.databind.json.JsonMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.json.JsonTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.TestConstructor;

import lombok.Getter;
import lombok.RequiredArgsConstructor;
import lombok.Setter;

/**
 * Spring Bootが作るJsonMapperの書き出しと読み取りが、Spring Boot 3(Jackson 2)のときと同じであることを確かめる
 *
 * 期待値は、Spring Boot 3.5.16 の main(b585d9c6)の @JsonTest で、同じ入力を ObjectMapper で書いた見本である
 */
@JsonTest
@Import(JsonMapperConfig.class)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class JsonMapperConfigTest {

    private final JsonMapper jsonMapper;

    /** writeValueAsString で書いた見本(絵文字はそのまま) */
    private static final String SAMPLE_STRING = "{\"zeta\":\"z\",\"alpha\":1,\"nullField\":null,\"emptyList\":[],"
            + "\"date\":\"2026-10-29\",\"dateTime\":\"2026-10-29T13:45:30.123\","
            + "\"instant\":\"2026-10-29T04:45:30.123456Z\",\"color\":\"GREEN\",\"emoji\":\"職務経歴😀👍🏽\"}";

    /** writeValueAsBytes で書いた見本(UTF-8。絵文字はサロゲートの対の \\u の形) */
    private static final String SAMPLE_BYTES = "{\"zeta\":\"z\",\"alpha\":1,\"nullField\":null,\"emptyList\":[],"
            + "\"date\":\"2026-10-29\",\"dateTime\":\"2026-10-29T13:45:30.123\","
            + "\"instant\":\"2026-10-29T04:45:30.123456Z\",\"color\":\"GREEN\","
            + "\"emoji\":\"職務経歴\\uD83D\\uDE00\\uD83D\\uDC4D\\uD83C\\uDFFD\"}";

    private static final String SAMPLE_EMOJI_STRING = "\"絵文字😀を含む文字列\"";

    enum Color {
        RED, GREEN
    }

    /** 宣言の順(zeta, alpha, ...)と名前の順が違う。nullField は、呼ぶ側が null を渡して null の項目の書き方を確かめる */
    @Getter
    static class SampleBean {
        private String zeta = "z";
        private Integer alpha = 1;
        private String nullField;
        private List<String> emptyList = List.of();
        private LocalDate date = LocalDate.of(2026, 10, 29);
        private LocalDateTime dateTime = LocalDateTime.of(2026, 10, 29, 13, 45, 30, 123_000_000);
        private Instant instant = Instant.parse("2026-10-29T04:45:30.123456Z");
        private Color color = Color.GREEN;
        private String emoji = "職務経歴😀👍🏽";

        SampleBean(String nullField) {
            this.nullField = nullField;
        }
    }

    record SampleRecord(String zeta, Integer alpha, String nullField, List<String> emptyList, LocalDate date,
            LocalDateTime dateTime, Instant instant, Color color, String emoji) {
    }

    @Getter
    @Setter
    static class PrimitiveHolder {
        private int count;
        private String name;
    }

    @Test
    @DisplayName("クラスを文字列に書くと、項目の名前と並び順と値の書き方と空の項目が見本と同じになる")
    void test1() {
        assertThat(jsonMapper.writeValueAsString(new SampleBean(null))).isEqualTo(SAMPLE_STRING);
    }

    @Test
    @DisplayName("recordを文字列に書くと、見本と同じになる")
    void test2() {
        SampleRecord sample = new SampleRecord("z", 1, null, List.of(), LocalDate.of(2026, 10, 29),
                LocalDateTime.of(2026, 10, 29, 13, 45, 30, 123_000_000),
                Instant.parse("2026-10-29T04:45:30.123456Z"), Color.GREEN, "職務経歴😀👍🏽");

        assertThat(jsonMapper.writeValueAsString(sample)).isEqualTo(SAMPLE_STRING);
    }

    @Test
    @DisplayName("絵文字を含む文字列を文字列に書くと、見本と同じになる")
    void test3() {
        assertThat(jsonMapper.writeValueAsString("絵文字😀を含む文字列")).isEqualTo(SAMPLE_EMOJI_STRING);
    }

    @Test
    @DisplayName("クラスをバイトに書くと、絵文字がサロゲートの対の形で書かれ、見本と同じになる")
    void test4() {
        byte[] bytes = jsonMapper.writeValueAsBytes(new SampleBean(null));

        assertThat(new String(bytes, StandardCharsets.UTF_8)).isEqualTo(SAMPLE_BYTES);
    }

    @Test
    @DisplayName("JSONのあとに余分な文字があっても、最初の値を読める")
    void test5() {
        PrimitiveHolder holder = jsonMapper.readValue("{\"count\":1,\"name\":\"a\"} x", PrimitiveHolder.class);

        assertThat(holder.getCount()).isEqualTo(1);
        assertThat(holder.getName()).isEqualTo("a");
    }

    @Test
    @DisplayName("基本型の項目がnullのとき、0として読める")
    void test6() {
        PrimitiveHolder holder = jsonMapper.readValue("{\"count\":null,\"name\":\"a\"}", PrimitiveHolder.class);

        assertThat(holder.getCount()).isZero();
        assertThat(holder.getName()).isEqualTo("a");
    }

    @Test
    @DisplayName("知らない項目があっても読める")
    void test7() {
        PrimitiveHolder holder = jsonMapper.readValue("{\"count\":2,\"name\":\"a\",\"other\":true}",
                PrimitiveHolder.class);

        assertThat(holder.getCount()).isEqualTo(2);
        assertThat(holder.getName()).isEqualTo("a");
    }
}
