package com.example.takeout.controller;

import com.example.takeout.entity.CartItem;
import com.example.takeout.entity.User;
import com.example.takeout.security.CurrentUser;
import com.example.takeout.service.CartService;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

import java.util.List;

/**
 * 购物车
 */
@Controller
public class CartController {

    private final CartService cartService;
    private final CurrentUser currentUser;

    public CartController(CartService cartService, CurrentUser currentUser) {
        this.cartService = cartService;
        this.currentUser = currentUser;
    }

    @GetMapping("/cart")
    public String cart(Model model, Authentication auth) {
        User user = currentUser.get(auth);
        List<CartItem> items = cartService.list(user);
        model.addAttribute("items", items);
        model.addAttribute("total", cartService.total(items));
        model.addAttribute("cartCount", cartService.count(items));
        return "cart";
    }

    @PostMapping("/cart/add")
    public String add(@RequestParam Long dishId,
                      @RequestParam(defaultValue = "1") Integer quantity,
                      @RequestParam(required = false) String taste,
                      Authentication auth,
                      RedirectAttributes ra) {
        User user = currentUser.get(auth);
        cartService.add(user, dishId, quantity, taste);
        ra.addFlashAttribute("success", "已加入购物车");
        return "redirect:/menu";
    }

    @PostMapping("/cart/update")
    public String update(@RequestParam Long itemId,
                         @RequestParam Integer quantity,
                         Authentication auth,
                         RedirectAttributes ra) {
        User user = currentUser.get(auth);
        cartService.updateQuantity(user, itemId, quantity);
        ra.addFlashAttribute("success", "购物车已更新");
        return "redirect:/cart";
    }

    @PostMapping("/cart/remove")
    public String remove(@RequestParam Long itemId, Authentication auth, RedirectAttributes ra) {
        User user = currentUser.get(auth);
        cartService.remove(user, itemId);
        ra.addFlashAttribute("success", "已从购物车移除");
        return "redirect:/cart";
    }

    @PostMapping("/cart/clear")
    public String clear(Authentication auth, RedirectAttributes ra) {
        User user = currentUser.get(auth);
        cartService.clear(user);
        ra.addFlashAttribute("success", "购物车已清空");
        return "redirect:/cart";
    }
}
