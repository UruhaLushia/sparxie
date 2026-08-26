import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../rust_api.dart' as rust;
import '../utils.dart';

Future<void> showMemoryDetailsSheet({
  required BuildContext context,
  required bool localKernel,
  required ValueListenable<rust.MemorySample> memory,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) =>
        _MemoryDetailsSheet(localKernel: localKernel, memory: memory),
  );
}

class _MemoryDetailsSheet extends StatefulWidget {
  const _MemoryDetailsSheet({required this.localKernel, required this.memory});
  final bool localKernel;
  final ValueListenable<rust.MemorySample> memory;

  @override
  State<_MemoryDetailsSheet> createState() => _MemoryDetailsSheetState();
}

class _MemoryDetailsSheetState extends State<_MemoryDetailsSheet> {
  rust.MemoryDetails? _details;
  String? _error;
  bool _loading = false;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading || !mounted) return;
    setState(() => _loading = true);
    try {
      final details = await rust.memoryDetails(
        includeKernel: widget.localKernel,
      );
      if (mounted) {
        setState(() {
          _details = details;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.86,
        child: ListenableBuilder(
          listenable: widget.memory,
          builder: (context, _) {
            final app = _details?.app;
            final total = app?.pss ?? widget.memory.value.inuse;
            final kernel = _details?.kernel;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '内存信息',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('总计', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  formatBytes(total),
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 20),
                if (_error != null) _InfoText(_error!),
                _Section(
                  title: '应用',
                  child: app == null
                      ? const _InfoText('暂无 Android 进程明细')
                      : _appInfo(app),
                ),
                _Section(
                  title: '内核',
                  child: kernel == null
                      ? _InfoText(
                          _details?.kernelError ??
                              (widget.localKernel ? '内核未运行' : '当前控制器不提供内核明细'),
                        )
                      : _kernelInfo(kernel),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _appInfo(rust.AppMemoryInfo info) => Column(
    children: [
      _MemoryRow('PSS（进程总量）', info.pss),
      if (info.rss != null) _MemoryRow('RSS（驻留内存）', info.rss!),
      if (info.peakRss != null) _MemoryRow('峰值 RSS', info.peakRss!),
      if (info.virtualSize != null) _MemoryRow('虚拟内存', info.virtualSize!),
      _MemoryRow('私有脏页', info.privateDirty),
      _MemoryRow('私有干净页', info.privateClean),
      _MemoryRow('共享页', info.sharedClean + info.sharedDirty),
      if (info.swapPss != null) _MemoryRow('Swap PSS', info.swapPss!),
      const Divider(),
      if (info.javaAllocated != BigInt.zero)
        _MemoryRow(
          'Java 堆已用 / 上限',
          info.javaAllocated,
          suffix: ' / ${formatBytes(info.javaLimit)}',
        ),
      _MemoryRow('原生堆已分配', info.nativeAllocated),
      _MemoryRow('图形', info.graphics ?? BigInt.zero),
      _MemoryRow('代码', info.code ?? BigInt.zero),
      _MemoryRow('栈', info.stack ?? BigInt.zero),
      _MemoryRow('其他私有', info.privateOther ?? BigInt.zero),
    ],
  );

  Widget _kernelInfo(rust.KernelMemoryInfo info) => Column(
    children: [
      _MemoryRow('堆已使用', info.heapAlloc),
      _MemoryRow('堆占用页', info.heapInuse),
      _MemoryRow('堆空闲页', info.heapIdle),
      _MemoryRow('堆已归还', info.heapReleased),
      _MemoryRow('栈占用', info.stackInuse),
      _MemoryRow('运行时系统内存', info.sys),
      _MemoryRow('协程', BigInt.from(info.goroutines), suffix: ' 个'),
      _MemoryRow('GC 次数', BigInt.from(info.gcCount), suffix: ' 次'),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

class _MemoryRow extends StatelessWidget {
  const _MemoryRow(this.label, this.value, {this.suffix = ''});
  final String label;
  final BigInt value;
  final String suffix;
  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: Text('${formatBytes(value)}$suffix'),
  );
}

class _InfoText extends StatelessWidget {
  const _InfoText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.bodyMedium);
}
