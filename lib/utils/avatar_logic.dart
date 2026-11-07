import '../models/app_user.dart';
import '../models/seller_profile.dart';

/// Decide qué fotografía va en el círculo de la cabecera de «Mi cuenta» y de
/// «Mi catálogo». Es lógica pura para poder probarla sin Firebase.
///
/// Reglas:
///  - Solo un VENDEDOR muestra foto, y es la foto principal de SU perfil de
///    marca (`sellerProfiles/{uid}.fotoPrincipal`). Hoy no existe una foto
///    personal independiente, así que un comprador siempre ve su inicial.
///  - El perfil debe pertenecer a la sesión (`perfil.usuarioId == usuario.uid`):
///    nunca se reutiliza la foto de otro documento.
///  - Una foto vacía o que no sea una URL remota no se usa; se muestra la inicial.
class AvatarLogic {
  AvatarLogic._();

  static String? fotoDeCuenta({required AppUser? usuario, required SellerProfile? perfil}) {
    if (usuario == null || perfil == null) return null;
    if (usuario.rol != UserRole.vendedor) return null;
    if (perfil.usuarioId != usuario.uid || perfil.id != usuario.uid) return null;
    return urlValida(perfil.fotoPrincipal);
  }

  /// Foto de la marca para la cabecera de «Mi catálogo» (el perfil ya es el
  /// del vendedor con sesión, porque ActivityProvider solo escucha el suyo).
  static String? fotoDeMarca(SellerProfile? perfil) => urlValida(perfil?.fotoPrincipal);

  static String? urlValida(String? url) {
    final t = url?.trim();
    if (t == null || t.isEmpty) return null;
    return (t.startsWith('https://') || t.startsWith('http://')) ? t : null;
  }

  /// Inicial en mayúscula del nombre, o `?` si no hay nombre.
  static String inicial(String? nombre) {
    final t = nombre?.trim() ?? '';
    return t.isEmpty ? '?' : t.substring(0, 1).toUpperCase();
  }
}
