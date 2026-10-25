import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../repositories/repo_exception.dart';
import '../../state/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dismiss_keyboard.dart';

/// Recuperación de contraseña con Firebase Authentication.
class ForgotPasswordScreen extends StatefulWidget {
  final String emailInicial;
  const ForgotPasswordScreen({super.key, this.emailInicial = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _emailCtrl = TextEditingController(text: widget.emailInicial);
  bool _cargando = false;
  bool _enviado = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_cargando || !_formKey.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await context.read<SessionProvider>().recuperarPassword(_emailCtrl.text.trim());
      if (mounted) setState(() => _enviado = true);
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
        appBar: AppBar(title: const Text('Recuperar contraseña')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: _enviado
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.mark_email_read_outlined, size: 54, color: AppColors.leafGreen),
                      const SizedBox(height: 14),
                      const Text('Revisa tu correo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 8),
                      Text(
                        'Si ${_emailCtrl.text.trim()} tiene una cuenta, recibirás un enlace para crear una contraseña nueva.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Volver al inicio de sesión')),
                    ],
                  )
                : Form(
                    key: _formKey,
                    child: ListView(
                      children: [
                        Text('Te enviaremos un enlace para restablecerla.', style: TextStyle(color: Colors.grey.shade700)),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          enabled: !_cargando,
                          decoration: const InputDecoration(labelText: 'Correo electrónico', prefixIcon: Icon(Icons.email_outlined)),
                          validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Correo inválido',
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, style: const TextStyle(color: AppColors.danger)),
                        ],
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _cargando ? null : _enviar,
                          child: _cargando
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                              : const Text('Enviar enlace'),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
