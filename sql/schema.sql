-- ============================================================
-- 校园外卖点餐系统 数据库建表脚本
-- 数据库：MySQL 8.0
-- 编码：utf8mb4
-- ============================================================

DROP DATABASE IF EXISTS campus_takeout;
CREATE DATABASE campus_takeout DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE campus_takeout;

-- ------------------------------------------------------------
-- 1. 用户表（普通顾客 + 管理员，用 role 区分）
-- ------------------------------------------------------------
CREATE TABLE `app_user` (
  `id`          BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
  `username`    VARCHAR(50)  NOT NULL                COMMENT '登录用户名',
  `password`    VARCHAR(100) NOT NULL                COMMENT '密码（BCrypt 加密）',
  `nickname`    VARCHAR(50)  DEFAULT NULL            COMMENT '昵称',
  `phone`       VARCHAR(20)  DEFAULT NULL            COMMENT '手机号',
  `address`     VARCHAR(255) DEFAULT NULL            COMMENT '默认收货地址',
  `balance`     DECIMAL(10,2) NOT NULL DEFAULT 0.00  COMMENT '账户余额',
  `role`        VARCHAR(20)  NOT NULL DEFAULT 'USER' COMMENT '角色：USER / ADMIN',
  `enabled`     TINYINT(1)   NOT NULL DEFAULT 1      COMMENT '是否启用',
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user_username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户表';

-- ------------------------------------------------------------
-- 2. 餐品分类表
-- ------------------------------------------------------------
CREATE TABLE `category` (
  `id`         BIGINT      NOT NULL AUTO_INCREMENT,
  `name`       VARCHAR(50) NOT NULL COMMENT '分类名称',
  `sort_order` INT         NOT NULL DEFAULT 0 COMMENT '排序号，越小越靠前',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_category_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='餐品分类表';

-- ------------------------------------------------------------
-- 3. 餐品表
-- ------------------------------------------------------------
CREATE TABLE `dish` (
  `id`          BIGINT        NOT NULL AUTO_INCREMENT,
  `name`        VARCHAR(100)  NOT NULL              COMMENT '菜品名称',
  `category_id` BIGINT        NOT NULL              COMMENT '所属分类',
  `price`       DECIMAL(10,2) NOT NULL              COMMENT '单价',
  `stock`       INT           NOT NULL DEFAULT 0    COMMENT '库存份数',
  `sales`       INT           NOT NULL DEFAULT 0    COMMENT '累计销量',
  `description` VARCHAR(500)  DEFAULT NULL          COMMENT '菜品描述',
  `taste`       VARCHAR(100)  DEFAULT NULL          COMMENT '可选口味，逗号分隔',
  `image_emoji` VARCHAR(16)   DEFAULT NULL          COMMENT '图片占位符（emoji）',
  `on_sale`     TINYINT(1)    NOT NULL DEFAULT 1    COMMENT '是否上架',
  `created_at`  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_dish_category` (`category_id`),
  CONSTRAINT `fk_dish_category` FOREIGN KEY (`category_id`) REFERENCES `category` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='餐品表';

-- ------------------------------------------------------------
-- 4. 购物车表
-- ------------------------------------------------------------
CREATE TABLE `cart_item` (
  `id`       BIGINT       NOT NULL AUTO_INCREMENT,
  `user_id`  BIGINT       NOT NULL,
  `dish_id`  BIGINT       NOT NULL,
  `quantity` INT          NOT NULL DEFAULT 1 COMMENT '数量',
  `taste`    VARCHAR(50)  DEFAULT NULL       COMMENT '选择的口味',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_cart_user_dish_taste` (`user_id`, `dish_id`, `taste`),
  KEY `idx_cart_user` (`user_id`),
  CONSTRAINT `fk_cart_user` FOREIGN KEY (`user_id`) REFERENCES `app_user` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_cart_dish` FOREIGN KEY (`dish_id`) REFERENCES `dish` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='购物车表';

-- ------------------------------------------------------------
-- 5. 订单表
-- ------------------------------------------------------------
CREATE TABLE `orders` (
  `id`             BIGINT        NOT NULL AUTO_INCREMENT,
  `order_no`       VARCHAR(32)   NOT NULL COMMENT '订单号',
  `user_id`        BIGINT        NOT NULL,
  `total_amount`   DECIMAL(10,2) NOT NULL COMMENT '订单总金额',
  `status`         VARCHAR(20)   NOT NULL DEFAULT 'CREATED' COMMENT 'CREATED/PAID/DELIVERING/COMPLETED/CANCELLED',
  `address`        VARCHAR(255)  NOT NULL COMMENT '收货地址',
  `phone`          VARCHAR(20)   NOT NULL COMMENT '联系电话',
  `remark`         VARCHAR(255)  DEFAULT NULL COMMENT '备注',
  `created_at`     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `paid_at`        DATETIME      DEFAULT NULL,
  `completed_at`   DATETIME      DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_orders_no` (`order_no`),
  KEY `idx_orders_user` (`user_id`),
  KEY `idx_orders_status` (`status`),
  CONSTRAINT `fk_orders_user` FOREIGN KEY (`user_id`) REFERENCES `app_user` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单表';

-- ------------------------------------------------------------
-- 6. 订单明细表（下单时快照菜名与单价，避免菜品改价影响历史订单）
-- ------------------------------------------------------------
CREATE TABLE `order_item` (
  `id`         BIGINT        NOT NULL AUTO_INCREMENT,
  `order_id`   BIGINT        NOT NULL,
  `dish_id`    BIGINT        NOT NULL,
  `dish_name`  VARCHAR(100)  NOT NULL COMMENT '下单时菜名快照',
  `unit_price` DECIMAL(10,2) NOT NULL COMMENT '下单时单价快照',
  `quantity`   INT           NOT NULL,
  `taste`      VARCHAR(50)   DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_order_item_order` (`order_id`),
  CONSTRAINT `fk_order_item_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单明细表';

-- ------------------------------------------------------------
-- 7. 评价表
-- ------------------------------------------------------------
CREATE TABLE `review` (
  `id`         BIGINT       NOT NULL AUTO_INCREMENT,
  `order_id`   BIGINT       NOT NULL,
  `user_id`    BIGINT       NOT NULL,
  `rating`     INT          NOT NULL COMMENT '评分 1-5',
  `content`    VARCHAR(500) DEFAULT NULL COMMENT '评价内容',
  `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_review_order` (`order_id`),
  KEY `idx_review_user` (`user_id`),
  CONSTRAINT `fk_review_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单评价表';
