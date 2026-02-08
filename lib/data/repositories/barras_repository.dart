// lib/data/repositories/barras_repository.dart
import 'package:hive/hive.dart';
import 'package:lego/data/local/hive_boxes.dart';
import 'package:lego/data/local/barra_local.dart';

class BarrasRepository {
  Future<Box<BarraLocal>> _open() async =>
      Hive.isBoxOpen(HiveBoxes.barrasBox)
          ? Hive.box<BarraLocal>(HiveBoxes.barrasBox)
          : await Hive.openBox<BarraLocal>(HiveBoxes.barrasBox);

  Future<BarraLocal?> getByTag(String tag) async {
    final box = await _open();
    return box.get(tag);
  }

  Future<void> logAvailableKeys() async {
    final box = await _open();
    print('[Diag] Keys disponíveis em ${box.name}: ${box.keys.take(20).toList()}');
  }
}
