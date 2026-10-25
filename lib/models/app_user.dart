enum UserRole { comprador, vendedor }

extension UserRoleX on UserRole {
  String get label => this == UserRole.vendedor ? 'Vendedor' : 'Comprador';
}

class AppUser {
  final String uid;
  final String email;
  final String nombre;
  final UserRole rol;
  final String? ubicacion;

  AppUser({
    required this.uid,
    required this.email,
    required this.nombre,
    required this.rol,
    this.ubicacion,
  });
}
