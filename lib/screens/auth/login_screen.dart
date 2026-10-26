import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/mock_store.dart';
import '../../models/app_user.dart';
import '../../services/session_provider.dart';
import '../../theme/app_theme.dart';
import '../home/home_shell.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _irAHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeShell()),
      (route) => false,
    );
  }

  void _iniciarSesion() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      context.read<SessionProvider>().iniciarSesion(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
      _irAHome();
    } catch (e) {
      setState(() => _error = e is AuthException ? e.mensaje : 'Error inesperado.');
    }
  }

  void _accesoRapidoComprador() {
    final session = context.read<SessionProvider>();
    try {
      session.registrar(
        email: 'comprador_demo@test.cafe',
        password: '123456',
        nombre: 'Comprador Demo',
        rol: UserRole.comprador,
      );
    } catch (_) {
      session.iniciarSesion(email: 'comprador_demo@test.cafe', password: '123456');
    }
    _irAHome();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const SizedBox(height: 36),
                const Icon(Icons.agriculture_outlined, size: 52, color: AppColors.coffeeMedium),
                const SizedBox(height: 12),
                Text('CaféMatch', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  'Marketplace de café — conecta productores y compradores.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) => (v == null || !v.contains('@')) ? 'Correo inválido' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (v) => (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                ],
                const SizedBox(height: 20),
                ElevatedButton(onPressed: _iniciarSesion, child: const Text('Iniciar sesión')),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
                  child: const Text('Crear cuenta nueva'),
                ),
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('o para probar rápido', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                ]),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _accesoRapidoComprador,
                  icon: const Icon(Icons.travel_explore_outlined, color: AppColors.leafGreen),
                  label: const Text('Entrar como comprador demo'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.leafGreen),
                    foregroundColor: AppColors.leafGreen,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
