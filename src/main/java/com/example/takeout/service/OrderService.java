package com.example.takeout.service;

import com.example.takeout.entity.CartItem;
import com.example.takeout.entity.Order;
import com.example.takeout.entity.OrderItem;
import com.example.takeout.entity.OrderStatus;
import com.example.takeout.entity.User;
import com.example.takeout.exception.BusinessException;
import com.example.takeout.repository.CartItemRepository;
import com.example.takeout.repository.DishRepository;
import com.example.takeout.repository.OrderRepository;
import com.example.takeout.repository.UserRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.concurrent.ThreadLocalRandom;

@Service
public class OrderService {

    private static final DateTimeFormatter NO_FMT = DateTimeFormatter.ofPattern("yyyyMMddHHmmss");

    private final OrderRepository orderRepository;
    private final CartItemRepository cartItemRepository;
    private final DishRepository dishRepository;
    private final UserRepository userRepository;

    public OrderService(OrderRepository orderRepository,
                        CartItemRepository cartItemRepository,
                        DishRepository dishRepository,
                        UserRepository userRepository) {
        this.orderRepository = orderRepository;
        this.cartItemRepository = cartItemRepository;
        this.dishRepository = dishRepository;
        this.userRepository = userRepository;
    }

    /** 我的订单 */
    public List<Order> listMine(Long userId) {
        return orderRepository.findByUserIdOrderByCreatedAtDescIdDesc(userId);
    }

    /** 全部订单（管理端） */
    public List<Order> listAll() {
        return orderRepository.findAllByOrderByCreatedAtDescIdDesc();
    }

    public List<Order> listByStatus(OrderStatus status) {
        return orderRepository.findByStatusOrderByCreatedAtAsc(status);
    }

    public Order get(Long orderId) {
        return orderRepository.findById(orderId)
                .orElseThrow(() -> new BusinessException("订单不存在"));
    }

    /** 查询订单并校验归属，防止看别人的订单 */
    public Order getOwned(Long orderId, Long userId) {
        Order order = get(orderId);
        if (!order.getUserId().equals(userId)) {
            throw new BusinessException("无权查看该订单");
        }
        return order;
    }

    /**
     * 下单：把购物车内容转成订单，并校验库存
     * 注意：此时只锁库存不做扣减，扣减在支付成功后执行，避免占用库存
     */
    @Transactional
    public Order createFromCart(User user, String address, String phone, String remark) {
        if (address == null || address.isBlank()) {
            throw new BusinessException("请填写收货地址");
        }
        if (phone == null || phone.isBlank()) {
            throw new BusinessException("请填写联系电话");
        }

        List<CartItem> cart = cartItemRepository.findByUserIdOrderByIdAsc(user.getId());
        if (cart.isEmpty()) {
            throw new BusinessException("购物车是空的，先去挑点吃的吧");
        }

        Order order = new Order();
        order.setOrderNo(generateOrderNo());
        order.setUserId(user.getId());
        order.setAddress(address.trim());
        order.setPhone(phone.trim());
        order.setRemark(remark);
        order.setStatus(OrderStatus.CREATED);

        BigDecimal total = BigDecimal.ZERO;
        for (CartItem ci : cart) {
            if (!ci.getDish().isAvailable()) {
                throw new BusinessException("【" + ci.getDish().getName() + "】已售罄，请从购物车中移除");
            }
            OrderItem oi = new OrderItem();
            oi.setDishId(ci.getDish().getId());
            oi.setDishName(ci.getDish().getName());
            oi.setUnitPrice(ci.getDish().getPrice());
            oi.setQuantity(ci.getQuantity());
            oi.setTaste(ci.getTaste());
            order.addItem(oi);
            total = total.add(oi.getSubtotal());
        }
        order.setTotalAmount(total);

        Order saved = orderRepository.save(order);
        cartItemRepository.deleteByUserId(user.getId());
        return saved;
    }

