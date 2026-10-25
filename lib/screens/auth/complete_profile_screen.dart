import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_user.dart';
import '../../repositories/repo_exception.dart';
import '../../state/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_header.dart';
import '../../widgets/dismiss_keyboard.dart';

/// Se muestra cuando existe una cuenta en Authentication pero no su perfil
/// en Firestore (p. ej. la app se cerró justo después del registro). Permite
/// completarlo sin crear otra cuenta.
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  UserRole _rol = UserRole.comprador;
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_cargando || !_formKey.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await context.read<SessionProvider>().completarPerfilFaltante(nombre: _nombreCtrl.text, rol: _rol);
    } on RepoException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sesion = context.read<SessionProvider>();
    return DismissKeyboard(
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  const SizedBox(height: 32),
                  const LoteaBrandHeader(symbolHeight: 60, nameSize: 32),
                  const SizedBox(height: 22),
                  Text('Completa tu perfil', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    'Tu cuenta (${sesion.correo ?? ''}) ya existe, pero falta guardar tus datos básicos.',
                    style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  SegmentedButton<UserRole>(
                    segments: const [
                      ButtonSegment(value: UserRole.comprador, label: Text('Comprar café'), icon: Icon(Icons.travel_explore_outlined)),
                      ButtonSegment(value: UserRole.vendedor, label: Text('Vender café'), icon: Icon(Icons.storefront_outlined)),
                    ],
                    selected: {_rol},
                    onSelectionChanged: _cargando ? null : (s) => setState(() => _rol = s.first),
                  ),
                  const SizedBox(height: 6),
                  Text('Este rol no se puede cambiar después.', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nombreCtrl,
                    enabled: !_cargando,
                    decoration: const InputDecoration(labelText: 'Nombre o nombre de finca/marca', prefixIcon: Icon(Icons.person_outline)),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.danger)),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _cargando ? null : _guardar,
                    child: _cargando
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : const Text('Guardar y continuar'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _cargando ? null : sesion.cerrarSesion, child: const Text('Cerrar sesión')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
