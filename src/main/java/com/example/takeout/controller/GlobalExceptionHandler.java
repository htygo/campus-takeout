package com.example.takeout.controller;

import com.example.takeout.exception.BusinessException;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.servlet.ModelAndView;

/**
 * 全局异常处理：把业务异常渲染成友好的提示页面，而不是 500 白页。
 *
 * 注意：这里显式构造 ModelAndView 并以 text/html 渲染，
 * 避免 Spring 走内容协商把 JSON 当 HTML 输出而抛 HttpMessageNotWritableException。
 */
@ControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(BusinessException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ModelAndView handleBusiness(BusinessException ex) {
        ModelAndView mv = new ModelAndView("error");
        mv.addObject("message", ex.getMessage());
        return mv;
    }
}
