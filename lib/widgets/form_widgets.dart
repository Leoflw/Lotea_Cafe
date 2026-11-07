import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Sección de un formulario largo: icono + título en DM Serif Display, texto
/// de orientación y los campos debajo. Sin tarjeta ni borde: la separación la
/// dan el título y el espacio, para que el formulario no parezca una pila de
/// cajas.
class FormSection extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String? ayuda;
  final Widget? trailing;
  final List<Widget> children;

  const FormSection({
    super.key,
    required this.icono,
    required this.titulo,
    required this.children,
    this.ayuda,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(color: AppColors.surfaceWarm, shape: BoxShape.circle),
              child: Icon(icono, size: 19, color: AppColors.coffeeMedium),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(titulo, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 21))),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
        if (ayuda != null) ...[
          const SizedBox(height: 8),
          Text(ayuda!, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4)),
        ],
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }
}

/// Separador entre secciones de un formulario.
class FormSeparator extends StatelessWidget {
  const FormSeparator({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 26),
        child: Divider(),
      );
}

/// Etiqueta de un campo con su estado (obligatorio con «*» u «Opcional») y,
/// si hace falta, una explicación sencilla debajo.
class FieldLabel extends StatelessWidget {
  final String texto;
  final bool obligatorio;
  final bool opcional;
  final String? ayuda;

  const FieldLabel(this.texto, {super.key, this.obligatorio = false, this.opcional = false, this.ayuda});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(texto, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.coffeeDark)),
              ),
              if (obligatorio) const Text(' *', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800, fontSize: 14)),
              if (opcional) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.surfaceWarm, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: const Text('Opcional', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.inkSoft, height: 1.2)),
                ),
              ],
            ],
          ),
          if (ayuda != null) ...[
            const SizedBox(height: 2),
            Text(ayuda!, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35)),
          ],
        ],
      ),
    );
  }
}

/// Opción seleccionable de un formulario (variedad, proceso, certificación…).
/// [unica] = una sola opción (ChoiceChip); si no, selección múltiple.
class OptionChip extends StatelessWidget {
  final String texto;
  final bool activo;
  final ValueChanged<bool> onSelected;
  final bool unica;

  const OptionChip({super.key, required this.texto, required this.activo, required this.onSelected, this.unica = false});

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(color: activo ? Colors.white : AppColors.coffeeDark, fontWeight: FontWeight.w600);
    final borde = BorderSide(color: activo ? AppColors.coffeeMedium : AppColors.outlineStrong);
    if (unica) {
      return ChoiceChip(
        label: Text(texto),
        selected: activo,
        showCheckmark: false,
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.coffeeMedium,
        side: borde,
        labelStyle: estilo,
        onSelected: onSelected,
      );
    }
    return FilterChip(
      label: Text(texto),
      selected: activo,
      showCheckmark: false,
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.coffeeMedium,
      side: borde,
      labelStyle: estilo,
      onSelected: onSelected,
    );
  }
}
