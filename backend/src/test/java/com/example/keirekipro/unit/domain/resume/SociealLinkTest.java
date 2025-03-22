package com.example.keirekipro.unit.domain.resume;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Link;
import com.example.keirekipro.domain.model.resume.SocialLink;
import com.example.keirekipro.shared.Notification;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class SociealLinkTest {

    @Mock
    private Notification notification;

    @Test
    @DisplayName("新規構築用コンストラクタでインスタンス化する")
    void test1() {
        Link link = Link.create(notification, "https://example.com");
        SocialLink sociealLink = SocialLink.create(0, "GitHub", link);

        assertThat(sociealLink).isNotNull();
        assertThat(sociealLink.getId()).isNotNull();
        assertThat(sociealLink.getOrderNo()).isEqualTo(0);
        assertThat(sociealLink.getName()).isEqualTo("GitHub");
        assertThat(sociealLink.getLink()).isEqualTo(link);
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test2() {
        Link link = Link.create(notification, "https://example.com");
        UUID id = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        SocialLink sociealLink = SocialLink.reconstruct(id, 0, "GitHub", link);

        assertThat(sociealLink).isNotNull();
        assertThat(sociealLink.getId()).isEqualTo(id);
        assertThat(sociealLink.getOrderNo()).isEqualTo(0);
        assertThat(sociealLink.getName()).isEqualTo("GitHub");
        assertThat(sociealLink.getLink()).isEqualTo(link);
    }

    @Test
    @DisplayName("ソーシャル名を変更する")
    void test3() {
        Link link = Link.create(notification, "https://example.com");
        SocialLink beforeSociealLink = SocialLink.create(0, "GitHub", link);
        SocialLink afterSociealLink = beforeSociealLink.changeName("LinkedIn");

        assertThat(afterSociealLink.getName()).isEqualTo("LinkedIn");
    }

    @Test
    @DisplayName("リンクを変更する")
    void test4() {
        Link beforeLink = Link.create(notification, "https://example.com");
        SocialLink beforeSociealLink = SocialLink.create(0, "GitHub", beforeLink);
        Link afterLink = Link.create(notification, "https://linkedin.com");
        SocialLink afterSociealLink = beforeSociealLink.changeLink(afterLink);

        assertThat(afterSociealLink.getLink()).isEqualTo(afterLink);
    }

    @Test
    @DisplayName("ソーシャル名、リンクを変更する")
    void test5() {
        Link beforeLink = Link.create(notification, "https://example.com");
        SocialLink beforeSociealLink = SocialLink.create(0, "GitHub", beforeLink);
        Link afterLink = Link.create(notification, "https://linkedin.com");
        SocialLink afterSociealLink = beforeSociealLink.changeLink(afterLink).changeName("LinkedIn");

        assertThat(afterSociealLink.getLink()).isEqualTo(afterLink);
        assertThat(afterSociealLink.getName()).isEqualTo("LinkedIn");
    }
}
