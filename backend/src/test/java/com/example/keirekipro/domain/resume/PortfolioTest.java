package com.example.keirekipro.domain.resume;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Link;
import com.example.keirekipro.domain.model.resume.Portfolio;
import com.example.keirekipro.domain.shared.Notification;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

class PortfolioTest {

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
        Portfolio portfolio = Portfolio.create(0, "ポートフォリオ名", "概要説明", "Java, Spring, React", link);
        // インスタンスがnullでない。
        assertNotNull(portfolio);
        // idが生成されている。
        assertNotNull(portfolio.getId());
        // 並び順が正しい値である。
        assertEquals(0, portfolio.getOrderNo());
        // ポートフォリオ名が正しい値である。
        assertEquals("ポートフォリオ名", portfolio.getName());
        // ポートフォリオ概要が正しい値である。
        assertEquals("概要説明", portfolio.getOverview());
        // 技術スタックが正しい値である。
        assertEquals("Java, Spring, React", portfolio.getTechStack());
        // リンクが正しい値である。
        assertEquals(link, portfolio.getLink());
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test2() {
        Link link = Link.create(notification, "https://example.com");
        UUID id = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        Portfolio portfolio = Portfolio.reconstruct(id, 0, "ポートフォリオ名", "概要説明", "Java, Spring, React", link);
        // インスタンスがnullでない。
        assertNotNull(portfolio);
        // idが正しい値である。
        assertEquals(portfolio.getId(), id);
        // 並び順が正しい値である。
        assertEquals(portfolio.getOrderNo(), 0);
        // ポートフォリオ名が正しい値である。
        assertEquals(portfolio.getName(), "ポートフォリオ名");
        // ポートフォリオ概要が正しい値である。
        assertEquals(portfolio.getOverview(), "概要説明");
        // 技術スタックが正しい値である。
        assertEquals(portfolio.getTechStack(), "Java, Spring, React");
        // リンクが正しい値である。
        assertEquals(portfolio.getLink(), link);
    }

    @Test
    @DisplayName("ポートフォリオ名を変更する")
    void test3() {
        Link link = Link.create(notification, "https://example.com");
        Portfolio beforePortfolio = Portfolio.create(0, "ポートフォリオ名", "概要説明", "Java, Spring, React", link);
        Portfolio afterPortfolio = beforePortfolio.changeName("新しいポートフォリオ名");
        // 変更したポートフォリオ名が正しい値である。
        assertEquals(afterPortfolio.getName(), "新しいポートフォリオ名");
    }

    @Test
    @DisplayName("ポートフォリオ概要を変更する")
    void test4() {
        Link link = Link.create(notification, "https://example.com");
        Portfolio beforePortfolio = Portfolio.create(0, "ポートフォリオ名", "概要説明", "Java, Spring, React", link);
        Portfolio afterPortfolio = beforePortfolio.changeOverview("新しい概要説明");
        // 変更したポートフォリオ概要が正しい値である。
        assertEquals(afterPortfolio.getOverview(), "新しい概要説明");
    }

    @Test
    @DisplayName("技術スタックを変更する")
    void test5() {
        Link link = Link.create(notification, "https://example.com");
        Portfolio beforePortfolio = Portfolio.create(0, "ポートフォリオ名", "概要説明", "Java, Spring, React", link);
        Portfolio afterPortfolio = beforePortfolio.changeTechStack("TypeScript, Node.js");
        // 変更した技術スタックが正しい値である。
        assertEquals(afterPortfolio.getTechStack(), "TypeScript, Node.js");
    }

    @Test
    @DisplayName("リンクを変更する")
    void test6() {
        Link beforeLink = Link.create(notification, "https://example.com");
        Portfolio beforePortfolio = Portfolio.create(0, "ポートフォリオ名", "概要説明", "Java, Spring, React", beforeLink);
        Link afterLink = Link.create(notification, "https://github.com");
        Portfolio afterPortfolio = beforePortfolio.changeLink(afterLink);
        // 変更したリンクが正しい値である。
        assertEquals(afterPortfolio.getLink(), afterLink);
    }

    @Test
    @DisplayName("ポートフォリオ名、概要、技術スタック、リンクを変更する")
    void test7() {
        Link beforeLink = Link.create(notification, "https://example.com");
        Portfolio beforePortfolio = Portfolio.create(0, "ポートフォリオ名", "概要説明", "Java, Spring, React", beforeLink);
        Link afterLink = Link.create(notification, "https://github.com");
        Portfolio afterPortfolio = beforePortfolio.changeName("新しいポートフォリオ名")
                .changeOverview("新しい概要説明")
                .changeTechStack("TypeScript, Node.js")
                .changeLink(afterLink);
        // 変更した項目が正しい値である。
        assertEquals(afterPortfolio.getName(), "新しいポートフォリオ名");
        assertEquals(afterPortfolio.getOverview(), "新しい概要説明");
        assertEquals(afterPortfolio.getTechStack(), "TypeScript, Node.js");
        assertEquals(afterPortfolio.getLink(), afterLink);
    }
}
