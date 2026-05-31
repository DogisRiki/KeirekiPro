package com.example.keirekipro.usecase.resume.command;

import java.time.YearMonth;
import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * 資格更新ユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class UpdateCertificationCommand {

    private UUID userId;

    private String resumeId;

    private UUID certificationId;

    private String name;

    private YearMonth date;
}
