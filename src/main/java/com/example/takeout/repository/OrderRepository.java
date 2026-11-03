package com.example.takeout.repository;

import com.example.takeout.entity.Order;
import com.example.takeout.entity.OrderStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.math.BigDecimal;
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
}
