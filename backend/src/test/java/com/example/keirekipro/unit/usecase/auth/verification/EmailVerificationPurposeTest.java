package com.example.keirekipro.unit.usecase.auth.verification;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;

import com.example.keirekipro.usecase.auth.verification.EmailVerificationPurpose;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class EmailVerificationPurposeTest {

    @Test
    @DisplayName("PASSWORD_RESET の期限は10分で、ほかの3つは24時間である")
    void test1() {
        assertThat(EmailVerificationPurpose.values()).hasSize(4);
        assertThat(EmailVerificationPurpose.REGISTRATION.getLinkValidity()).isEqualTo(Duration.ofHours(24));
        assertThat(EmailVerificationPurpose.ACCOUNT_EMAIL.getLinkValidity()).isEqualTo(Duration.ofHours(24));
        assertThat(EmailVerificationPurpose.PENDING_EMAIL.getLinkValidity()).isEqualTo(Duration.ofHours(24));
        assertThat(EmailVerificationPurpose.PASSWORD_RESET.getLinkValidity()).isEqualTo(Duration.ofMinutes(10));
    }
}
