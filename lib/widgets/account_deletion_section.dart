import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../repositories/account_deletion_client.dart';
import '../repositories/repo_exception.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';

/// Reautentica y envía la operación al Worker; devuelve lo que éste confirmó o lanza [RepoException].
typedef OperacionConContrasena = Future<EstadoEliminacionCuenta> Function(String password);

/// Sección «Eliminar cuenta» de «Mi cuenta». Según el estado REAL de la cuenta (`users/{uid}`, que
/// llega por Firestore y por eso sobrevive a cerrar y volver a abrir la sesión):
///  - activa: explica el proceso y ofrece solicitar (con confirmación explícita y contraseña);
///  - eliminación pendiente: tarjeta con la fecha programada y «Cancelar solicitud» (con contraseña).
///    El botón NO depende de la hora del teléfono: solo el servidor decide si el plazo sigue vigente
///    (responde `plazo_vencido` y la app muestra ese mensaje); un reloj adelantado no puede ocultarlo;
///  - eliminando: el borrado definitivo ya comenzó; solo informa (sin cancelar ni acciones comerciales);
///  - estado desconocido: aviso conservador (operaciones bloqueadas).
class AccountDeletionSection extends StatelessWidget {
  final AppUser usuario;
  final OperacionConContrasena onSolicitar;
  final OperacionConContrasena onCancelar;

  const AccountDeletionSection({
    super.key,
    required this.usuario,
    required this.onSolicitar,
    required this.onCancelar,
  });

  @override
  Widget build(BuildContext context) {
    switch (usuario.cuentaEstado) {
      case CuentaEstado.activa:
        return _activa(context);
      case CuentaEstado.eliminacionPendiente:
        return _pendiente(context);
      case CuentaEstado.eliminando:
        return _eliminando(context);
      case CuentaEstado.desconocida:
        return _desconocida(context);
    }
  }

  Widget _activa(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      key: const ValueKey('seccion_eliminar_cuenta'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Eliminar cuenta', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 6),
        Text(
          'Si decides eliminar tu cuenta, tendrás 15 días para arrepentirte: durante ese tiempo puedes cancelar la solicitud.',
          style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('boton_eliminar_cuenta'),
          onPressed: () => _solicitar(context),
          icon: const Icon(Icons.delete_forever_outlined, color: AppColors.danger),
          label: const Text('Eliminar mi cuenta', style: TextStyle(color: AppColors.danger)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.danger), minimumSize: const Size(48, 48)),
        ),
      ],
    );
  }

  Widget _pendiente(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final programada = usuario.eliminacionProgramadaAt;
    final dias = (usuario.eliminacionSolicitadaAt != null && programada != null)
        ? programada.difference(usuario.eliminacionSolicitadaAt!).inDays
        : 15;
    return Card(
      key: const ValueKey('tarjeta_eliminacion_cuenta'),
      color: AppColors.danger.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.hourglass_top_outlined, color: AppColors.danger),
              const SizedBox(width: 8),
              Expanded(child: Text('Eliminación de cuenta solicitada', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 10),
            Text(
              programada != null ? 'Programada para el ${formatFechaHora(programada)}.' : 'Programada.',
              key: const ValueKey('eliminacion_fecha'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text('Tienes un periodo de espera de $dias días calendario; puedes cancelarla hasta esa fecha. El servidor confirma si el plazo sigue vigente.'),
            const SizedBox(height: 10),
            Text(
              'Mientras tanto, las operaciones comerciales de tu cuenta están bloqueadas y tus cafés publicados no aparecen en el catálogo. '
              'Tu historial de solicitudes, conversaciones y cotizaciones sigue disponible.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              key: const ValueKey('boton_cancelar_eliminacion'),
              onPressed: () => _cancelar(context),
              icon: const Icon(Icons.undo),
              label: const Text('Cancelar solicitud'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ],
        ),
      ),
    );
  }

  /// El Worker ya comenzó el borrado definitivo: la cancelación dejó de estar disponible. Sin botones.
  Widget _eliminando(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      key: const ValueKey('tarjeta_cuenta_eliminando'),
      color: AppColors.danger.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.delete_forever_outlined, color: AppColors.danger),
              const SizedBox(width: 8),
              Expanded(child: Text('Tu cuenta está en proceso de eliminación definitiva', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 10),
            const Text('El periodo de espera terminó y la eliminación ya comenzó, por eso ya no se puede cancelar.'),
            const SizedBox(height: 8),
            Text('Las operaciones comerciales de tu cuenta están bloqueadas. Este proceso puede tardar un tiempo.', style: t.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _desconocida(BuildContext context) {
    return Card(
      key: const ValueKey('tarjeta_cuenta_desconocida'),
      color: AppColors.danger.withValues(alpha: 0.06),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No reconocemos el estado actual de tu cuenta, así que por seguridad las operaciones comerciales están bloqueadas. '
          'Actualiza la aplicación o inténtalo más tarde.',
        ),
      ),
    );
  }

  Future<void> _solicitar(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await showDialog<EstadoEliminacionCuenta>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoConContrasena(
        titulo: 'Eliminar cuenta',
        etiquetaConfirmar: 'Solicitar eliminación',
        exigeEntendido: true,
        contenido: const [
          Text('Antes de continuar, esto es lo que va a pasar:'),
          SizedBox(height: 8),
          _Punto('Tu cuenta entrará en un periodo de espera de 15 días calendario.'),
          _Punto('Durante ese tiempo se bloquearán las operaciones comerciales de tu cuenta.'),
          _Punto('Tus cafés publicados dejarán de aparecer en el catálogo durante el periodo.'),
          _Punto('Tus borradores no se alterarán.'),
          _Punto('El historial de solicitudes, conversaciones y cotizaciones no se borra en esta etapa.'),
          _Punto('Podrás cancelar la solicitud antes de la fecha límite.'),
          _Punto('El borrado definitivo todavía no ocurre al solicitarlo.'),
        ],
        operacion: onSolicitar,
      ),
    );
    if (r == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(r.programadaAt != null
            ? 'Solicitud registrada. Tu cuenta quedó programada para el ${formatFechaHora(r.programadaAt)}; puedes cancelarla antes.'
            : 'Solicitud registrada.'),
        duration: const Duration(seconds: 6),
      ));
  }

  Future<void> _cancelar(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await showDialog<EstadoEliminacionCuenta>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoConContrasena(
        titulo: 'Cancelar la eliminación',
        etiquetaConfirmar: 'Cancelar solicitud',
        exigeEntendido: false,
        contenido: const [
          Text('Tu cuenta volverá a estar activa y tus cafés que se suspendieron por esta solicitud se publicarán de nuevo. Por seguridad, confirma tu contraseña.'),
        ],
        operacion: onCancelar,
      ),
    );
    if (r == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Solicitud cancelada. Tu cuenta está activa de nuevo.'), duration: Duration(seconds: 5)));
  }
}

