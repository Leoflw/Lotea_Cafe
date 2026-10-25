import 'dart:io';
import 'package:flutter/material.dart';
import '../models/coffee_profile.dart';
import '../theme/app_theme.dart';

/// Tarjeta visual de un perfil de café mostrada en el feed tipo swipe.
/// Las imágenes son archivos locales (elegidos con la galería); si no hay
/// ninguna, se muestra un ícono de café como placeholder.
class SwipeCard extends StatelessWidget {
  final CoffeeProfile perfil;

  const SwipeCard({super.key, required this.perfil});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _imagenPrincipal(),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          perfil.finca.isNotEmpty ? perfil.finca : perfil.nombreVendedor,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (perfil.calificacionPromedio > 0) ...[
                        const Icon(Icons.star, color: Colors.amber, size: 18),
                        const SizedBox(width: 2),
                        Text(
                          perfil.calificacionPromedio.toStringAsFixed(1),
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    perfil.nombreVendedor,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: perfil.variedades.take(4).map((v) => _Chip(texto: v)).toList(),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '\$${perfil.precioPorKg.toStringAsFixed(2)} / kg',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (perfil.altitudMsnm != null)
                        Text(
                          '${perfil.altitudMsnm!.toStringAsFixed(0)} msnm',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagenPrincipal() {
    if (perfil.imagenes.isEmpty) {
      return Container(
        color: AppColors.coffeeLight,
        child: const Icon(Icons.coffee, size: 64, color: Colors.white),
      );
    }
    final archivo = File(perfil.imagenes.first);
    return Image.file(
      archivo,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: AppColors.coffeeLight,
        child: const Icon(Icons.coffee, size: 64, color: Colors.white),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String texto;
  const _Chip({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.22),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(texto, style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }
}
