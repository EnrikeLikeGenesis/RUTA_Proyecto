class AppUser {
  final String id;
  final String email;
  final String username;

  AppUser({
    required this.id,
    required this.email,
    required this.username,
  });

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id'] as String,
      email: map['email'] as String? ?? '',
      username: map['username'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'username': username,
    };
  }
}
