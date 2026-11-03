package com.example.takeout.repository;

import com.example.takeout.entity.Review;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface ReviewRepository extends JpaRepository<Review, Long> {

    Optional<Review> findByOrderId(Long orderId);

    List<Review> findByUserIdOrderByCreatedAtDesc(Long userId);

    List<Review> findTop5ByOrderByCreatedAtDesc();

    long countByOrderId(Long orderId);
}
