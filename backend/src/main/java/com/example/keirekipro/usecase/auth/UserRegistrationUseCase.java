package com.example.keirekipro.usecase.auth;

import java.time.Instant;
import java.util.Collections;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.service.user.UserEmailDuplicationCheckService;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.auth.command.UserRegistrationCommand;
import com.example.keirekipro.usecase.auth.store.PendingRegistration;
import com.example.keirekipro.usecase.auth.store.PendingRegistrationStore;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationPurpose;

import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * ユーザー新規登録ユースケース
 * アカウントは作らず、確認前の登録を置いて確認のメールを送る。アカウントは確認のリンクを受け付けたときに作る
 */
@Service
@RequiredArgsConstructor
public class UserRegistrationUseCase {

    private final PasswordEncoder passwordEncoder;

    private final UserEmailDuplicationCheckService userEmailDuplicationCheckService;

    private final PendingRegistrationStore pendingRegistrationStore;

    private final EmailVerificationMailer mailer;

    /**
     * ユーザー新規登録ユースケースを実行する
     *
     * @param command コマンド
     */
    public void execute(UserRegistrationCommand command) {

        ErrorCollector errorCollector = new ErrorCollector();

        // メールアドレス値オブジェクトを作成
        Email email = Email.create(errorCollector, command.getEmail());

        // メールアドレス重複チェック
        userEmailDuplicationCheckService.execute(email);

        String passwordHash = passwordEncoder.encode(command.getPassword());

        // 入力の検証だけに使い、作ったユーザーは保存しない
        User.create(errorCollector, email, passwordHash, Collections.emptyMap(), null, command.getUsername());

        PendingRegistration registration = new PendingRegistration(
                UUID.randomUUID(), command.getEmail(), passwordHash, command.getUsername(), Instant.now());
        pendingRegistrationStore.save(registration, EmailVerificationPurpose.REGISTRATION.getLinkValidity());

        // RATE_LIMITED のときも登録は受け付ける
        try {
            mailer.send(command.getEmail(), registration.id(), EmailVerificationPurpose.REGISTRATION);
        } catch (RuntimeException e) {
            pendingRegistrationStore.delete(registration);
            throw e;
        }
    }
}
