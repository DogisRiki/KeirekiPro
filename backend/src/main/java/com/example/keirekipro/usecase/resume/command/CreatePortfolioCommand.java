package com.example.keirekipro.usecase.resume.command;

import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * ポートフォリオ作成ユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class CreatePortfolioCommand {

    private UUID userId;

    private String resumeId;

    private String name;

    private String overview;

    private String techStack;

    private String link;
}
