package com.example.keirekipro.unit.domain.model.resume;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Link;
import com.example.keirekipro.domain.model.resume.Portfolio;
import com.example.keirekipro.shared.Notification;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class PortfolioTest {

    @Mock
    private Notification notification;

    @Test
    @DisplayName("新規構築用コンストラクタでインスタンス化する")
    void test1() {
        Link link = Link.create(notification, "https://example.com");
        Portfolio portfolio = Portfolio.create(0, "ポートフォリオ名", "概要説明", "Java, Spring, React", link);

        assertThat(portfolio).isNotNull();
        assertThat(portfolio.getId()).isNotNull();
        assertThat(portfolio.getOrderNo()).isEqualTo(0);
        assertThat(portfolio.getName()).isEqualTo("ポートフォリオ名");
        assertThat(portfolio.getOverview()).isEqualTo("概要説明");
        assertThat(portfolio.getTechStack()).isEqualTo("Java, Spring, React");
        assertThat(portfolio.getLink()).isEqualTo(link);
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test2() {
        Link link = Link.create(notification, "https://example.com");
        UUID id = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        Portfolio portfolio = Portfolio.reconstruct(id, 0, "ポートフォリオ名", "概要説明", "Java, Spring, React", link);

        assertThat(portfolio).isNotNull();
        assertThat(portfolio.getId()).isEqualTo(id);
        assertThat(portfolio.getOrderNo()).isEqualTo(0);
        assertThat(portfolio.getName()).isEqualTo("ポートフォリオ名");
        assertThat(portfolio.getOverview()).isEqualTo("概要説明");
        assertThat(portfolio.getTechStack()).isEqualTo("Java, Spring, React");
        assertThat(portfolio.getLink()).isEqualTo(link);
    }

    @Test
    @DisplayName("ポートフォリオ名を変更する")
    void test3() {
        Link link = Link.create(notification, "https://example.com");
        Portfolio beforePortfolio = Portfolio.create(0, "ポートフォリオ名", "概要説明", "Java, Spring, React", link);
        Portfolio afterPortfolio = beforePortfolio.changeName("新しいポートフォリオ名");

        assertThat(afterPortfolio.getName()).isEqualTo("新しいポートフォリオ名");
    }

    @Test
    @DisplayName("ポートフォリオ概要を変更する")
    void test4() {
        Link link = Link.create(notification, "https://example.com");
        Portfolio beforePortfolio = Portfolio.create(0, "ポートフォリオ名", "概要説明", "Java, Spring, React", link);
        Portfolio afterPortfolio = beforePortfolio.changeOverview("新しい概要説明");

        assertThat(afterPortfolio.getOverview()).isEqualTo("新しい概要説明");
    }

    @Test
    @DisplayName("技術スタックを変更する")
    void test5() {
        Link link = Link.create(notification, "https://example.com");
        Portfolio beforePortfolio = Portfolio.create(0, "ポートフォリオ名", "概要説明", "Java, Spring, React", link);
        Portfolio afterPortfolio = beforePortfolio.changeTechStack("TypeScript, Node.js");

        assertThat(afterPortfolio.getTechStack()).isEqualTo("TypeScript, Node.js");
    }

    @Test
    @DisplayName("リンクを変更する")
    void test6() {
        Link beforeLink = Link.create(notification, "https://example.com");
        Portfolio beforePortfolio = Portfolio.create(0, "ポートフォリオ名", "概要説明", "Java, Spring, React", beforeLink);
        Link afterLink = Link.create(notification, "https://github.com");
        Portfolio afterPortfolio = beforePortfolio.changeLink(afterLink);

        assertThat(afterPortfolio.getLink()).isEqualTo(afterLink);
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

        assertThat(afterPortfolio.getName()).isEqualTo("新しいポートフォリオ名");
        assertThat(afterPortfolio.getOverview()).isEqualTo("新しい概要説明");
        assertThat(afterPortfolio.getTechStack()).isEqualTo("TypeScript, Node.js");
        assertThat(afterPortfolio.getLink()).isEqualTo(afterLink);
    }
}
