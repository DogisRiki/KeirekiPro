package com.example.keirekipro.unit.domain.model.resume;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Link;
import com.example.keirekipro.domain.model.resume.SnsPlatform;
import com.example.keirekipro.shared.Notification;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class SnsPlatformTest {

    @Mock
    private Notification notification;

    @Test
    @DisplayName("新規構築用コンストラクタでインスタンス化する")
    void test1() {
        Link link = Link.create(notification, "https://example.com");
        SnsPlatform snsPlatform = SnsPlatform.create(notification, "GitHub", link);

        assertThat(snsPlatform).isNotNull();
        assertThat(snsPlatform.getId()).isNotNull();
        assertThat(snsPlatform.getName()).isEqualTo("GitHub");
        assertThat(snsPlatform.getLink()).isEqualTo(link);
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test2() {
        Link link = Link.create(notification, "https://example.com");
        UUID id = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        SnsPlatform snsPlatform = SnsPlatform.reconstruct(id, "GitHub", link);

        assertThat(snsPlatform).isNotNull();
        assertThat(snsPlatform.getId()).isEqualTo(id);
        assertThat(snsPlatform.getName()).isEqualTo("GitHub");
        assertThat(snsPlatform.getLink()).isEqualTo(link);
    }

    @Test
    @DisplayName("プラットフォーム名を変更する")
    void test3() {
        Link link = Link.create(notification, "https://example.com");
        SnsPlatform beforeSnsPlatform = SnsPlatform.create(notification, "GitHub", link);
        SnsPlatform afterSnsPlatform = beforeSnsPlatform.changeName(notification, "LinkedIn");

        assertThat(afterSnsPlatform.getName()).isEqualTo("LinkedIn");
    }

    @Test
    @DisplayName("リンクを変更する")
    void test4() {
        Link beforeLink = Link.create(notification, "https://example.com");
        SnsPlatform beforeSnsPlatform = SnsPlatform.create(notification, "GitHub", beforeLink);
        Link afterLink = Link.create(notification, "https://linkedin.com");
        SnsPlatform afterSnsPlatform = beforeSnsPlatform.changeLink(notification, afterLink);

        assertThat(afterSnsPlatform.getLink()).isEqualTo(afterLink);
    }

    @Test
    @DisplayName("プラットフォーム名、リンクを変更する")
    void test5() {
        Link beforeLink = Link.create(notification, "https://example.com");
        SnsPlatform beforeSnsPlatform = SnsPlatform.create(notification, "GitHub", beforeLink);
        Link afterLink = Link.create(notification, "https://linkedin.com");
        SnsPlatform afterSnsPlatform = beforeSnsPlatform.changeLink(notification, afterLink).changeName(notification,
                "LinkedIn");

        assertThat(afterSnsPlatform.getLink()).isEqualTo(afterLink);
        assertThat(afterSnsPlatform.getName()).isEqualTo("LinkedIn");
    }

    @Test
    @DisplayName("必須項目が未入力の場合、エラーが通知される")
    void test6() {
        Notification notification = new Notification();

        SnsPlatform.create(notification, "", null);

        assertThat(notification.getErrors().get("name")).containsExactly("プラットフォーム名は入力必須です。");
        assertThat(notification.getErrors().get("link")).containsExactly("リンクは入力必須です。");
    }

    @Test
    @DisplayName("プラットフォーム名が最大文字数を超える場合、エラーが通知される")
    void test7() {
        Notification notification = new Notification();
        Notification linkNotification = new Notification();
        String longName = "a".repeat(51);
        Link link = Link.create(linkNotification, "https://example.com");

        SnsPlatform.create(notification, longName, link);

        assertThat(notification.getErrors().get("name")).containsExactly("プラットフォーム名は50文字以内で入力してください。");
    }
}
