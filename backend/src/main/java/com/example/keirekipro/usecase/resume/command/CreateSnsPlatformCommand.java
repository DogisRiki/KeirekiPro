package com.example.keirekipro.usecase.resume.command;

import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * SNSプラットフォーム作成ユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class CreateSnsPlatformCommand {

    private UUID userId;

    private String resumeId;

    private String name;

    private String link;
}
