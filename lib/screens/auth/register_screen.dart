import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/mock_store.dart';
import '../../models/app_user.dart';
import '../../services/session_provider.dart';
import '../../theme/app_theme.dart';
import '../home/home_shell.dart';

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

  UserRole _rolSeleccionado = UserRole.comprador;
  String? _error;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _registrar() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      context.read<SessionProvider>().registrar(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
            nombre: _nombreCtrl.text.trim(),
            rol: _rolSeleccionado,
          );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (route) => false,
      );
    } catch (e) {
      setState(() => _error = e is AuthException ? e.mensaje : 'Error inesperado.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const SizedBox(height: 12),
                Text('Quiero registrarme como:',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _RolCard(
                        icono: Icons.storefront_outlined,
                        titulo: 'Vendedor',
                        subtitulo: 'Ofrezco café',
                        seleccionado: _rolSeleccionado == UserRole.vendedor,
                        onTap: () =>
                            setState(() => _rolSeleccionado = UserRole.vendedor),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RolCard(
                        icono: Icons.shopping_bag_outlined,
                        titulo: 'Comprador',
                        subtitulo: 'Busco café',
                        seleccionado: _rolSeleccionado == UserRole.comprador,
                        onTap: () => setState(
                            () => _rolSeleccionado = UserRole.comprador),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre o nombre de finca/marca',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) =>
                      (v == null || !v.contains('@')) ? 'Correo inválido' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (v) => (v == null || v.length < 6)
                      ? 'Mínimo 6 caracteres'
                      : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _registrar,
                  child: const Text('Registrarme'),
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

class _RolCard extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String subtitulo;
  final bool seleccionado;
  final VoidCallback onTap;

  const _RolCard({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: seleccionado ? AppColors.coffeeMedium : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: seleccionado ? AppColors.coffeeMedium : AppColors.coffeeLight,
            width: 1.4,
          ),
        ),
        child: Column(
          children: [
            Icon(icono, color: seleccionado ? Colors.white : AppColors.coffeeMedium),
            const SizedBox(height: 8),
            Text(
              titulo,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: seleccionado ? Colors.white : AppColors.coffeeDark,
              ),
            ),
            Text(
              subtitulo,
              style: TextStyle(
                fontSize: 12,
                color: seleccionado ? Colors.white70 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
