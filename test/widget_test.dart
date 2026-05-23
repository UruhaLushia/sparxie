import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sparxie/controller.dart';

void main() {
  test('ControllerStore add/update/remove persists', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await ControllerStore.load();

    final added = await store.add(name: '机房', baseUrl: 'http://1.2.3.4:9090');
    expect(store.controllers.any((c) => c.id == added.id), isTrue);

    await store.update(added.id, name: '机房 A');
    expect(
      store.controllers.firstWhere((c) => c.id == added.id).name,
      '机房 A',
    );

    await store.activate(added.id);
    expect(store.activeId, added.id);

    await store.remove(added.id);
    expect(store.controllers.any((c) => c.id == added.id), isFalse);
  });
}
