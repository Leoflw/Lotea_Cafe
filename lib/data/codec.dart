import 'package:cloud_firestore/cloud_firestore.dart';

/// Lectura tolerante de valores de Firestore. Los modelos no dependen de
/// `cloud_firestore` salvo por esta utilidad, así que se pueden probar con
/// mapas simples.
DateTime? readDate(Object? v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return null;
}

double? readDouble(Object? v) => v is num ? v.toDouble() : null;
int? readInt(Object? v) => v is num ? v.toInt() : null;
String? readString(Object? v) => v is String && v.isNotEmpty ? v : null;
List<String> readStringList(Object? v) =>
    v is List ? v.whereType<String>().toList() : <String>[];

T readEnum<T extends Enum>(List<T> values, Object? v, T fallback) {
  if (v is String) {
    for (final e in values) {
      if (e.name == v) return e;
    }
  }
  return fallback;
}
