package com.example.keirekipro.usecase.resume.command;

import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * ポートフォリオ更新ユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class UpdatePortfolioCommand {

    private UUID userId;

    private String resumeId;

    private UUID portfolioId;

    private String name;

    private String overview;

    private String techStack;

    private String link;
}
