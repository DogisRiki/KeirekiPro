package com.example.keirekipro.usecase.resume.command;

import java.time.LocalDate;
import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * 職務経歴書基本情報更新ユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class UpdateResumeBasicCommand {

    private UUID userId;

    private String resumeId;

    private String resumeName;

    private LocalDate date;

    private String lastName;

    private String firstName;
}
