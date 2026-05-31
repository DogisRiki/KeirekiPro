package com.example.keirekipro.usecase.resume.command;

import java.time.YearMonth;
import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * 職歴作成ユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class CreateCareerCommand {

    private UUID userId;

    private String resumeId;

    private String companyName;

    private YearMonth startDate;

    private YearMonth endDate;

    private Boolean active;
}
