import 'dart:async';

import 'package:flutter/material.dart';

import 'navigation.dart';
import 'push_gateway.dart';

enum PushRuta { chat, cotizacion }

/// Destino de una notificación ya validado en su forma.
class PushDestino {
  final PushRuta ruta;
  final String id;
  const PushDestino(this.ruta, this.id);

  static final _id = RegExp(r'^[A-Za-z0-9_-]{1,300}$');

  /// null si el mensaje no trae una ruta conocida y un id con forma válida.
  static PushDestino? desde(PushMensaje m) {
    final id = m.destinoId;
    if (id == null || !_id.hasMatch(id)) return null;
    switch (m.ruta) {
      case 'chat':
        return PushDestino(PushRuta.chat, id);
      case 'cotizacion':
        return PushDestino(PushRuta.cotizacion, id);
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is PushDestino && other.ruta == ruta && other.id == id;

  @override
  int get hashCode => Object.hash(ruta, id);
}

/// Devuelve la pantalla de destino SOLO si la persona `uid` tiene acceso al recurso
/// (existe y participa); null si no está disponible.
typedef ResolverDestino = Future<Widget?> Function(PushDestino destino, String uid);

/// Gestiona lo que ocurre al recibir o tocar una notificación:
///  - primer plano (`onMessage`): aviso dentro de la app con texto genérico propio
///    (Android no muestra notificación del sistema con la app abierta);
///  - toque desde segundo plano (`onMessageOpenedApp`) o con la app cerrada
///    (`getInitialMessage`): abre `ChatScreen` o `QuoteDetailScreen`.
///
/// La navegación pedida se CONSERVA hasta que sea seguro hacerla (sesión
/// resuelta, perfil cargado y onboarding terminado) y se descarta si no hay
/// sesión. Siempre se comprueba el acceso al recurso antes de abrirlo. Usa el
/// `navigatorKey` existente de `navigation.dart` (no crea otro).
class PushCoordinator {
  final PushGateway _gateway;
  final ResolverDestino _resolver;
  final GlobalKey<NavigatorState> _navegador;

  PushCoordinator({
    required PushGateway gateway,
    required ResolverDestino resolver,
    GlobalKey<NavigatorState>? navegador,
  })  : _gateway = gateway,
        _resolver = resolver,
        _navegador = navegador ?? navigatorKey;

  final List<StreamSubscription<PushMensaje>> _subs = [];
  final List<String> _vistos = []; // ids de mensajes ya tratados (evita abrir dos veces el mismo)
  PushDestino? _pendiente;
  bool _navegando = false;
  bool _iniciado = false;

  String? _uid;
  bool _lista = false;
  bool _sinSesion = false;

  /// Id del chat que se está viendo ahora mismo (lo fija `ChatScreen`): ahí no se
  /// muestra aviso en primer plano, porque el mensaje ya aparece en pantalla.
  String? chatAbierto;

  /// Destino a la espera de poder navegar (para pruebas).
  @visibleForTesting
  PushDestino? get pendiente => _pendiente;

  void iniciar() {
    if (_iniciado) return;
    _iniciado = true;
    _subs.add(_gateway.enPrimerPlano.listen(_alRecibirEnPrimerPlano, onError: (Object _) {}));
    _subs.add(_gateway.alAbrirNotificacion.listen(_alAbrir, onError: (Object _) {}));
    unawaited(_cargarMensajeInicial());
  }

  Future<void> _cargarMensajeInicial() async {
    try {
      final m = await _gateway.mensajeInicial;
      if (m != null) _alAbrir(m);
    } catch (_) {
      // Sin mensaje inicial: la app abre con normalidad.
    }
  }

  /// Lo llama el puente de sesión. [lista] = sesión resuelta, perfil cargado y onboarding hecho.
  void actualizarSesion({required String? uid, required bool lista, required bool sinSesion}) {
    _uid = uid;
    _lista = lista;
    _sinSesion = sinSesion;
    unawaited(_intentar());
  }

  bool _yaVisto(PushMensaje m) {
    final id = m.id;
    if (id == null) return false;
    if (_vistos.contains(id)) return true;
    _vistos.add(id);
    if (_vistos.length > 20) _vistos.removeAt(0);
    return false;
  }

  void _alAbrir(PushMensaje m) {
    if (_yaVisto(m)) return;
    final destino = PushDestino.desde(m);
    if (destino == null) return;
    _pendiente = destino;
    unawaited(_intentar());
  }

  Future<void> _intentar() async {
    final destino = _pendiente;
    if (destino == null || _navegando) return;
    if (_sinSesion) {
      _pendiente = null; // sesión resuelta sin usuario: no se navega hacia el contenido de nadie
      return;
    }
    final uid = _uid;
    if (!_lista || uid == null) return; // la sesión aún se resuelve: se conserva
    final nav = _navegador.currentState;
    if (nav == null) return;
    if (destino.ruta == PushRuta.chat && destino.id == chatAbierto) {
      _pendiente = null;
      return;
    }

    _pendiente = null;
    _navegando = true;
    try {
      final pantalla = await _resolver(destino, uid).timeout(const Duration(seconds: 10));
      if (_uid != uid) return; // cambió la cuenta mientras se resolvía
      final actual = _navegador.currentState;
      if (actual == null) return;
      if (pantalla == null) {
        _mostrarAviso('Este contenido ya no está disponible.');
        return;
      }
      unawaited(actual.push(MaterialPageRoute<void>(builder: (_) => pantalla)));
    } catch (_) {
      _mostrarAviso('No se pudo abrir la notificación. Inténtalo de nuevo.');
    } finally {
      _navegando = false;
      // Si mientras se resolvía este destino llegó otro (o el usuario tocó «Ver»),
      // `_intentar` lo dejó pendiente porque `_navegando` estaba activo: se retoma
      // ahora. Antes quedaba sin procesar hasta el siguiente cambio de sesión.
      if (_pendiente != null) unawaited(_intentar());
    }
  }

  void _alRecibirEnPrimerPlano(PushMensaje m) {
    final destino = PushDestino.desde(m);
    if (destino == null) return;
    if (destino.ruta == PushRuta.chat && destino.id == chatAbierto) return;
    final texto = destino.ruta == PushRuta.chat ? 'Tienes un nuevo mensaje en Lotea Café' : 'Tienes novedades en una cotización';
    final ctx = _navegador.currentContext;
    if (ctx == null) return;
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(texto),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Ver',
          onPressed: () {
            _pendiente = destino;
            unawaited(_intentar());
          },
        ),
      ));
  }

  void _mostrarAviso(String texto) {
    final ctx = _navegador.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.maybeOf(ctx)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }
}
