package com.example.keirekipro.usecase.auth;

import java.util.Collections;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.domain.service.user.UserEmailDuplicationCheckService;
import com.example.keirekipro.domain.shared.event.DomainEventPublisher;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.auth.command.UserRegistrationCommand;
import com.example.keirekipro.usecase.auth.store.UserTokenVersionStore;

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

    private final UserTokenVersionStore userTokenVersionStore;

    /**
     * ユーザー新規登録ユースケースを実行する
     *
     * @param command コマンド
     */
    @Transactional
    public void execute(UserRegistrationCommand command) {

        ErrorCollector errorCollector = new ErrorCollector();

        // メールアドレス値オブジェクトを作成
        Email email = Email.create(errorCollector, command.getEmail());

        // メールアドレス重複チェック
        userEmailDuplicationCheckService.execute(email);

        User user = User.create(
                errorCollector,
                Email.create(
                        errorCollector,
                        command.getEmail()),
                passwordEncoder.encode(command.getPassword()),
                Collections.emptyMap(),
                null,
                command.getUsername());

        // 新規登録イベントを発行する
        user.register();

        // ユーザー登録
        userRepository.save(user);

        // トークンバージョンを初期化
        userTokenVersionStore.initialize(user.getId());

        // 新規登録イベントをパブリッシュ
        user.getDomainEvents().forEach(eventPublisher::publish);
        user.clearDomainEvents();
    }
}
