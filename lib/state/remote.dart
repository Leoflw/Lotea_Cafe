import '../repositories/repo_exception.dart';

enum RemoteStatus { cargando, listo, error }

/// Estado de un dato remoto. Separa "todavía cargando", "cargó y puede estar
/// vacío" y "falló" — para que un error de conexión nunca se muestre como
/// una lista vacía.
class Remote<T> {
  final RemoteStatus status;
  final T? _data;
  final RepoException? error;

  const Remote.cargando() : status = RemoteStatus.cargando, _data = null, error = null;
  const Remote.listo(T data) : status = RemoteStatus.listo, _data = data, error = null;
  const Remote.error(RepoException this.error) : status = RemoteStatus.error, _data = null;

  bool get cargando => status == RemoteStatus.cargando;
  bool get listo => status == RemoteStatus.listo;
  bool get fallo => status == RemoteStatus.error;
  T get data => _data as T;
}
