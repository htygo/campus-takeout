package com.example.takeout.exception;

/**
 * 业务异常：抛出后由全局异常处理器转成友好提示页面
 */
public class BusinessException extends RuntimeException {

    public BusinessException(String message) {
        super(message);
    }
}
