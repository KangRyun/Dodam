final class GuardianPinStatusDto {
  const GuardianPinStatusDto({
    required this.pinConfigured,
    required this.locked,
    required this.remainingAttempts,
    required this.retryAfterSeconds,
    required this.lockedUntil,
    required this.serverTime,
  });

  factory GuardianPinStatusDto.fromJson(Map<String, dynamic> json) =>
      GuardianPinStatusDto(
        pinConfigured: json['pinConfigured'] as bool,
        locked: json['locked'] as bool,
        remainingAttempts: _wholeInt(
          json['remainingAttempts'],
          'remainingAttempts',
        ),
        retryAfterSeconds: json['retryAfterSeconds'] == null
            ? null
            : _wholeInt(json['retryAfterSeconds'], 'retryAfterSeconds'),
        lockedUntil: _utcInstantOrNull(json['lockedUntil'], 'lockedUntil'),
        serverTime: _utcInstant(json['serverTime'], 'serverTime'),
      );

  final bool pinConfigured;
  final bool locked;
  final int remainingAttempts;
  final int? retryAfterSeconds;
  final DateTime? lockedUntil;
  final DateTime serverTime;
}

final class GuardianPinRequestDto {
  const GuardianPinRequestDto(this.pin);

  final String pin;

  Map<String, dynamic> toJson() => {'pin': pin};

  @override
  String toString() => 'GuardianPinRequestDto(pin: [REDACTED])';
}

final class GuardianPinChangeRequestDto {
  const GuardianPinChangeRequestDto({
    required this.currentPin,
    required this.newPin,
  });

  final String currentPin;
  final String newPin;

  Map<String, dynamic> toJson() => {'currentPin': currentPin, 'newPin': newPin};

  @override
  String toString() =>
      'GuardianPinChangeRequestDto(currentPin: [REDACTED], newPin: [REDACTED])';
}

int _wholeInt(Object? value, String field) {
  if (value is! num || !value.isFinite || value != value.roundToDouble()) {
    throw FormatException('$field must be a whole number.');
  }
  return value.toInt();
}

DateTime _utcInstant(Object? value, String field) {
  if (value is! String) throw FormatException('$field must be a UTC instant.');
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('$field must be a UTC instant.');
  }
  return parsed.toUtc();
}

DateTime? _utcInstantOrNull(Object? value, String field) =>
    value == null ? null : _utcInstant(value, field);
