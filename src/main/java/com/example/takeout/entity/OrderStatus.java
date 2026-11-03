package com.example.takeout.entity;

/**
 * 订单状态
 *
 * CREATED    已创建（待支付）
 * PAID       已支付（待接单/已接单）
 * DELIVERING 配送中
 * COMPLETED  已完成
 * CANCELLED  已取消
 */
public enum OrderStatus {
    CREATED("待支付"),
    PAID("已支付"),
    DELIVERING("配送中"),
    COMPLETED("已完成"),
    CANCELLED("已取消");

    private final String label;

    OrderStatus(String label) {
        this.label = label;
    }

    public String getLabel() {
        return label;
    }
}
