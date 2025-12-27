package com.example.keirekipro.usecase.auth;

import java.util.Collections;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.domain.service.user.UserEmailDuplicationCheckService;
import com.example.keirekipro.domain.shared.event.DomainEventPublisher;
import com.example.keirekipro.presentation.auth.dto.UserRegistrationRequest;
import com.example.keirekipro.shared.ErrorCollector;

import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * ユーザー新規登録ユースケース
 */
@Service
@RequiredArgsConstructor
public class UserRegistrationUseCase {

    private final UserRepository userRepository;

    private final PasswordEncoder passwordEncoder;

    private final DomainEventPublisher eventPublisher;

    private final UserEmailDuplicationCheckService userEmailDuplicationCheckService;

    /**
     * ユーザー新規登録ユースケースを実行する
     *
     * @param request リクエスト
     */
    @Transactional
    public void execute(UserRegistrationRequest request) {

        ErrorCollector errorCollector = new ErrorCollector();

        // メールアドレス値オブジェクトを作成
        Email email = Email.create(errorCollector, request.getEmail());

        // メールアドレス重複チェック
        userEmailDuplicationCheckService.execute(email);

        User user = User.create(
                errorCollector,
                Email.create(
                        errorCollector, request.getEmail()),
                passwordEncoder.encode(request.getPassword()),
                false,
                Collections.emptyMap(),
                null,
                request.getUsername());

        // 新規登録イベントを発行する
        user.register();

        // ユーザー登録
        userRepository.save(user);

        // 新規登録イベントをパブリッシュ
        user.getDomainEvents().forEach(eventPublisher::publish);
        user.clearDomainEvents();
    }
}
