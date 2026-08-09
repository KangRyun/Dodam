package com.ssafy.b209.expert.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

@Entity
@Table(name = "expert_profile_specialties")
class ExpertProfileSpecialty {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "expert_profile_id", nullable = false)
  private ExpertProfile expertProfile;

  @Column(name = "specialty_code", nullable = false, length = 50)
  private String specialtyCode;

  @Column(name = "specialty_name", nullable = false, length = 100)
  private String specialtyName;

  @Column(name = "display_order", nullable = false)
  private short displayOrder;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  protected ExpertProfileSpecialty() {}

  static ExpertProfileSpecialty snapshot(
      ExpertProfile profile, String specialtyCode, int displayOrder, LocalDateTime now) {
    ExpertProfileSpecialty specialty = new ExpertProfileSpecialty();
    specialty.expertProfile = profile;
    specialty.specialtyCode = specialtyCode;
    // 별도 전문 분야 사전이 확정되기 전까지 명칭 Snapshot은 계약의 코드 자체를 보존한다.
    specialty.specialtyName = specialtyCode;
    specialty.displayOrder = (short) displayOrder;
    specialty.createdAt = now;
    return specialty;
  }

  String getSpecialtyCode() {
    return specialtyCode;
  }

  void changeDisplayOrder(int displayOrder) {
    this.displayOrder = (short) displayOrder;
  }

  int getDisplayOrder() {
    return displayOrder;
  }
}
