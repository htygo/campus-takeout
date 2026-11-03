package com.example.takeout.security;

import com.example.takeout.entity.Role;
import com.example.takeout.entity.User;
import com.example.takeout.repository.UserRepository;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Component;

/**
 * 便捷读取“当前登录用户”的工具类。
 * 由于页面模板经常需要当前用户信息，统一在这里查库获取。
 */
@Component
public class CurrentUser {

    private final UserRepository userRepository;

    public CurrentUser(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    /** 获取当前登录用户；未登录返回 null */
    public User get(Authentication authentication) {
        if (authentication == null || !authentication.isAuthenticated()) {
            return null;
        }
        String name = authentication.getName();
        if (name == null || "anonymousUser".equals(name)) {
            return null;
        }
        return userRepository.findByUsername(name).orElse(null);
    }

    /** 当前登录用户是否为管理员 */
    public boolean isAdmin(Authentication authentication) {
        if (authentication == null) {
            return false;
        }
        return authentication.getAuthorities().stream()
                .anyMatch(a -> ("ROLE_" + Role.ADMIN.name()).equals(a.getAuthority()));
    }
}
