package com.example.keirekipro.usecase.resume.command;

import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * 自己PR更新ユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class UpdateSelfPromotionCommand {

    private UUID userId;

    private String resumeId;

    private UUID selfPromotionId;

    private String title;

    private String content;
}
