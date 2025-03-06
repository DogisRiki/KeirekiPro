package com.example.keirekipro.unit.domain.resume;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

import java.util.List;

import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.shared.Notification;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

class ResumeNameTest {

    @Mock
    private Notification notification;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
    }

    @Test
    @DisplayName("有効な値でインスタンス化する")
    void test1() {
        ResumeName resumeName = ResumeName.create(notification, "職務経歴書名サンプル");
        // インスタンスがnullでない。
        assertNotNull(resumeName);
        // 職務経歴書名が正しい値である。
        assertEquals("職務経歴書名サンプル", resumeName.getValue());
        // notification.addError()が一度も呼ばれていない。
        verify(notification, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("職務経歴書名に不正な値が混入した状態でインスタンス化する")
    void test2() {
        String invalidChars = ResumeName.INVALID_PATTERN.replace("[", "").replace("]", "");
        for (char c : invalidChars.toCharArray()) {
            // 毎回モックをリセットして、呼び出し履歴をクリアする
            reset(notification);
            // 通常の文字列に禁則文字を混ぜる
            String invalidName = "Valid" + c;

            ResumeName resumeName = ResumeName.create(notification, invalidName);
            // インスタンスがnullでない。
            assertNotNull(resumeName);
            // 職務経歴書名に対するエラーメッセージが登録される
            verify(notification, times(1)).addError(
                    eq("resumeName"),
                    eq("職務経歴書名には次の文字は使用できません。\n" + "\\ / : * ? \" < > | "));
        }
    }

    @Test
    @DisplayName("職務経歴書名の先頭または末尾に不正な文字列が混入した状態でインスタンス化する")
    void test3() {
        List<String> testValues = List.of(
                ".職務経歴書名",
                "職務経歴書名.",
                ".職務経歴書名.");
        for (String value : testValues) {
            // 毎回モックをリセットして、呼び出し履歴をクリアする
            reset(notification);

            ResumeName resumeName = ResumeName.create(notification, value);
            // インスタンスがnullでない。
            assertNotNull(resumeName);
            // 職務経歴書名に対するエラーメッセージが登録される
            verify(notification, times(1)).addError(
                    eq("resumeName"),
                    eq("職務経歴書名の先頭または末尾に「.」を使用することはできません。"));
        }
    }

    @Test
    @DisplayName("職務経歴書名に禁止文字も含み、かつ先頭/末尾に不正な文字列が混入した状態でインスタンス化する")
    void test4() {
        String invalidChars = ResumeName.INVALID_PATTERN.replace("[", "").replace("]", "");

        // 1) 先頭にドット + 禁則文字
        // 2) 末尾にドット + 禁則文字
        for (char c : invalidChars.toCharArray()) {
            // 先頭にドット
            {
                // 毎回モックをリセットして、呼び出し履歴をクリアする
                reset(notification);
                String value = "." + "invalid" + c;
                ResumeName resumeName = ResumeName.create(notification, value);
                // インスタンスがnullでない。
                assertNotNull(resumeName);

                // 禁止文字エラー + 先頭ドットエラーの2回
                verify(notification).addError(
                        eq("resumeName"),
                        eq("職務経歴書名には次の文字は使用できません。\n" + "\\ / : * ? \" < > | "));
                verify(notification).addError(
                        eq("resumeName"),
                        eq("職務経歴書名の先頭または末尾に「.」を使用することはできません。"));

                // 2回呼ばれたことを総数でも確認（呼び出し順が変わる可能性もあるため）
                verify(notification, times(2)).addError(eq("resumeName"), anyString());
            }

            // 末尾にドット
            {
                // 毎回モックをリセットして、呼び出し履歴をクリアする
                reset(notification);
                String value = "invalid" + c + "."; // 例: "invalid/."
                ResumeName resumeName = ResumeName.create(notification, value);
                // インスタンスがnullでない。
                assertNotNull(resumeName);

                // 禁止文字エラー + 先頭ドットエラーの2回
                verify(notification).addError(
                        eq("resumeName"),
                        eq("職務経歴書名には次の文字は使用できません。\n" + "\\ / : * ? \" < > | "));
                verify(notification).addError(
                        eq("resumeName"),
                        eq("職務経歴書名の先頭または末尾に「.」を使用することはできません。"));
                // 2回呼ばれたことを総数でも確認（呼び出し順が変わる可能性もあるため）
                verify(notification, times(2)).addError(eq("resumeName"), anyString());
            }
        }
    }

    @Test
    @DisplayName("職務経歴書名がnullまたは空白の状態でインスタンス化する")
    void test5() {
        // nullのケース
        {
            reset(notification);
            ResumeName resumeName = ResumeName.create(notification, null);
            assertNotNull(resumeName);
            verify(notification, times(1)).addError(
                    eq("resumeName"),
                    eq("職務経歴書名は入力必須です。"));
        }

        // 空文字のケース
        {
            reset(notification);
            ResumeName resumeName = ResumeName.create(notification, "");
            assertNotNull(resumeName);
            verify(notification, times(1)).addError(
                    eq("resumeName"),
                    eq("職務経歴書名は入力必須です。"));
        }

        // スペースのみのケース
        {
            reset(notification);
            ResumeName resumeName = ResumeName.create(notification, "   ");
            assertNotNull(resumeName);
            verify(notification, times(1)).addError(
                    eq("resumeName"),
                    eq("職務経歴書名は入力必須です。"));
        }

        // タブのみのケース
        {
            reset(notification);
            ResumeName resumeName = ResumeName.create(notification, "\t");
            assertNotNull(resumeName);
            verify(notification, times(1)).addError(
                    eq("resumeName"),
                    eq("職務経歴書名は入力必須です。"));
        }
    }
}
