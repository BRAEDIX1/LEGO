// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_state.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AppStateAdapter extends TypeAdapter<AppState> {
  @override
  final int typeId = 2;

  @override
  AppState read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppState(
      lastSyncMateriais: fields[0] as String?,
      lastSyncBarras: fields[1] as String?,
      lastSyncGases: fields[2] as String?,
      lastLogin: fields[3] as DateTime?,
      lastSyncProdutos: fields[4] as String?,
      seedVersion: fields[5] as int,
      cursorBarrasShard: fields[6] as String?,
      cursorProdutosShard: fields[7] as String?,
      handover: fields[8] as bool,
      contagemAtual: fields[9] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, AppState obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.lastSyncMateriais)
      ..writeByte(1)
      ..write(obj.lastSyncBarras)
      ..writeByte(2)
      ..write(obj.lastSyncGases)
      ..writeByte(3)
      ..write(obj.lastLogin)
      ..writeByte(4)
      ..write(obj.lastSyncProdutos)
      ..writeByte(5)
      ..write(obj.seedVersion)
      ..writeByte(6)
      ..write(obj.cursorBarrasShard)
      ..writeByte(7)
      ..write(obj.cursorProdutosShard)
      ..writeByte(8)
      ..write(obj.handover)
      ..writeByte(9)
      ..write(obj.contagemAtual);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppStateAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