    /**
     * 支付订单：
     * 1. 校验余额是否充足
     * 2. 原子扣减库存（库存不足则抛异常，事务回滚）
     * 3. 扣除余额
     * 4. 订单状态改为 PAID
     */
    @Transactional
    public Order pay(Long orderId, Long userId) {
        Order order = getOwned(orderId, userId);
        if (order.getStatus() != OrderStatus.CREATED) {
            throw new BusinessException("该订单当前状态为「" + order.getStatus().getLabel() + "」，无法支付");
        }

        User user = userRepository.findById(userId)
                .orElseThrow(() -> new BusinessException("用户不存在"));

        if (user.getBalance().compareTo(order.getTotalAmount()) < 0) {
            throw new BusinessException("余额不足，当前余额 ¥" + user.getBalance()
                    + "，订单需 ¥" + order.getTotalAmount() + "，请先充值");
        }

        // ① 原子抢占：把「待支付 → 已支付」做成一条条件更新，谁先执行成功谁就拿到这笔订单。
        //    并发场景下只有 1 个请求会返回 1，其余返回 0，直接拒绝，避免重复支付。
        int claimed = orderRepository.markPaidIfCreated(orderId, LocalDateTime.now());
        if (claimed == 0) {
            throw new BusinessException("该订单已被支付或状态已变更，请刷新后重试");
        }

        // ② 逐条扣减库存，任何一条失败都抛异常回滚（同时会把上面改的状态一起回滚）
        for (OrderItem item : order.getItems()) {
            int affected = dishRepository.deductStock(item.getDishId(), item.getQuantity());
            if (affected == 0) {
                throw new BusinessException("【" + item.getDishName() + "】库存不足，支付失败，请调整订单");
            }
        }

        // ③ 原子扣款：仅当余额充足时才扣，并返回受影响行数，防止并发扣成负数 / 多扣。
        int deducted = orderRepository.deductBalanceIfEnough(userId, order.getTotalAmount());
        if (deducted == 0) {
            throw new BusinessException("余额不足，支付失败");
        }

        // 状态已在 ① 中通过条件更新落库，这里重新读回最新快照返回给上层
        return orderRepository.findById(orderId).orElseThrow(() -> new BusinessException("订单不存在"));
    }

    /** 用户取消订单（仅待支付可取消） */
    @Transactional
    public void cancel(Long orderId, Long userId) {
        Order order = getOwned(orderId, userId);
        if (order.getStatus() != OrderStatus.CREATED) {
            throw new BusinessException("只能取消「待支付」的订单");
        }
        // 原子条件更新：只有仍是「待支付」时才取消，避免与支付并发时状态互相覆盖
        int affected = orderRepository.markCancelledIfCreated(orderId);
        if (affected == 0) {
            throw new BusinessException("该订单状态已变更（可能已支付），无法取消");
        }
    }

    // ---------- 管理端订单流转 ----------

    /**
     * 推进订单状态：PAID -> DELIVERING -> COMPLETED
     */
    @Transactional
    public void advance(Long orderId) {
        Order order = get(orderId);
        switch (order.getStatus()) {
            case PAID -> order.setStatus(OrderStatus.DELIVERING);
            case DELIVERING -> {
                order.setStatus(OrderStatus.COMPLETED);
                order.setCompletedAt(LocalDateTime.now());
            }
            default -> throw new BusinessException("当前状态「" + order.getStatus().getLabel() + "」无法继续流转");
        }
        orderRepository.save(order);
    }

    /** 管理端取消订单并退款、回补库存（仅未完成的订单可取消） */
    @Transactional
    public void adminCancel(Long orderId) {
        Order order = get(orderId);
        if (order.getStatus() == OrderStatus.COMPLETED || order.getStatus() == OrderStatus.CANCELLED) {
            throw new BusinessException("已完成或已取消的订单不能取消");
        }
        boolean wasPaid = order.getStatus() != OrderStatus.CREATED;

        // ① 原子抢占取消权：只有仍是「未终结」状态才能取消成功。
        //    并发/重复点击时只有 1 个请求返回 1，其余返回 0 直接拒绝，避免重复退款、重复回补库存。
        int claimed = orderRepository.markCancelledIfNotFinal(orderId);
        if (claimed == 0) {
            throw new BusinessException("该订单已完成或已取消，无法重复取消");
        }

        // ② 确认抢到取消权后，才执行退款 + 回补库存（已支付订单）
        if (wasPaid) {
            User user = userRepository.findById(order.getUserId())
                    .orElseThrow(() -> new BusinessException("下单用户不存在"));
            user.setBalance(user.getBalance().add(order.getTotalAmount()));
            userRepository.save(user);

            for (OrderItem item : order.getItems()) {
                dishRepository.restoreStock(item.getDishId(), item.getQuantity());
            }
        }
    }

    private String generateOrderNo() {
        return "T" + LocalDateTime.now().format(NO_FMT)
                + String.format("%04d", ThreadLocalRandom.current().nextInt(10000));
    }

    // ---------- 统计（管理端首页） ----------

    public BigDecimal revenue() {
        return orderRepository.sumAmountByStatus(OrderStatus.COMPLETED);
    }

    public BigDecimal totalSales() {
        return orderRepository.sumValidAmount();
    }

    public long countByStatus(OrderStatus status) {
        return orderRepository.countByStatus(status);
    }
}
