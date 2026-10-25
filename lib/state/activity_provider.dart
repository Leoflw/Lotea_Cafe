import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import '../models/coffee_lot.dart';
import '../models/favorite.dart';
import '../models/interest_request.dart';
import '../models/quote_request.dart';
import '../models/seller_profile.dart';
import '../repositories/coffee_lot_repository.dart';
import '../repositories/favorite_repository.dart';
import '../repositories/interest_request_repository.dart';
import '../repositories/quote_repository.dart';
import '../repositories/repo_exception.dart';
import '../repositories/seller_repository.dart';
import 'remote.dart';
import 'session_provider.dart';

/// Datos PROPIOS de la persona con sesión iniciada, escuchados en tiempo
/// real desde Firestore (conjuntos pequeños y filtrados por su UID):
///   comprador → solicitudes enviadas, cotizaciones, favoritos
///   vendedor  → su perfil, sus lotes, solicitudes y cotizaciones recibidas
/// No guarda el catálogo público (ese se consulta por páginas) ni es una
/// fuente de verdad: refleja Firestore y se vacía al cerrar sesión.
class ActivityProvider extends ChangeNotifier {
  final SellerRepository _sellers;
  final CoffeeLotRepository _lots;
  final InterestRequestRepository _requests;
  final FavoriteRepository _favorites;
  final QuoteRepository _quotes;

  ActivityProvider({
    required SellerRepository sellers,
    required CoffeeLotRepository lots,
    required InterestRequestRepository requests,
    required FavoriteRepository favorites,
    required QuoteRepository quotes,
  })  : _sellers = sellers,
        _lots = lots,
        _requests = requests,
        _favorites = favorites,
        _quotes = quotes;

  final List<StreamSubscription<dynamic>> _subs = [];
  String? _uid;
  UserRole? _rol;

  Remote<List<InterestRequest>> _solicitudes = const Remote.cargando();
  Remote<List<QuoteRequest>> _cotizaciones = const Remote.cargando();
  Remote<List<Favorite>> _favoritos = const Remote.cargando();
  Remote<List<CoffeeLot>> _lotesPropios = const Remote.cargando();
  Remote<SellerProfile?> _perfilVendedor = const Remote.cargando();
  final List<String> _descartes = [];

  Remote<List<InterestRequest>> get solicitudes => _solicitudes;
  Remote<List<QuoteRequest>> get cotizaciones => _cotizaciones;
  Remote<List<Favorite>> get favoritos => _favoritos;
  Remote<List<CoffeeLot>> get lotesPropios => _lotesPropios;
  Remote<SellerProfile?> get perfilVendedor => _perfilVendedor;

  /// Se llama desde ProxyProvider cada vez que cambia la sesión.
  void actualizarSesion(SessionProvider sesion) {
    final u = sesion.usuario;
    final uid = sesion.status == SessionStatus.listo ? u?.uid : null;
    final rol = sesion.status == SessionStatus.listo ? u?.rol : null;
    if (uid == _uid && rol == _rol) return;
    _detener();
    _uid = uid;
    _rol = rol;
    if (uid == null || rol == null) {
      notifyListeners();
      return;
    }
    _iniciar(uid, rol);
  }

  void _escuchar<T>(Stream<T> s, void Function(T) alDato, void Function(RepoException) alError) {
    _subs.add(s.listen((d) {
      alDato(d);
      notifyListeners();
    }, onError: (Object e) {
      alError(RepoException.desde(e));
      notifyListeners();
    }));
  }

