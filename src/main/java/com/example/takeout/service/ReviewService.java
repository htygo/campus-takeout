package com.example.takeout.service;

import com.example.takeout.entity.Order;
import com.example.takeout.entity.OrderStatus;
import com.example.takeout.entity.Review;
import com.example.takeout.exception.BusinessException;
import com.example.takeout.repository.OrderRepository;
import com.example.takeout.repository.ReviewRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
public class ReviewService {

    private final ReviewRepository reviewRepository;
    private final OrderRepository orderRepository;

    public ReviewService(ReviewRepository reviewRepository, OrderRepository orderRepository) {
        this.reviewRepository = reviewRepository;
        this.orderRepository = orderRepository;
    }

    /** 对已完成的订单提交评价（每单只能评一次） */
    @Transactional
    public Review submit(Long orderId, Long userId, Integer rating, String content) {
        Order order = orderRepository.findById(orderId)
                .orElseThrow(() -> new BusinessException("订单不存在"));

        if (!order.getUserId().equals(userId)) {
            throw new BusinessException("无权评价该订单");
        }
        if (order.getStatus() != OrderStatus.COMPLETED) {
            throw new BusinessException("订单完成后才能评价");
        }
        if (reviewRepository.findByOrderId(orderId).isPresent()) {
            throw new BusinessException("该订单已经评价过了");
        }
        if (rating == null || rating < 1 || rating > 5) {
            throw new BusinessException("评分必须在 1~5 星之间");
        }

        Review review = new Review();
        review.setOrderId(orderId);
        review.setUserId(userId);
        review.setRating(rating);
        review.setContent(content);
        return reviewRepository.save(review);
    }

    public List<Review> latest() {
        return reviewRepository.findTop5ByOrderByCreatedAtDesc();
    }

    public List<Review> listMine(Long userId) {
        return reviewRepository.findByUserIdOrderByCreatedAtDesc(userId);
    }

    public boolean hasReviewed(Long orderId) {
        return reviewRepository.findByOrderId(orderId).isPresent();
    }
}
