package com.example.keirekipro.unit.domain.model.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

import com.example.keirekipro.domain.model.resume.FullName;
import com.example.keirekipro.shared.ErrorCollector;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class FullNameTest {

    @Mock
    private ErrorCollector errorCollector;

    @Test
    @DisplayName("有効な値でインスタンス化する")
    void test1() {
        FullName fullName = FullName.create(errorCollector, "Yaま田", "タRoゥ");

        assertThat(fullName).isNotNull();
        assertThat(fullName.getLastName()).isEqualTo("Yaま田");
        assertThat(fullName.getFirstName()).isEqualTo("タRoゥ");
        verify(errorCollector, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("姓に不正な値が混入した状態でインスタンス化する")
    void test2() {
        FullName fullName = FullName.create(errorCollector, "@", "太郎");

        assertThat(fullName).isNotNull();
        // 姓に対するエラーメッセージが登録される
        verify(errorCollector, times(1)).addError(
                eq("lastName"),
                eq("姓には英数、ひらがな、カタカナ、漢字のみ使用できます。"));
        // 名に対するエラーメッセージは登録されない
        verify(errorCollector, never()).addError(eq("firstName"), anyString());
    }

    @Test
    @DisplayName("名に不正な値が混入した状態でインスタンス化する")
    void test3() {
        FullName fullName = FullName.create(errorCollector, "山田", "@");

        assertThat(fullName).isNotNull();
        // 名に対するエラーメッセージが登録される
        verify(errorCollector, times(1)).addError(
                eq("firstName"),
                eq("名には英数、ひらがな、カタカナ、漢字のみ使用できます。"));
        // 姓に対するエラーメッセージは登録されない
        verify(errorCollector, never()).addError(eq("lastName"), anyString());
    }

    @Test
    @DisplayName("姓と名に不正な値が混入した状態でインスタンス化する")
    void test4() {
        FullName fullName = FullName.create(errorCollector, "$", "@");

        assertThat(fullName).isNotNull();
        // 姓に対するエラーメッセージが登録される
        verify(errorCollector, times(1)).addError(
                eq("lastName"),
                eq("姓には英数、ひらがな、カタカナ、漢字のみ使用できます。"));
        // 名に対するエラーメッセージが登録される
        verify(errorCollector, times(1)).addError(
                eq("firstName"),
                eq("名には英数、ひらがな、カタカナ、漢字のみ使用できます。"));
    }

    @Test
    @DisplayName("姓がnullまたは空白の状態でインスタンス化する")
    void test5() {
        // nullのケース
        {
            reset(errorCollector);
            FullName fullName = FullName.create(errorCollector, null, "太郎");

            assertThat(fullName).isNotNull();
            verify(errorCollector, times(1)).addError(
                    eq("lastName"),
                    eq("姓は入力必須です。"));
            verify(errorCollector, never()).addError(eq("firstName"), anyString());
        }

        // 空文字のケース
        {
            reset(errorCollector);
            FullName fullName = FullName.create(errorCollector, "", "太郎");

            assertThat(fullName).isNotNull();
            verify(errorCollector, times(1)).addError(
                    eq("lastName"),
                    eq("姓は入力必須です。"));
            verify(errorCollector, never()).addError(eq("firstName"), anyString());
        }

        // スペースのみのケース
        {
            reset(errorCollector);
            FullName fullName = FullName.create(errorCollector, "   ", "太郎");

            assertThat(fullName).isNotNull();
            verify(errorCollector, times(1)).addError(
                    eq("lastName"),
                    eq("姓は入力必須です。"));
            verify(errorCollector, never()).addError(eq("firstName"), anyString());
        }

        // タブのみのケース
        {
            reset(errorCollector);
            FullName fullName = FullName.create(errorCollector, "\t", "太郎");

            assertThat(fullName).isNotNull();
            verify(errorCollector, times(1)).addError(
                    eq("lastName"),
                    eq("姓は入力必須です。"));
            verify(errorCollector, never()).addError(eq("firstName"), anyString());
        }
    }

    @Test
    @DisplayName("名がnullまたは空白の状態でインスタンス化する")
    void test6() {
        // nullのケース
        {
            reset(errorCollector);
            FullName fullName = FullName.create(errorCollector, "山田", null);

            assertThat(fullName).isNotNull();
            verify(errorCollector, times(1)).addError(
                    eq("firstName"),
                    eq("名は入力必須です。"));
            verify(errorCollector, never()).addError(eq("lastName"), anyString());
        }

        // 空文字のケース
        {
            reset(errorCollector);
            FullName fullName = FullName.create(errorCollector, "山田", "");

            assertThat(fullName).isNotNull();
            verify(errorCollector, times(1)).addError(
                    eq("firstName"),
                    eq("名は入力必須です。"));
            verify(errorCollector, never()).addError(eq("lastName"), anyString());
        }

        // スペースのみのケース
        {
            reset(errorCollector);
            FullName fullName = FullName.create(errorCollector, "山田", "   ");

            assertThat(fullName).isNotNull();
            verify(errorCollector, times(1)).addError(
                    eq("firstName"),
                    eq("名は入力必須です。"));
            verify(errorCollector, never()).addError(eq("lastName"), anyString());
        }

        // タブのみのケース
        {
            reset(errorCollector);
            FullName fullName = FullName.create(errorCollector, "山田", "\t");

            assertThat(fullName).isNotNull();
            verify(errorCollector, times(1)).addError(
                    eq("firstName"),
                    eq("名は入力必須です。"));
            verify(errorCollector, never()).addError(eq("lastName"), anyString());
        }
    }

    @Test
    @DisplayName("姓が11文字を超える状態でインスタンス化する")
    void test7() {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < 11; i++) {
            sb.append('a');
        }
        String longLastName = sb.toString();

        FullName fullName = FullName.create(errorCollector, longLastName, "太郎");

        assertThat(fullName).isNotNull();
        // 姓の桁数に対するエラーメッセージが登録される
        verify(errorCollector, times(1)).addError(
                eq("lastName"),
                eq("姓は10文字以内で入力してください。"));
        // 名に対するエラーメッセージは登録されない
        verify(errorCollector, never()).addError(eq("firstName"), anyString());
    }

    @Test
    @DisplayName("名が11文字を超える状態でインスタンス化する")
    void test8() {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < 11; i++) {
            sb.append('a');
        }
        String longFirstName = sb.toString();

        FullName fullName = FullName.create(errorCollector, "山田", longFirstName);

        assertThat(fullName).isNotNull();
        // 名の桁数に対するエラーメッセージが登録される
        verify(errorCollector, times(1)).addError(
                eq("firstName"),
                eq("名は10文字以内で入力してください。"));
        // 姓に対するエラーメッセージは登録されない
        verify(errorCollector, never()).addError(eq("lastName"), anyString());
    }

    @Test
    @DisplayName("姓が11文字を超え、かつ不正な値が混入した状態でインスタンス化する")
    void test9() {
        String longInvalidLastName = "aaaaaaaaaa@"; // 11文字 + 禁止文字

        FullName fullName = FullName.create(errorCollector, longInvalidLastName, "太郎");

        assertThat(fullName).isNotNull();

        // 桁数エラー + 禁止文字エラーの2回
        verify(errorCollector).addError(
                eq("lastName"),
                eq("姓は10文字以内で入力してください。"));
        verify(errorCollector).addError(
                eq("lastName"),
                eq("姓には英数、ひらがな、カタカナ、漢字のみ使用できます。"));
        verify(errorCollector, times(2)).addError(eq("lastName"), anyString());

        // 名に対するエラーメッセージは登録されない
        verify(errorCollector, never()).addError(eq("firstName"), anyString());
    }
}