  void _iniciar(String uid, UserRole rol) {
    if (rol == UserRole.comprador) {
      _escuchar<List<InterestRequest>>(_requests.observarEnviadas(uid),
          (d) => _solicitudes = Remote.listo(d), (e) => _solicitudes = Remote.error(e));
      _escuchar<List<QuoteRequest>>(_quotes.observarComoComprador(uid),
          (d) => _cotizaciones = Remote.listo(d), (e) => _cotizaciones = Remote.error(e));
      _escuchar<List<Favorite>>(_favorites.observar(uid),
          (d) => _favoritos = Remote.listo(d), (e) => _favoritos = Remote.error(e));
    } else {
      _escuchar<SellerProfile?>(_sellers.observar(uid),
          (d) => _perfilVendedor = Remote.listo(d), (e) => _perfilVendedor = Remote.error(e));
      _escuchar<List<CoffeeLot>>(_lots.observarDeVendedor(uid),
          (d) => _lotesPropios = Remote.listo(d), (e) => _lotesPropios = Remote.error(e));
      _escuchar<List<InterestRequest>>(_requests.observarRecibidas(uid),
          (d) => _solicitudes = Remote.listo(d), (e) => _solicitudes = Remote.error(e));
      _escuchar<List<QuoteRequest>>(_quotes.observarComoVendedor(uid),
          (d) => _cotizaciones = Remote.listo(d), (e) => _cotizaciones = Remote.error(e));
    }
  }

  void _detener() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _solicitudes = const Remote.cargando();
    _cotizaciones = const Remote.cargando();
    _favoritos = const Remote.cargando();
    _lotesPropios = const Remote.cargando();
    _perfilVendedor = const Remote.cargando();
    _descartes.clear();
  }

  /// Reinicia las suscripciones (botón "Reintentar").
  void reintentar() {
    final uid = _uid;
    final rol = _rol;
    if (uid == null || rol == null) return;
    _detener();
    notifyListeners();
    _iniciar(uid, rol);
  }

  // ---- Conveniencias de lectura (sin inventar datos mientras carga) ----

  List<InterestRequest> get listaSolicitudes => _solicitudes.listo ? _solicitudes.data : const [];
  List<QuoteRequest> get listaCotizaciones => _cotizaciones.listo ? _cotizaciones.data : const [];
  List<CoffeeLot> get listaLotesPropios => _lotesPropios.listo ? _lotesPropios.data : const [];

  List<InterestRequest> get conexiones => listaSolicitudes.where((s) => s.esConexion).toList();
  List<InterestRequest> get pendientes =>
      listaSolicitudes.where((s) => s.estado == EstadoSolicitud.pendiente).toList();

  /// Cotizaciones que esperan una acción del vendedor.
  int get cotizacionesPorResponder => listaCotizaciones
      .where((c) => QuoteStateMachine.requiereRespuestaDelVendedor(c.estado))
      .length;

  /// Ofertas que esperan respuesta del comprador (vigentes).
  int get ofertasPorResponder =>
      listaCotizaciones.where((c) => c.estadoEfectivo() == EstadoCotizacion.ofertaEnviada).length;

  int get lotesPublicados => listaLotesPropios.where((l) => l.publicado).length;
  int get lotesBorrador => listaLotesPropios.where((l) => !l.publicado).length;

  /// Ids de lotes sobre los que el comprador ya tiene una solicitud activa
  /// (pendiente o aceptada): no se vuelven a ofrecer en Descubrir.
  Set<String> get lotesYaSolicitados => listaSolicitudes
      .where((s) => s.estado != EstadoSolicitud.rechazada)
      .map((s) => s.coffeeLotId)
      .toSet();

  bool esFavorito(TipoFavorito tipo, String refId) =>
      _favoritos.listo && _favoritos.data.any((f) => f.tipo == tipo && f.refId == refId);

  List<String> idsFavoritos(TipoFavorito tipo) => _favoritos.listo
      ? _favoritos.data.where((f) => f.tipo == tipo).map((f) => f.refId).toList()
      : <String>[];

  /// ¿Existe ya una cotización activa del comprador para esta conexión?
  List<QuoteRequest> cotizacionesDeConexion(String interestRequestId) =>
      listaCotizaciones.where((c) => c.interestRequestId == interestRequestId).toList();

  // ---- Descartes (solo de esta sesión; no generan registro comercial) ----

  Set<String> get descartes => _descartes.toSet();

  void descartar(String lotId) {
    if (!_descartes.contains(lotId)) _descartes.add(lotId);
    notifyListeners();
  }

  String? deshacerUltimoDescarte() {
    if (_descartes.isEmpty) return null;
    final id = _descartes.removeLast();
    notifyListeners();
    return id;
  }

  @override
  void dispose() {
    _detener();
    super.dispose();
  }
}
