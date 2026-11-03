package com.example.takeout.service;

import com.example.takeout.entity.Role;
import com.example.takeout.entity.User;
import com.example.takeout.exception.BusinessException;
import com.example.takeout.repository.UserRepository;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;

@Service
public class UserService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    public UserService(UserRepository userRepository, PasswordEncoder passwordEncoder) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
    }

    /** 按用户名查询 */
    public User findByUsername(String username) {
        return userRepository.findByUsername(username)
                .orElseThrow(() -> new BusinessException("用户不存在：" + username));
    }

    public User findById(Long id) {
        return userRepository.findById(id)
                .orElseThrow(() -> new BusinessException("用户不存在"));
    }

    /**
     * 注册新顾客
     */
    @Transactional
    public User register(String username, String rawPassword, String nickname,
                         String phone, String address) {
        if (username == null || username.isBlank()) {
            throw new BusinessException("用户名不能为空");
        }
        if (rawPassword == null || rawPassword.length() < 6) {
            throw new BusinessException("密码长度不能少于 6 位");
        }
        if (userRepository.existsByUsername(username)) {
            throw new BusinessException("用户名已被占用，请换一个");
        }

        User user = new User();
        user.setUsername(username.trim());
        user.setPassword(passwordEncoder.encode(rawPassword));
        user.setNickname((nickname == null || nickname.isBlank()) ? username.trim() : nickname.trim());
        user.setPhone(phone);
        user.setAddress(address);
        user.setBalance(BigDecimal.ZERO);
        user.setRole(Role.USER);
        user.setEnabled(true);
        return userRepository.save(user);
    }

    /** 更新个人资料 */
    @Transactional
    public void updateProfile(Long userId, String nickname, String phone, String address) {
        User user = findById(userId);
        user.setNickname(nickname);
        user.setPhone(phone);
        user.setAddress(address);
        userRepository.save(user);
    }

    /** 修改密码 */
    @Transactional
    public void changePassword(Long userId, String oldPassword, String newPassword) {
        User user = findById(userId);
        if (!passwordEncoder.matches(oldPassword, user.getPassword())) {
            throw new BusinessException("原密码不正确");
        }
        if (newPassword == null || newPassword.length() < 6) {
            throw new BusinessException("新密码长度不能少于 6 位");
        }
        user.setPassword(passwordEncoder.encode(newPassword));
        userRepository.save(user);
    }

    /** 充值（返回充值后余额） */
    @Transactional
    public BigDecimal recharge(Long userId, BigDecimal amount) {
        if (amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new BusinessException("充值金额必须大于 0");
        }
        User user = findById(userId);
        user.setBalance(user.getBalance().add(amount));
        userRepository.save(user);
        return user.getBalance();
    }
}
