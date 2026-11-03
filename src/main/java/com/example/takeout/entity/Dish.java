package com.example.takeout.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/**
 * 餐品
 */
@Entity
@Table(name = "dish")
public class Dish {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "name", nullable = false, length = 100)
    private String name;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "category_id", nullable = false)
    private Category category;

    @Column(name = "price", nullable = false, precision = 10, scale = 2)
    private BigDecimal price;

    @Column(name = "stock", nullable = false)
    private Integer stock = 0;

    @Column(name = "sales", nullable = false)
    private Integer sales = 0;

    @Column(name = "description", length = 500)
    private String description;

    /** 可选口味，逗号分隔，例如 "微辣,中辣,特辣" */
    @Column(name = "taste", length = 100)
    private String taste;

    /** 用 emoji 充当菜品图，避免依赖图片资源 */
    @Column(name = "image_emoji", length = 16)
    private String imageEmoji;

    @Column(name = "on_sale", nullable = false)
    private Boolean onSale = true;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private LocalDateTime createdAt;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public Category getCategory() { return category; }
    public void setCategory(Category category) { this.category = category; }

    public BigDecimal getPrice() { return price; }
    public void setPrice(BigDecimal price) { this.price = price; }

    public Integer getStock() { return stock; }
    public void setStock(Integer stock) { this.stock = stock; }

    public Integer getSales() { return sales; }
    public void setSales(Integer sales) { this.sales = sales; }

    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }

    public String getTaste() { return taste; }
    public void setTaste(String taste) { this.taste = taste; }

    public String getImageEmoji() { return imageEmoji; }
    public void setImageEmoji(String imageEmoji) { this.imageEmoji = imageEmoji; }

    public Boolean getOnSale() { return onSale; }
    public void setOnSale(Boolean onSale) { this.onSale = onSale; }

    public LocalDateTime getCreatedAt() { return createdAt; }

    /** 口味列表（供页面下拉框使用） */
    public List<String> getTasteList() {
        if (taste == null || taste.isBlank()) {
            return Collections.emptyList();
        }
        return Arrays.stream(taste.split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .toList();
    }

    /** 是否可购买：已上架且有库存 */
    public boolean isAvailable() {
        return Boolean.TRUE.equals(onSale) && stock != null && stock > 0;
    }
}
