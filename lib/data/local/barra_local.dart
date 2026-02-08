// lib/data/local/barra_local.dart
import 'package:hive/hive.dart';

part 'barra_local.g.dart';

@HiveType(typeId: 32)
class BarraLocal {
  @HiveField(0) String tag;
  @HiveField(1) String codigo;
  @HiveField(2) String? lote;
  @HiveField(3) DateTime? updatedAt;

  BarraLocal({
    required this.tag,
    required this.codigo,
    this.lote,
    this.updatedAt,
  });
}