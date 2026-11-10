package com.example.takeout.repository;

import com.example.takeout.entity.Order;
import com.example.takeout.entity.User;
import com.example.takeout.entity.OrderStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

public interface OrderRepository extends JpaRepository<Order, Long> {

    List<Order> findByUserIdOrderByCreatedAtDescIdDesc(Long userId);

    List<Order> findAllByOrderByCreatedAtDescIdDesc();

    List<Order> findByStatusOrderByCreatedAtAsc(OrderStatus status);

    long countByStatus(OrderStatus status);

    // ---------- 管理端统计 ----------

    /** 统计某状态订单的总金额（已完成订单即为营业额） */
    @Query("select coalesce(sum(o.totalAmount), 0) from Order o where o.status = :status")
    BigDecimal sumAmountByStatus(@Param("status") OrderStatus status);

    /** 全部订单总金额（不含已取消） */
    @Query("select coalesce(sum(o.totalAmount), 0) from Order o where o.status <> 'CANCELLED'")
    BigDecimal sumValidAmount();

    long countByUserId(Long userId);

    // ---------- 并发 / 幂等控制 ----------

    /**
     * 原子地把订单从「待支付」改成「已支付」。
     * 只有当前状态仍是 CREATED 时才会更新成功，返回受影响行数：
     *  - 返回 1：本次抢到了这笔订单，可以继续后续操作；
     *  - 返回 0：已被别的请求抢先支付（或不是待支付状态），应直接拒绝。
     * 这是「先检查后更新」的原子替代，防止同一订单被并发重复支付。
     */
    @Modifying
    @Query("update Order o set o.status = com.example.takeout.entity.OrderStatus.PAID, " +
           "o.paidAt = :paidAt where o.id = :id and o.status = com.example.takeout.entity.OrderStatus.CREATED")
    int markPaidIfCreated(@Param("id") Long id, @Param("paidAt") LocalDateTime paidAt);

    /**
     * 原子地扣减用户余额：仅当余额充足时才扣，返回受影响行数。
     * 返回 0 表示余额不足（或用户不存在），应回滚。
     * 把「查余额 → 判断 → 扣款」合成一条语句，避免并发下扣成负数。
     */
    @Modifying
    @Query("update User u set u.balance = u.balance - :amount " +
           "where u.id = :userId and u.balance >= :amount")
    int deductBalanceIfEnough(@Param("userId") Long userId, @Param("amount") BigDecimal amount);

    /**
     * 原子地把「待支付」订单取消。仅当当前状态仍是 CREATED 时更新成功。
     * 用于用户自助取消，避免与支付并发时状态互相覆盖。
     */
    @Modifying
    @Query("update Order o set o.status = com.example.takeout.entity.OrderStatus.CANCELLED " +
           "where o.id = :id and o.status = com.example.takeout.entity.OrderStatus.CREATED")
    int markCancelledIfCreated(@Param("id") Long id);

    /**
     * 原子地把「未终结」订单取消：只有 status 属于 CREATED / PAID / DELIVERING 时才更新成功。
     * 用于管理端取消，必须在执行退款/回补库存之前调用：
     *  - 返回 1：本次抢到这笔取消操作，继续退款、回补库存；
     *  - 返回 0：订单已完成或已取消（被别的请求抢先），应直接拒绝，避免重复退款。
     */
    @Modifying
    @Query("update Order o set o.status = com.example.takeout.entity.OrderStatus.CANCELLED " +
           "where o.id = :id and o.status in (com.example.takeout.entity.OrderStatus.CREATED, " +
           "com.example.takeout.entity.OrderStatus.PAID, com.example.takeout.entity.OrderStatus.DELIVERING)")
    int markCancelledIfNotFinal(@Param("id") Long id);
}
