enum UserRole {
  guardian('GUARDIAN'),
  expert('EXPERT'),
  admin('ADMIN');

  const UserRole(this.wireName);

  final String wireName;
}
