package com.example.takeout.repository;

import com.example.takeout.entity.CartItem;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface CartItemRepository extends JpaRepository<CartItem, Long> {

    List<CartItem> findByUserIdOrderByIdAsc(Long userId);

    /** 查找同一用户、同一菜品、同一口味的条目（用于合并数量） */
    @Query("""
            select c from CartItem c
            where c.user.id = :userId and c.dish.id = :dishId
              and ((c.taste is null and :taste is null) or c.taste = :taste)
            """)
    Optional<CartItem> findSame(@Param("userId") Long userId,
                                @Param("dishId") Long dishId,
                                @Param("taste") String taste);

    long countByUserId(Long userId);

    @Modifying
    @Query("delete from CartItem c where c.user.id = :userId")
    void deleteByUserId(@Param("userId") Long userId);
}
