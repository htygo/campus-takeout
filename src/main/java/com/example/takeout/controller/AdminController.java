package com.example.takeout.controller;

import com.example.takeout.entity.OrderStatus;
import com.example.takeout.entity.Role;
import com.example.takeout.service.DishService;
import com.example.takeout.service.OrderService;
import com.example.takeout.service.ReviewService;
import com.example.takeout.service.UserService;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

import java.math.BigDecimal;

/**
 * 管理端：菜品管理、分类管理、订单处理、经营统计
 */
@Controller
public class AdminController {

    private final DishService dishService;
    private final OrderService orderService;
    private final UserService userService;
    private final ReviewService reviewService;

    public AdminController(DishService dishService, OrderService orderService,
                           UserService userService, ReviewService reviewService) {
        this.dishService = dishService;
        this.orderService = orderService;
        this.userService = userService;
        this.reviewService = reviewService;
    }

    /** 后台首页：统计看板 */
    @GetMapping("/admin")
    public String dashboard(Model model) {
        model.addAttribute("dishCount", dishService.listAll(null).size());
        model.addAttribute("orderCount", orderService.listAll().size());
        model.addAttribute("paidCount", orderService.countByStatus(OrderStatus.PAID));
        model.addAttribute("deliveringCount", orderService.countByStatus(OrderStatus.DELIVERING));
        model.addAttribute("completedCount", orderService.countByStatus(OrderStatus.COMPLETED));
        model.addAttribute("revenue", orderService.revenue());
        model.addAttribute("totalSales", orderService.totalSales());
        model.addAttribute("recentOrders", orderService.listAll().stream().limit(5).toList());
        return "admin/dashboard";
    }

    // ---------- 菜品管理 ----------

    @GetMapping("/admin/dishes")
    public String dishes(@RequestParam(required = false) Long categoryId, Model model) {
        model.addAttribute("dishes", dishService.listAll(categoryId));
        model.addAttribute("categories", dishService.listCategories());
        model.addAttribute("activeCategoryId", categoryId);
        return "admin/dishes";
    }

    @GetMapping("/admin/dishes/new")
    public String newDish(Model model) {
        model.addAttribute("categories", dishService.listCategories());
        return "admin/dish-form";
    }

    @GetMapping("/admin/dishes/{id}/edit")
    public String editDish(@PathVariable Long id, Model model) {
        model.addAttribute("dish", dishService.getDish(id));
        model.addAttribute("categories", dishService.listCategories());
        return "admin/dish-form";
    }

    @PostMapping("/admin/dishes/save")
    public String saveDish(@RequestParam(required = false) Long id,
                           @RequestParam String name,
                           @RequestParam Long categoryId,
                           @RequestParam BigDecimal price,
                           @RequestParam Integer stock,
                           @RequestParam(required = false) String description,
                           @RequestParam(required = false) String taste,
                           @RequestParam(required = false) String imageEmoji,
                           @RequestParam(required = false, defaultValue = "false") Boolean onSale,
                           RedirectAttributes ra) {
        dishService.saveDish(id, name, categoryId, price, stock, description, taste, imageEmoji, onSale);
        ra.addFlashAttribute("success", id == null ? "菜品已新增" : "菜品已更新");
        return "redirect:/admin/dishes";
    }

    @PostMapping("/admin/dishes/{id}/toggle")
    public String toggleDish(@PathVariable Long id, RedirectAttributes ra) {
        dishService.toggleOnSale(id);
        ra.addFlashAttribute("success", "上架状态已切换");
        return "redirect:/admin/dishes";
    }

    @PostMapping("/admin/dishes/{id}/restock")
    public String restock(@PathVariable Long id, @RequestParam int quantity, RedirectAttributes ra) {
        dishService.restock(id, quantity);
        ra.addFlashAttribute("success", "补货成功");
        return "redirect:/admin/dishes";
    }

    @PostMapping("/admin/dishes/{id}/delete")
    public String deleteDish(@PathVariable Long id, RedirectAttributes ra) {
        dishService.deleteDish(id);
        ra.addFlashAttribute("success", "菜品已删除");
        return "redirect:/admin/dishes";
    }

    // ---------- 分类管理 ----------

    @GetMapping("/admin/categories")
    public String categories(Model model) {
        model.addAttribute("categories", dishService.listCategories());
        return "admin/categories";
    }

    @PostMapping("/admin/categories/save")
    public String saveCategory(@RequestParam(required = false) Long id,
                               @RequestParam String name,
                               @RequestParam(required = false, defaultValue = "0") Integer sortOrder,
                               RedirectAttributes ra) {
        dishService.saveCategory(id, name, sortOrder);
        ra.addFlashAttribute("success", "分类已保存");
        return "redirect:/admin/categories";
    }

    @PostMapping("/admin/categories/{id}/delete")
    public String deleteCategory(@PathVariable Long id, RedirectAttributes ra) {
        dishService.deleteCategory(id);
        ra.addFlashAttribute("success", "分类已删除");
        return "redirect:/admin/categories";
    }

    // ---------- 订单管理 ----------

    @GetMapping("/admin/orders")
    public String orders(@RequestParam(required = false) OrderStatus status, Model model) {
        model.addAttribute(
                "orders",
                status == null ? orderService.listAll() : orderService.listByStatus(status)
        );
        model.addAttribute("statuses", OrderStatus.values());
        model.addAttribute("activeStatus", status);
        return "admin/orders";
    }

    @PostMapping("/admin/orders/{id}/advance")
    public String advance(@PathVariable Long id, RedirectAttributes ra) {
        orderService.advance(id);
        ra.addFlashAttribute("success", "订单状态已更新");
        return "redirect:/admin/orders";
    }

    @PostMapping("/admin/orders/{id}/cancel")
    public String cancelOrder(@PathVariable Long id, RedirectAttributes ra) {
        orderService.adminCancel(id);
        ra.addFlashAttribute("success", "订单已取消并退款");
        return "redirect:/admin/orders";
    }

    // ---------- 用户与评价 ----------

    @GetMapping("/admin/reviews")
    public String reviews(Model model) {
        model.addAttribute("reviews", reviewService.latest());
        return "admin/reviews";
    }
}
