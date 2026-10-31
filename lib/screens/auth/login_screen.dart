import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../repositories/repo_exception.dart';
import '../../state/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_header.dart';
import '../../widgets/dismiss_keyboard.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

/// Inicio de sesión exclusivamente con Firebase Authentication. No existe
/// ningún acceso rápido ni cuenta de demostración.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _ocultar = true;
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _iniciarSesion() async {
    if (_cargando || !_formKey.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await context.read<SessionProvider>().iniciarSesion(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
      // El AuthGate cambia de pantalla al detectar la sesión.
    } on RepoException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DismissKeyboard(
      child: Scaffold(
        body: SafeArea(
          // El contenido se centra con la altura disponible, pero si no cabe
          // (teléfono pequeño o teclado abierto) simplemente se desplaza.
          child: LayoutBuilder(
            builder: (context, constraints) {
              const padV = 24.0;
              final h = constraints.maxHeight;
              final gapMarca = (h * 0.03).clamp(14.0, 28.0).toDouble();
              final gapFormulario = (h * 0.045).clamp(20.0, 40.0).toDouble();
              final minAlto = h > padV * 2 ? h - padV * 2 : 0.0;
              return SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: padV),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minAlto),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const LoteaBrandHeader(symbolHeight: 84, nameSize: 38),
                        SizedBox(height: gapMarca),
                        Text(
                          'Marketplace de café: conecta productores y compradores.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                        SizedBox(height: gapFormulario),
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          enabled: !_cargando,
                          decoration: const InputDecoration(labelText: 'Correo electrónico', prefixIcon: Icon(Icons.email_outlined)),
                          validator: (v) {
                            final t = (v ?? '').trim();
                            if (t.isEmpty) return 'Escribe tu correo';
                            return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'Correo inválido';
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _ocultar,
                          autofillHints: const [AutofillHints.password],
                          enabled: !_cargando,
                          onFieldSubmitted: (_) => _iniciarSesion(),
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _ocultar ? 'Mostrar contraseña' : 'Ocultar contraseña',
                              icon: Icon(_ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                              onPressed: () => setState(() => _ocultar = !_ocultar),
                            ),
                          ),
                          validator: (v) => (v == null || v.isEmpty) ? 'Escribe tu contraseña' : null,
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _cargando
                                ? null
                                : () => Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => ForgotPasswordScreen(emailInicial: _emailCtrl.text.trim()),
                                    )),
                            child: const Text('¿Olvidaste tu contraseña?'),
                          ),
                        ),
                        if (_error != null) ...[
                          Text(_error!, style: const TextStyle(color: AppColors.danger)),
                          const SizedBox(height: 10),
                        ],
                        ElevatedButton(
                          onPressed: _cargando ? null : _iniciarSesion,
                          child: _cargando
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                              : const Text('Iniciar sesión'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: _cargando
                              ? null
                              : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
                          child: const Text('Crear cuenta nueva'),
                        ),
                        // Pequeño contrapeso inferior: sube ligeramente el centro
                        // óptico del bloque para que no se sienta pegado abajo.
                        SizedBox(height: h * 0.06),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
