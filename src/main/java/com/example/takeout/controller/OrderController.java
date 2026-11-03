package com.example.takeout.controller;

import com.example.takeout.entity.CartItem;
import com.example.takeout.entity.Order;
import com.example.takeout.entity.User;
import com.example.takeout.security.CurrentUser;
import com.example.takeout.service.CartService;
import com.example.takeout.service.OrderService;
import com.example.takeout.service.ReviewService;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

import java.util.List;

/**
 * 订单：结算、支付、取消、评价
 */
@Controller
public class OrderController {

    private final OrderService orderService;
    private final CartService cartService;
    private final ReviewService reviewService;
    private final CurrentUser currentUser;

    public OrderController(OrderService orderService, CartService cartService,
                           ReviewService reviewService, CurrentUser currentUser) {
        this.orderService = orderService;
        this.cartService = cartService;
        this.reviewService = reviewService;
        this.currentUser = currentUser;
    }

    /** 订单列表 */
    @GetMapping("/orders")
    public String list(Model model, Authentication auth) {
        User user = currentUser.get(auth);
        model.addAttribute("orders", orderService.listMine(user.getId()));
        model.addAttribute("cartCount", cartService.count(cartService.list(user)));
        return "orders";
    }

    /** 结算页：确认购物车内容、填地址 */
    @GetMapping("/orders/checkout")
    public String checkout(Model model, Authentication auth) {
        User user = currentUser.get(auth);
        List<CartItem> items = cartService.list(user);
        model.addAttribute("items", items);
        model.addAttribute("total", cartService.total(items));
        model.addAttribute("user", user);
        return "checkout";
    }

    /** 提交订单 */
    @PostMapping("/orders/create")
    public String create(@RequestParam String address,
                         @RequestParam String phone,
                         @RequestParam(required = false) String remark,
                         Authentication auth,
                         RedirectAttributes ra) {
        User user = currentUser.get(auth);
        Order order = orderService.createFromCart(user, address, phone, remark);
        ra.addFlashAttribute("success", "下单成功，请尽快完成支付");
        return "redirect:/orders/" + order.getId() + "/detail";
    }

    /** 订单详情 */
    @GetMapping("/orders/{id}/detail")
    public String detail(@PathVariable Long id, Model model, Authentication auth) {
        User user = currentUser.get(auth);
        Order order = orderService.getOwned(id, user.getId());
        model.addAttribute("order", order);
        model.addAttribute("user", user);
        model.addAttribute("hasReviewed", reviewService.hasReviewed(id));
        return "order-detail";
    }

    /** 支付 */
    @PostMapping("/orders/{id}/pay")
    public String pay(@PathVariable Long id, Authentication auth, RedirectAttributes ra) {
        User user = currentUser.get(auth);
        orderService.pay(id, user.getId());
        ra.addFlashAttribute("success", "支付成功，商家正在备餐");
        return "redirect:/orders/" + id + "/detail";
    }

    /** 取消订单 */
    @PostMapping("/orders/{id}/cancel")
    public String cancel(@PathVariable Long id, Authentication auth, RedirectAttributes ra) {
        User user = currentUser.get(auth);
        orderService.cancel(id, user.getId());
        ra.addFlashAttribute("success", "订单已取消");
        return "redirect:/orders/" + id + "/detail";
    }

    /** 提交评价 */
    @PostMapping("/orders/{id}/review")
    public String review(@PathVariable Long id,
                         @RequestParam Integer rating,
                         @RequestParam(required = false) String content,
                         Authentication auth,
                         RedirectAttributes ra) {
        User user = currentUser.get(auth);
        reviewService.submit(id, user.getId(), rating, content);
        ra.addFlashAttribute("success", "感谢您的评价！");
        return "redirect:/orders/" + id + "/detail";
    }
}