class _Punto extends StatelessWidget {
  final String texto;
  const _Punto(this.texto);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  '), Expanded(child: Text(texto))]),
      );
}

/// Diálogo de confirmación con contraseña. La contraseña vive solo en el controlador del campo (estado
/// temporal del formulario) y se borra al cerrar. Un solo envío a la vez: el botón se desactiva y muestra
/// el progreso hasta que el Worker responde; un error se muestra dentro y permite reintentar.
class _DialogoConContrasena extends StatefulWidget {
  final String titulo;
  final String etiquetaConfirmar;
  final bool exigeEntendido;
  final List<Widget> contenido;
  final OperacionConContrasena operacion;

  const _DialogoConContrasena({
    required this.titulo,
    required this.etiquetaConfirmar,
    required this.exigeEntendido,
    required this.contenido,
    required this.operacion,
  });

  @override
  State<_DialogoConContrasena> createState() => _DialogoConContrasenaState();
}

class _DialogoConContrasenaState extends State<_DialogoConContrasena> {
  final _password = TextEditingController();
  bool _entendido = false;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  bool get _puedeConfirmar => !_enviando && _password.text.isNotEmpty && (!widget.exigeEntendido || _entendido);

  Future<void> _confirmar() async {
    if (!_puedeConfirmar) return; // evita el doble toque (la bandera se activa antes de cualquier await)
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final r = await widget.operacion(_password.text);
      if (!mounted) return;
      Navigator.of(context).pop(r);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = RepoException.desde(e).mensaje;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_enviando,
      child: AlertDialog(
        title: Text(widget.titulo),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...widget.contenido,
              const SizedBox(height: 12),
              if (widget.exigeEntendido)
                CheckboxListTile(
                  key: const ValueKey('casilla_entiendo'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _entendido,
                  onChanged: _enviando ? null : (v) => setState(() => _entendido = v ?? false),
                  title: const Text('Entiendo lo que ocurrirá con mi cuenta.'),
                ),
              TextField(
                key: const ValueKey('campo_contrasena'),
                controller: _password,
                enabled: !_enviando,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                autofillHints: const [],
                decoration: const InputDecoration(labelText: 'Tu contraseña', prefixIcon: Icon(Icons.lock_outline)),
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, key: const ValueKey('error_contrasena'), style: const TextStyle(color: AppColors.danger)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('boton_volver'),
            onPressed: _enviando ? null : () => Navigator.of(context).pop(),
            child: const Text('Volver'),
          ),
          ElevatedButton(
            key: const ValueKey('boton_confirmar_contrasena'),
            onPressed: _puedeConfirmar ? _confirmar : null,
            style: ElevatedButton.styleFrom(minimumSize: const Size(48, 48)),
            child: _enviando
                ? const SizedBox(key: ValueKey('enviando_progreso'), width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Text(widget.etiquetaConfirmar),
          ),
        ],
      ),
    );
  }
}
