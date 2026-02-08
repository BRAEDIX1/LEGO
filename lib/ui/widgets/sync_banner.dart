import 'package:flutter/material.dart';

class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key, required this.visible, this.message = 'Sincronizando bases...'});
  final bool visible;
  final String message;
  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return MaterialBanner(
      content: Text(message),
      actions: const [SizedBox()],
      leading: const Padding(
        padding: EdgeInsets.only(right: 8.0),
        child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}
