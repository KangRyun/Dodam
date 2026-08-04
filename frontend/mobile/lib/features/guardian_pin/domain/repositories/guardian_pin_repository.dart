import '../../data/dto/guardian_pin_dtos.dart';

abstract interface class GuardianPinRepository {
  Future<GuardianPinStatusDto> getStatus();

  Future<GuardianPinStatusDto> configure(String pin);

  Future<GuardianPinStatusDto> change({
    required String currentPin,
    required String newPin,
  });

  Future<GuardianPinStatusDto> reset();

  Future<GuardianPinStatusDto> verify(String pin);
}
