package com.example.keirekipro.usecase.resume.command;

import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * 職務経歴書作成・コピー作成ユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class CreateResumeCommand {

    private UUID userId;

    private String resumeName;

    private UUID resumeId;
}
