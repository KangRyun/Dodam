package com.ssafy.b209.drawing.repository;

import com.ssafy.b209.drawing.domain.DrawingActivityCategory;
import com.ssafy.b209.drawing.domain.DrawingType;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 그림 활동 시작 시 선택할 유형을 식별자로 조회하는 저장소다. */
public interface DrawingTypeRepository extends JpaRepository<DrawingType, Long> {

  /**
   * 그림 유형 목록을 분류와 활성 상태 조건으로 조회한다.
   *
   * <p>연령 조건은 아동의 만 나이를 계산한 Service가 적용한다.
   *
   * @param category 조회할 활동 분류, 전체 분류이면 {@code null}
   * @param activeOnly 활성 유형만 조회할지 여부
   * @return 기본 노출 순서와 식별자 순서가 적용된 그림 유형 목록
   */
  @Query(
      """
      select drawingType
        from DrawingType drawingType
       where (:category is null or drawingType.activityCategory = :category)
         and (:activeOnly = false or drawingType.active = true)
       order by drawingType.displayOrder, drawingType.id
      """)
  List<DrawingType> findForListing(
      @Param("category") DrawingActivityCategory category, @Param("activeOnly") boolean activeOnly);
}
