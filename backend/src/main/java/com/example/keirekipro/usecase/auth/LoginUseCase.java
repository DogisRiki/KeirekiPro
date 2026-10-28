package com.example.keirekipro.usecase.auth;

import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.usecase.auth.command.LoginCommand;
import com.example.keirekipro.usecase.auth.dto.LoginUseCaseDto;
import com.example.keirekipro.usecase.auth.store.PendingRegistrationStore;
import com.example.keirekipro.usecase.shared.exception.EmailNotVerifiedUseCaseException;
import com.example.keirekipro.usecase.shared.exception.EmailNotVerifiedUseCaseException.Kind;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * ログインユースケース
 */
@Service
@RequiredArgsConstructor
public class LoginUseCase {

    private static final String INVALID_CREDENTIALS_MESSAGE = "メールアドレスまたはパスワードが正しくありません。";

    /**
     * 入力されたパスワードと照らし合わせる確認前の登録の最大の件数
     */
    private static final int MAX_PENDING_REGISTRATIONS = 5;

    private final UserRepository userRepository;

    private final PasswordEncoder passwordEncoder;

    private final PendingRegistrationStore pendingRegistrationStore;

    /**
     * ログインのユースケースを実行する
     *
     * @param command コマンド
     * @return ユーザー認証情報
     */
    public LoginUseCaseDto execute(LoginCommand command) {

        // ユーザーが存在するか。アカウントが無ければ、確認前の登録と照らし合わせる
        User user = userRepository.findByEmail(command.getEmail())
                .orElseThrow(() -> rejectWithoutAccount(command));

        // パスワードが一致するか
        if (!passwordEncoder.matches(command.getPassword(), user.getPasswordHash())) {
            throw new UseCaseException(INVALID_CREDENTIALS_MESSAGE);
        }

        // 確認がまだなら、2段階認証が有効でも2段階認証に進まない
        if (!user.isEmailVerified()) {
            throw new EmailNotVerifiedUseCaseException(Kind.UNVERIFIED_ACCOUNT_EMAIL);
        }

        return LoginUseCaseDto.builder()
                .id(user.getId())
                .email(user.getEmail().getValue())
                .twoFactorAuthEnabled(user.isTwoFactorAuthEnabled())
                .roles(user.getRoleNames())
                .build();
    }

    /**
     * アカウントが無いときに投げる例外を決める
     * 確認前の登録のパスワードが合えば確認がまだの例外にし、合わなければ今と同じ例外にする
     *
     * @param command コマンド
     * @return 投げる例外
     */
    private UseCaseException rejectWithoutAccount(LoginCommand command) {
        boolean matchesPendingRegistration = pendingRegistrationStore
                .findByEmail(command.getEmail(), MAX_PENDING_REGISTRATIONS).stream()
                .anyMatch(r -> passwordEncoder.matches(command.getPassword(), r.passwordHash()));
        if (matchesPendingRegistration) {
            return new EmailNotVerifiedUseCaseException(Kind.PENDING_REGISTRATION);
        }
        return new UseCaseException(INVALID_CREDENTIALS_MESSAGE);
    }
}
