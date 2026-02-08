// lib/services/sync_diagnostics.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:lego/data/local/lanc_local.dart';

class SyncDiagnostics {
  static Future<void> run(String uid) async {
    try {
      final name = 'lancamentos_$uid';
      final opened = Hive.isBoxOpen(name);
      print('[Diag] Box name: $name, isOpen=$opened');
      if (opened) {
        final box = Hive.box<LancLocal>(name);
        print('[Diag] Box len=${box.length} keys=${box.keys.take(3).toList()}');
      }

      final nested = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('lancamentos')
          .limit(1)
          .get();
      print('[Diag] Firestore users/{uid}/lancamentos count≈${nested.size}');

      for (final key in ['uid', 'userId', 'ownerId']) {
        final top = await FirebaseFirestore.instance
            .collection('lancamentos')
            .where(key, isEqualTo: uid)
            .limit(1)
            .get();
        print('[Diag] Firestore lancamentos where $key==uid count≈${top.size}');
      }
    } catch (e) {
      print('[Diag] Error running diagnostics: $e');
    }
  }
}
