import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_user.dart';
import '../../models/seller_profile.dart';
import '../../state/activity_provider.dart';
import '../../state/remote.dart';
import '../../state/session_provider.dart';
import '../../widgets/empty_state.dart' show RepoErrorView;
import '../../widgets/remote_view.dart';
import '../../theme/app_theme.dart';
import '../../widgets/badges.dart';
import '../seller/seller_profile_edit_screen.dart';

/// Cuenta del usuario. El comprador puede definir preferencias de compra
/// (sección 15); el vendedor ve un resumen de su perfil de marca y accede
/// a editarlo.
class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final actividad = context.watch<ActivityProvider>();
    final usuario = session.usuario;
    if (usuario == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(title: const Text('Mi cuenta')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: AppColors.coffeeLight,
              child: Text(
                usuario.nombre.isNotEmpty ? usuario.nombre[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 32, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(child: Text(usuario.nombre, style: Theme.of(context).textTheme.titleLarge)),
          Center(
            child: Text(usuario.rol.label,
                style: const TextStyle(color: AppColors.leafGreen, fontWeight: FontWeight.bold)),
          ),
          if (!session.esVendedor && (usuario.tipoComprador != null || usuario.ciudad != null)) ...[
            const SizedBox(height: 10),
            Center(
              child: Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (usuario.tipoComprador != null) Chip(label: Text(usuario.tipoComprador!.label)),
                  if (usuario.ciudad != null) Chip(label: Text(usuario.ciudad!)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          _fila(Icons.email_outlined, usuario.email),
          if (usuario.ciudad != null) _fila(Icons.location_city_outlined, usuario.ciudad!),

          if (session.esVendedor) ...[
            const SizedBox(height: 24),
            _tarjetaVendedor(context, actividad.perfilVendedor, usuario),
          ] else ...[
            const SizedBox(height: 24),
            _seccion('Preferencias de compra'),
            _preferenciasComprador(usuario),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _editarPreferencias(context, usuario),
              icon: const Icon(Icons.tune),
              label: const Text('Editar preferencias'),
            ),
          ],

          const SizedBox(height: 32),
          OutlinedButton.icon(
            // Al cerrar sesión, el AuthGate vuelve al login y se vacían los
            // datos del usuario (ActivityProvider).
            onPressed: () => context.read<SessionProvider>().cerrarSesion(),
            icon: const Icon(Icons.logout, color: AppColors.danger),
            label: const Text('Cerrar sesión', style: TextStyle(color: AppColors.danger)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaVendedor(BuildContext context, Remote<SellerProfile?> remoto, AppUser usuario) {
    if (remoto.cargando) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
    if (remoto.fallo) {
      return RepoErrorView(error: remoto.error!, onReintentar: context.read<ActivityProvider>().reintentar);
    }
    final perfil = remoto.data;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: perfil == null
            ? Column(
                children: [
                  const Text('Todavía no has creado el perfil de tu marca.'),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const SellerProfileEditScreen())),
                    child: const Text('Crear perfil de marca'),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(perfil.nombreMarca, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                      if (perfil.verificado) const VerifiedBadge(compacto: true),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(perfil.ubicacionCorta, style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const SellerProfileEditScreen())),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Editar perfil de marca'),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _preferenciasComprador(AppUser usuario) {
    final p = usuario.preferencias;
    if (p.estaVacia) {
      return Text('Aún no has configurado preferencias.', style: TextStyle(color: Colors.grey.shade600));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...p.variedades.map((v) => Chip(label: Text(v))),
        ...p.regiones.map((r) => Chip(label: Text(r))),
        ...p.procesos.map((pr) => Chip(label: Text(pr))),
        if (p.precioMaxCOP != null) Chip(label: Text('Hasta \$${p.precioMaxCOP!.toStringAsFixed(0)}/kg')),
      ],
    );
  }

  Future<void> _editarPreferencias(BuildContext context, AppUser usuario) async {
    var variedades = List<String>.from(usuario.preferencias.variedades);
    var regiones = List<String>.from(usuario.preferencias.regiones);
    var procesos = List<String>.from(usuario.preferencias.procesos);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Padding(
            padding: EdgeInsets.only(left: 24, right: 24, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Preferencias de compra', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  const Text('Variedades', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['Arábica', 'Robusta', 'Geisha', 'Bourbon', 'Typica', 'Caturra', 'Castillo'].map((v) {
                      final activo = variedades.contains(v);
                      return FilterChip(
                        label: Text(v),
                        selected: activo,
                        onSelected: (sel) => setState(() => sel ? variedades.add(v) : variedades.remove(v)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Regiones', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['Huila', 'Antioquia', 'Nariño', 'Caldas', 'Quindío', 'Tolima'].map((r) {
                      final activo = regiones.contains(r);
                      return FilterChip(
                        label: Text(r),
                        selected: activo,
                        onSelected: (sel) => setState(() => sel ? regiones.add(r) : regiones.remove(r)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Procesos', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['Lavado', 'Natural', 'Honey'].map((pr) {
                      final activo = procesos.contains(pr);
                      return FilterChip(
                        label: Text(pr),
                        selected: activo,
                        onSelected: (sel) => setState(() => sel ? procesos.add(pr) : procesos.remove(pr)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      final sesion = context.read<SessionProvider>();
                      final actualizado = usuario.copyWith(
                        preferencias: usuario.preferencias.copyWith(
                          variedades: variedades,
                          regiones: regiones,
                          procesos: procesos,
                        ),
                      );
                      try {
                        await sesion.actualizarUsuario(actualizado);
                        navigator.pop();
                      } catch (e) {
                        if (context.mounted) mostrarError(context, e);
                      }
                    },
                    child: const Text('Guardar preferencias'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    setState(() {});
  }

  Widget _seccion(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );

  Widget _fila(IconData icono, String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icono, color: AppColors.coffeeMedium, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }
}
