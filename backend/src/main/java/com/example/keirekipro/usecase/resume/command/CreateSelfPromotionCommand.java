package com.example.keirekipro.usecase.resume.command;

import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * 自己PR作成ユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class CreateSelfPromotionCommand {

    private UUID userId;

    private String resumeId;

    private String title;

    private String content;
}
