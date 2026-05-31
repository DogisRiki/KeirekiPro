package com.example.keirekipro.usecase.resume.command;

import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * SNSプラットフォーム更新ユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class UpdateSnsPlatformCommand {

    private UUID userId;

    private String resumeId;

    private UUID snsPlatformId;

    private String name;

    private String link;
}
