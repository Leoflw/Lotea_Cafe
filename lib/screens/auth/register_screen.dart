import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_user.dart';
import '../../repositories/repo_exception.dart';
import '../../state/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dismiss_keyboard.dart';

/// Registro con selección de rol — el vocabulario usado a partir de aquí
/// es siempre comercial ("Vender café" / "Comprar café"), nunca de citas.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _ciudadCtrl = TextEditingController();

  UserRole _rolSeleccionado = UserRole.comprador;
  TipoComprador? _tipoComprador;
  String? _error;
  bool _ocultar = true;
  bool _cargando = false;

  /// true cuando la cuenta ya existe en Authentication pero no se pudo crear
  /// el perfil: el botón reintenta SOLO el perfil (no crea otra cuenta).
  bool _soloFaltaPerfil = false;

  static final _regexCorreo = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _ciudadCtrl.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    if (_cargando) return;
    if (!_soloFaltaPerfil && !_formKey.currentState!.validate()) return;
    final session = context.read<SessionProvider>();
    final navigator = Navigator.of(context);
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      if (_soloFaltaPerfil) {
        await session.reintentarCreacionDePerfil();
      } else {
        await session.registrar(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          nombre: _nombreCtrl.text.trim(),
          rol: _rolSeleccionado,
          ciudad: _rolSeleccionado == UserRole.comprador ? _ciudadCtrl.text.trim() : null,
          tipoComprador: _rolSeleccionado == UserRole.comprador ? _tipoComprador : null,
        );
      }
      // El AuthGate muestra el onboarding correspondiente al rol.
      navigator.popUntil((r) => r.isFirst);
    } on RepoException catch (e) {
      if (!mounted) return;
      setState(() {
        _soloFaltaPerfil = session.uid != null && session.hayRegistroPendiente;
        _error = _soloFaltaPerfil
            ? 'Tu cuenta se creó, pero no pudimos guardar tu perfil: ${e.mensaje} Pulsa «Reintentar» para continuar sin crear otra cuenta.'
            : e.mensaje;
      });
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DismissKeyboard(
      child: Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const SizedBox(height: 12),
                Text('Quiero:', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                // IntrinsicHeight + stretch: ambas tarjetas miden SIEMPRE lo mismo
                // (la más alta marca la altura), sin dimensiones fijas.
                IntrinsicHeight(
                  child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _RolCard(
                        key: const ValueKey('rol_card_vendedor'),
                        icono: Icons.storefront_outlined,
                        titulo: 'Vender café',
                        subtitulo: 'Soy productor/vendedor',
                        seleccionado: _rolSeleccionado == UserRole.vendedor,
                        onTap: _cargando || _soloFaltaPerfil ? () {} : () => setState(() => _rolSeleccionado = UserRole.vendedor),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RolCard(
                        key: const ValueKey('rol_card_comprador'),
                        icono: Icons.travel_explore_outlined,
                        titulo: 'Comprar café',
                        subtitulo: 'Busco productores',
                        seleccionado: _rolSeleccionado == UserRole.comprador,
                        onTap: _cargando || _soloFaltaPerfil ? () {} : () => setState(() => _rolSeleccionado = UserRole.comprador),
                      ),
                    ),
                  ],
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nombreCtrl,
                  // Mismo campo (y mismo `nombre` en Firestore) para ambos roles:
                  // solo cambian la etiqueta y el texto de ayuda. La etiqueta se
                  // mantiene elevada para que la etiqueta larga del vendedor no
                  // se corte y el ejemplo del comprador sea visible.
                  decoration: InputDecoration(
                    labelText: _rolSeleccionado == UserRole.vendedor
                        ? 'Nombre del productor o finca/marca'
                        : 'Nombre completo',
                    hintText: _rolSeleccionado == UserRole.vendedor ? null : 'Ej. María Rodríguez',
                    helperText: _rolSeleccionado == UserRole.vendedor
                        ? 'Puedes usar tu nombre, el de tu finca o tu marca comercial.'
                        : null,
                    helperMaxLines: 2,
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) => _regexCorreo.hasMatch((v ?? '').trim()) ? null : 'Correo inválido',
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _ocultar,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    helperText: 'Mínimo 8 caracteres, con letras y números.',
                    suffixIcon: IconButton(
                      tooltip: _ocultar ? 'Mostrar contraseña' : 'Ocultar contraseña',
                      icon: Icon(_ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _ocultar = !_ocultar),
                    ),
                  ),
                  validator: (v) {
                    final t = v ?? '';
                    if (t.length < 8) return 'Mínimo 8 caracteres';
                    if (!RegExp(r'[A-Za-z]').hasMatch(t) || !RegExp(r'\d').hasMatch(t)) {
                      return 'Incluye letras y números';
                    }
                    return null;
                  },
                ),
                if (_rolSeleccionado == UserRole.comprador) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _ciudadCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ciudad — opcional',
                      prefixIcon: Icon(Icons.location_city_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<TipoComprador>(
                    initialValue: _tipoComprador,
                    // Sin isExpanded el botón mide lo que mida el texto MÁS largo
                    // («Comprador independiente») + el icono, sin importar el ancho
                    // disponible, y desborda en pantallas estrechas. Con isExpanded
                    // el contenido ocupa el ancho del campo y, si aun así el texto
                    // no cabe, se recorta con puntos suspensivos en lugar de
                    // desbordar. El texto seleccionado y las opciones del menú usan
                    // el mismo Text, así que no hace falta un selectedItemBuilder.
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de comprador — opcional',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: TipoComprador.values
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(t.label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _tipoComprador = v),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _cargando ? null : _registrar,
                  child: _cargando
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : Text(_soloFaltaPerfil ? 'Reintentar' : 'Registrarme'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _RolCard extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String subtitulo;
  final bool seleccionado;
  final VoidCallback onTap;

  const _RolCard({
    super.key,
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorIcono = seleccionado ? Colors.white : AppColors.coffeeMedium;
    final colorTitulo = seleccionado ? Colors.white : AppColors.coffeeDark;
    final colorSubtitulo = seleccionado ? Colors.white70 : Colors.grey.shade600;
    // Reserva siempre dos líneas para el subtítulo: las dos tarjetas tienen el
    // mismo contenido vertical aunque un texto ocupe una línea y el otro dos.
    final altoSubtitulo = MediaQuery.textScalerOf(context).scale(12) * 1.3 * 2;

    return Semantics(
      button: true,
      selected: seleccionado,
      label: '$titulo. $subtitulo',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          // Selección: solo cambian color, borde, texto e indicador; nunca el tamaño.
          decoration: BoxDecoration(
            color: seleccionado ? AppColors.coffeeMedium : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: seleccionado ? AppColors.coffeeMedium : AppColors.coffeeLight, width: 1.4),
          ),
          child: Stack(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(icono, size: 28, color: colorIcono),
                  const SizedBox(height: 8),
                  Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colorTitulo),
                  ),
                  const SizedBox(height: 2),
                  ConstrainedBox(
                    constraints: BoxConstraints(minHeight: altoSubtitulo),
                    child: Text(
                      subtitulo,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, height: 1.3, color: colorSubtitulo),
                    ),
                  ),
                ],
              ),
              // El indicador siempre ocupa su lugar (solo cambia su opacidad).
              Positioned(
                top: 0,
                right: 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: seleccionado ? 1 : 0,
                  child: const Icon(Icons.check_circle, size: 18, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
