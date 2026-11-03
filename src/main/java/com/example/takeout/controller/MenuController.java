package com.example.takeout.controller;

import com.example.takeout.entity.Dish;
import com.example.takeout.entity.Review;
import com.example.takeout.security.CurrentUser;
import com.example.takeout.service.CartService;
import com.example.takeout.service.DishService;
import com.example.takeout.service.ReviewService;
import com.example.takeout.entity.User;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;

import java.util.List;

/**
 * 顾客端：菜单浏览、菜品详情（游客也可访问）
 */
@Controller
public class MenuController {

    private final DishService dishService;
    private final CartService cartService;
    private final ReviewService reviewService;
    private final CurrentUser currentUser;

    public MenuController(DishService dishService, CartService cartService,
                          ReviewService reviewService, CurrentUser currentUser) {
        this.dishService = dishService;
        this.cartService = cartService;
        this.reviewService = reviewService;
        this.currentUser = currentUser;
    }

    /** 首页 = 菜单 */
    @GetMapping({"/", "/menu"})
    public String menu(@RequestParam(required = false) Long categoryId,
                       @RequestParam(required = false) String keyword,
                       Model model, Authentication auth) {
        List<Dish> dishes = dishService.listOnSale(categoryId, keyword);

        model.addAttribute("dishes", dishes);
        model.addAttribute("categories", dishService.listCategories());
        model.addAttribute("activeCategoryId", categoryId);
        model.addAttribute("keyword", keyword == null ? "" : keyword);
        model.addAttribute("hotDishes", dishService.hotDishes());

        User user = currentUser.get(auth);
        if (user != null && !currentUser.isAdmin(auth)) {
            var cart = cartService.list(user);
            model.addAttribute("cartCount", cartService.count(cart));
        }
        return "menu";
    }

    /** 菜品详情页 */
    @GetMapping("/dish/{id}")
    public String detail(@PathVariable Long id, Model model, Authentication auth) {
        Dish dish = dishService.getDish(id);
        model.addAttribute("dish", dish);
        model.addAttribute("reviews", reviewService.latest());

        User user = currentUser.get(auth);
        if (user != null && !currentUser.isAdmin(auth)) {
            var cart = cartService.list(user);
            model.addAttribute("cartCount", cartService.count(cart));
        }
        return "dish-detail";
    }
}
