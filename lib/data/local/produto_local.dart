// lib/data/local/produto_local.dart
import 'package:hive/hive.dart';

part 'produto_local.g.dart';

@HiveType(typeId: 31)
class ProdutoLocal {
  @HiveField(0) String codigo;
  @HiveField(1) String descricao;
  @HiveField(2) String unidade;
  @HiveField(3) String origem; // 'gases' ou 'materiais'
  @HiveField(4) DateTime? updatedAt;

  ProdutoLocal({
    required this.codigo,
    required this.descricao,
    required this.unidade,
    required this.origem,
    this.updatedAt,
  });
}
