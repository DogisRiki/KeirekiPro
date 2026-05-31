package com.example.keirekipro.usecase.user;

import java.util.UUID;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.user.command.SetEmailAndPasswordCommand;

import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * メールアドレス+パスワード設定ユースケース
 */
@Service
@RequiredArgsConstructor
public class SetEmailAndPasswordUseCase {

    private final UserRepository userRepository;

    private final PasswordEncoder passwordEncoder;

    /**
     * メールアドレス+パスワードの設定ユースケースを実行する
     *
     * @param command コマンド
     */
    @Transactional
    public void execute(SetEmailAndPasswordCommand command) {
        UUID userId = command.getUserId();

        User user = userRepository.findById(userId)
                .orElseThrow(() -> new AuthenticationCredentialsNotFoundException("不正なアクセスです。"));

        ErrorCollector errorCollector = new ErrorCollector();

        if (command.getEmail() != null) {
            Email email = Email.create(errorCollector, command.getEmail());
            user = user.setEmail(errorCollector, email);
        }

        if (command.getPassword() != null) {
            String passwordHash = passwordEncoder.encode(command.getPassword());
            user = user.resetPassword(passwordHash);
        }

        userRepository.save(user);
    }
}
