package com.example.keirekipro.domain.resume;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import com.example.keirekipro.domain.model.resume.Link;
import com.example.keirekipro.domain.model.resume.SociealLink;
import com.example.keirekipro.domain.shared.Notification;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

class SociealLinkTest {

    @Mock
    private Notification notification;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
    }

    @Test
    @DisplayName("新規構築用コンストラクタでインスタンス化する")
    void test1() {
        Link link = Link.create(notification, "https://example.com");
        SociealLink sociealLink = SociealLink.create(0, "GitHub", link);
        // インスタンスがnullでない。
        assertNotNull(sociealLink);
        // idが生成されている。
        assertNotNull(sociealLink.getId());
        // 並び順が正しい値である。
        assertEquals(0, sociealLink.getOrderNo());
        // ソーシャル名が正しい値である。
        assertEquals("GitHub", sociealLink.getName());
        // リンクが正しい値である。
        assertEquals(link, sociealLink.getLink());
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test2() {
        Link link = Link.create(notification, "https://example.com");
        SociealLink sociealLink = SociealLink.reconstruct("1234", 0, "GitHub", link);
        // インスタンスがnullでない。
        assertNotNull(sociealLink);
        // idが正しい値である。
        assertEquals(sociealLink.getId(), "1234");
        // 並び順が正しい値である。
        assertEquals(sociealLink.getOrderNo(), 0);
        // ソーシャル名が正しい値である。
        assertEquals(sociealLink.getName(), "GitHub");
        // リンクが正しい値である。
        assertEquals(link, sociealLink.getLink());
    }

    @Test
    @DisplayName("ソーシャル名を変更する")
    void test3() {
        Link link = Link.create(notification, "https://example.com");
        SociealLink beforeSociealLink = SociealLink.create(0, "GitHub", link);
        SociealLink afterSociealLink = beforeSociealLink.changeName("LinkedIn");
        // 変更したソーシャル名が正しい値である。
        assertEquals(afterSociealLink.getName(), "LinkedIn");
    }

    @Test
    @DisplayName("リンクを変更する")
    void test4() {
        Link beforeLink = Link.create(notification, "https://example.com");
        SociealLink beforeSociealLink = SociealLink.create(0, "GitHub", beforeLink);
        Link afterLink = Link.create(notification, "https://linkedin.com");
        SociealLink afterSociealLink = beforeSociealLink.changeLink(afterLink);
        // 変更したリンクが正しい値である。
        assertEquals(afterSociealLink.getLink(), afterLink);
    }

    @Test
    @DisplayName("ソーシャル名、リンクを変更する")
    void test5() {
        Link beforeLink = Link.create(notification, "https://example.com");
        SociealLink beforeSociealLink = SociealLink.create(0, "GitHub", beforeLink);
        Link afterLink = Link.create(notification, "https://linkedin.com");
        SociealLink afterSociealLink = beforeSociealLink.changeLink(afterLink).changeName("LinkedIn");
        // 変更した項目が正しい値である。
        assertEquals(afterSociealLink.getLink(), afterLink);
        assertEquals(afterSociealLink.getName(), "LinkedIn");
    }
}
