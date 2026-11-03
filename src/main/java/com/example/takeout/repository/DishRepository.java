package com.example.takeout.repository;

import com.example.takeout.entity.Dish;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface DishRepository extends JpaRepository<Dish, Long> {

    // ---------- 顾客端查询 ----------

    /** 所有上架且在售的菜品，按分类排序号、菜品 id 排序 */
    @Query("""
            select d from Dish d join d.category c
            where d.onSale = true
            order by c.sortOrder asc, d.id asc
            """)
    List<Dish> findOnSale();

    /** 按分类查询上架菜品 */
    @Query("""
            select d from Dish d join d.category c
            where d.onSale = true and c.id = :categoryId
            order by c.sortOrder asc, d.id asc
            """)
    List<Dish> findOnSaleByCategory(@Param("categoryId") Long categoryId);

    /** 按关键字搜索上架菜品（菜名或描述包含关键字） */
    @Query("""
            select d from Dish d join d.category c
            where d.onSale = true and (d.name like %:kw% or d.description like %:kw%)
            order by c.sortOrder asc, d.id asc
            """)
    List<Dish> searchOnSale(@Param("kw") String keyword);

    /** 热门菜品：按销量倒序取前 N 条 */
    List<Dish> findTop4ByOnSaleTrueOrderBySalesDesc();

    // ---------- 管理端查询 ----------

    List<Dish> findAllByOrderByCategorySortOrderAscIdAsc();

    List<Dish> findByCategoryId(Long categoryId);

    // ---------- 库存扣减（带条件更新，防止超卖） ----------

    /**
     * 原子扣减库存：只有当库存足够时才更新，返回受影响行数。
     * 影响行数为 0 说明库存不足，由 Service 抛出业务异常。
     */
    @Modifying
    @Query("""
            update Dish d set d.stock = d.stock - :qty, d.sales = d.sales + :qty
            where d.id = :id and d.stock >= :qty
            """)
    int deductStock(@Param("id") Long id, @Param("qty") int quantity);

    /** 回滚库存（取消订单时使用） */
    @Modifying
    @Query("""
            update Dish d set d.stock = d.stock + :qty, d.sales = d.sales - :qty
            where d.id = :id
            """)
    int restoreStock(@Param("id") Long id, @Param("qty") int quantity);
}
