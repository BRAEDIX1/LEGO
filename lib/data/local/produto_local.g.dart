// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'produto_local.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ProdutoLocalAdapter extends TypeAdapter<ProdutoLocal> {
  @override
  final int typeId = 31;

  @override
  ProdutoLocal read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ProdutoLocal(
      codigo: fields[0] as String,
      descricao: fields[1] as String,
      unidade: fields[2] as String,
      origem: fields[3] as String,
      updatedAt: fields[4] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, ProdutoLocal obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.codigo)
      ..writeByte(1)
      ..write(obj.descricao)
      ..writeByte(2)
      ..write(obj.unidade)
      ..writeByte(3)
      ..write(obj.origem)
      ..writeByte(4)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProdutoLocalAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
