package com.example.takeout.controller;

import com.example.takeout.entity.User;
import com.example.takeout.security.CurrentUser;
import com.example.takeout.service.UserService;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

import java.math.BigDecimal;

/**
 * 登录 / 注册 / 个人中心
 */
@Controller
public class AuthController {

    private final UserService userService;
    private final CurrentUser currentUser;

    public AuthController(UserService userService, CurrentUser currentUser) {
        this.userService = userService;
        this.currentUser = currentUser;
    }

    @GetMapping("/login")
    public String loginPage() {
        return "login";
    }

    @GetMapping("/register")
    public String registerPage() {
        return "register";
    }

    @PostMapping("/register")
    public String register(@RequestParam String username,
                           @RequestParam String password,
                           @RequestParam(required = false) String nickname,
                           @RequestParam(required = false) String phone,
                           @RequestParam(required = false) String address,
                           RedirectAttributes ra) {
        userService.register(username, password, nickname, phone, address);
        ra.addFlashAttribute("success", "注册成功，请登录");
        return "redirect:/login";
    }

    /** 个人中心 */
    @GetMapping("/me")
    public String profile(Model model, Authentication auth) {
        User user = currentUser.get(auth);
        model.addAttribute("user", user);
        return "profile";
    }

    @PostMapping("/me/update")
    public String updateProfile(@RequestParam(required = false) String nickname,
                                @RequestParam(required = false) String phone,
                                @RequestParam(required = false) String address,
                                Authentication auth,
                                RedirectAttributes ra) {
        User user = currentUser.get(auth);
        userService.updateProfile(user.getId(), nickname, phone, address);
        ra.addFlashAttribute("success", "资料已更新");
        return "redirect:/me";
    }

    @PostMapping("/me/password")
    public String changePassword(@RequestParam String oldPassword,
                                 @RequestParam String newPassword,
                                 Authentication auth,
                                 RedirectAttributes ra) {
        User user = currentUser.get(auth);
        userService.changePassword(user.getId(), oldPassword, newPassword);
        ra.addFlashAttribute("success", "密码已修改");
        return "redirect:/me";
    }

    @PostMapping("/me/recharge")
    public String recharge(@RequestParam BigDecimal amount,
                           Authentication auth,
                           RedirectAttributes ra) {
        User user = currentUser.get(auth);
        BigDecimal balance = userService.recharge(user.getId(), amount);
        ra.addFlashAttribute("success", "充值成功，当前余额 ¥" + balance);
        return "redirect:/me";
    }
}
