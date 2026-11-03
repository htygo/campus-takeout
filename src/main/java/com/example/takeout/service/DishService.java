package com.example.takeout.service;

import com.example.takeout.entity.Category;
import com.example.takeout.entity.Dish;
import com.example.takeout.exception.BusinessException;
import com.example.takeout.repository.CategoryRepository;
import com.example.takeout.repository.DishRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;

@Service
public class DishService {

    private final DishRepository dishRepository;
    private final CategoryRepository categoryRepository;

    public DishService(DishRepository dishRepository, CategoryRepository categoryRepository) {
        this.dishRepository = dishRepository;
        this.categoryRepository = categoryRepository;
    }

    // ---------- 分类 ----------

    public List<Category> listCategories() {
        return categoryRepository.findAllByOrderBySortOrderAscIdAsc();
    }

    public Category getCategory(Long id) {
        return categoryRepository.findById(id)
                .orElseThrow(() -> new BusinessException("分类不存在"));
    }

    @Transactional
    public Category saveCategory(Long id, String name, Integer sortOrder) {
        if (name == null || name.isBlank()) {
            throw new BusinessException("分类名称不能为空");
        }
        Category category = (id == null) ? new Category() : getCategory(id);
        category.setName(name.trim());
        category.setSortOrder(sortOrder == null ? 0 : sortOrder);
        return categoryRepository.save(category);
    }

    @Transactional
    public void deleteCategory(Long id) {
        if (!dishRepository.findByCategoryId(id).isEmpty()) {
            throw new BusinessException("该分类下还有菜品，无法删除");
        }
        categoryRepository.deleteById(id);
    }

    // ---------- 菜品（顾客端） ----------

    public List<Dish> listOnSale(Long categoryId, String keyword) {
        if (keyword != null && !keyword.isBlank()) {
            return dishRepository.searchOnSale(keyword.trim());
        }
        if (categoryId != null) {
            return dishRepository.findOnSaleByCategory(categoryId);
        }
        return dishRepository.findOnSale();
    }

    public List<Dish> hotDishes() {
        return dishRepository.findTop4ByOnSaleTrueOrderBySalesDesc();
    }

    public Dish getDish(Long id) {
        return dishRepository.findById(id)
                .orElseThrow(() -> new BusinessException("菜品不存在"));
    }

    // ---------- 菜品（管理端） ----------

    public List<Dish> listAll(Long categoryId) {
        if (categoryId != null) {
            return dishRepository.findByCategoryId(categoryId);
        }
        return dishRepository.findAllByOrderByCategorySortOrderAscIdAsc();
    }

    @Transactional
    public Dish saveDish(Long id, String name, Long categoryId, BigDecimal price,
                         Integer stock, String description, String taste,
                         String imageEmoji, Boolean onSale) {
        if (name == null || name.isBlank()) {
            throw new BusinessException("菜品名称不能为空");
        }
        if (price == null || price.compareTo(BigDecimal.ZERO) <= 0) {
            throw new BusinessException("价格必须大于 0");
        }
        if (stock == null || stock < 0) {
            throw new BusinessException("库存不能为负数");
        }

        Dish dish = (id == null) ? new Dish() : getDish(id);
        dish.setName(name.trim());
        dish.setCategory(getCategory(categoryId));
        dish.setPrice(price);
        dish.setStock(stock);
        dish.setDescription(description);
        dish.setTaste(taste);
        dish.setImageEmoji((imageEmoji == null || imageEmoji.isBlank()) ? "🍽️" : imageEmoji.trim());
        dish.setOnSale(onSale != null && onSale);
        return dishRepository.save(dish);
    }

    /** 上架 / 下架切换 */
    @Transactional
    public void toggleOnSale(Long id) {
        Dish dish = getDish(id);
        dish.setOnSale(!Boolean.TRUE.equals(dish.getOnSale()));
        dishRepository.save(dish);
    }

    @Transactional
    public void deleteDish(Long id) {
        dishRepository.deleteById(id);
    }

    /** 补货 */
    @Transactional
    public void restock(Long id, int quantity) {
        if (quantity <= 0) {
            throw new BusinessException("补货数量必须大于 0");
        }
        Dish dish = getDish(id);
        dish.setStock(dish.getStock() + quantity);
        dishRepository.save(dish);
    }
}
