package com.example.keirekipro.domain.resume;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
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
        assertEquals(resumeName.getValue(), "職務経歴書名サンプル");
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
    @DisplayName("equals")
    void test4() {
        ResumeName resumeName1 = ResumeName.create(notification, "職務経歴書名サンプル");
        ResumeName resumeName2 = ResumeName.create(notification, "職務経歴書名サンプル");
        ResumeName resumeName3 = ResumeName.create(notification, "ああ");
        // 値が同一であれば等価。
        assertEquals(resumeName1, resumeName2);
        // 値が同一でなければ等価でない。
        assertNotEquals(resumeName1, resumeName3);
    }

    @Test
    @DisplayName("hashCode")
    void test5() {
        int resumeName1 = ResumeName.create(notification, "職務経歴書名サンプル").hashCode();
        int resumeName2 = ResumeName.create(notification, "職務経歴書名サンプル").hashCode();
        int resumeName3 = ResumeName.create(notification, "ああ").hashCode();
        // 値が同一であれば同一。
        assertEquals(resumeName1, resumeName2);
        // 値が同一でなければ同一でない。
        assertNotEquals(resumeName1, resumeName3);
    }
}
