class AuthResponse {
  final String token;
  final String userId;
  final String displayName;
  final bool isAdmin;

  AuthResponse({
    required this.token,
    required this.userId,
    required this.displayName,
    required this.isAdmin,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
    token: json['token'],
    userId: json['user_id'],
    displayName: json['display_name'],
    isAdmin: json['is_admin'],
  );
}
