package com.example.takeout.service;

import com.example.takeout.entity.CartItem;
import com.example.takeout.entity.Dish;
import com.example.takeout.entity.User;
import com.example.takeout.exception.BusinessException;
import com.example.takeout.repository.CartItemRepository;
import com.example.takeout.repository.DishRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;

@Service
public class CartService {

    private final CartItemRepository cartItemRepository;
    private final DishRepository dishRepository;

    public CartService(CartItemRepository cartItemRepository, DishRepository dishRepository) {
        this.cartItemRepository = cartItemRepository;
        this.dishRepository = dishRepository;
    }

    public List<CartItem> list(User user) {
        return cartItemRepository.findByUserIdOrderByIdAsc(user.getId());
    }

    /** 购物车商品总价 */
    public BigDecimal total(List<CartItem> items) {
        return items.stream()
                .map(CartItem::getSubtotal)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    /** 购物车商品总件数 */
    public int count(List<CartItem> items) {
        return items.stream().mapToInt(CartItem::getQuantity).sum();
    }

    /**
     * 加入购物车：同一菜品同一口味则累加数量，否则新增一行
     */
    @Transactional
    public void add(User user, Long dishId, Integer quantity, String taste) {
        int qty = (quantity == null || quantity <= 0) ? 1 : quantity;
        Dish dish = dishRepository.findById(dishId)
                .orElseThrow(() -> new BusinessException("菜品不存在"));

        if (!dish.isAvailable()) {
            throw new BusinessException("【" + dish.getName() + "】已售罄或已下架");
        }

        String normalizedTaste = (taste == null || taste.isBlank()) ? null : taste.trim();

        CartItem item = cartItemRepository
                .findSame(user.getId(), dishId, normalizedTaste)
                .orElseGet(() -> {
                    CartItem c = new CartItem();
                    c.setUser(user);
                    c.setDish(dish);
                    c.setQuantity(0);
                    c.setTaste(normalizedTaste);
                    return c;
                });

        int newQty = item.getQuantity() + qty;
        if (newQty > dish.getStock()) {
            throw new BusinessException("【" + dish.getName() + "】库存不足，当前仅剩 " + dish.getStock() + " 份");
        }
        item.setQuantity(newQty);
        cartItemRepository.save(item);
    }

    /** 修改数量（传 0 表示删除） */
    @Transactional
    public void updateQuantity(User user, Long itemId, Integer quantity) {
        CartItem item = getOwnedItem(user, itemId);
        if (quantity == null || quantity <= 0) {
            cartItemRepository.delete(item);
            return;
        }
        if (quantity > item.getDish().getStock()) {
            throw new BusinessException("库存不足，最多可购买 " + item.getDish().getStock() + " 份");
        }
        item.setQuantity(quantity);
        cartItemRepository.save(item);
    }

    @Transactional
    public void remove(User user, Long itemId) {
        cartItemRepository.delete(getOwnedItem(user, itemId));
    }

    @Transactional
    public void clear(User user) {
        cartItemRepository.deleteByUserId(user.getId());
    }

    /** 校验购物车条目属于当前用户，防止越权操作别人的购物车 */
    private CartItem getOwnedItem(User user, Long itemId) {
        CartItem item = cartItemRepository.findById(itemId)
                .orElseThrow(() -> new BusinessException("购物车条目不存在"));
        if (!item.getUser().getId().equals(user.getId())) {
            throw new BusinessException("无权操作该购物车条目");
        }
        return item;
    }
}
