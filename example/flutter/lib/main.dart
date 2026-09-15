import 'package:flutter/material.dart';

import 'acceptance.dart';

void main() => runApp(const MaterialApp(home: AcceptanceApp()));

class AcceptanceApp extends StatefulWidget {
  const AcceptanceApp({super.key});

  @override
  State<AcceptanceApp> createState() => _AcceptanceAppState();
}

class _AcceptanceAppState extends State<AcceptanceApp>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation;
  int frames = 0;
  final checks = <String>[];
  List<NoteCard> rows = [];
  Map<String, Object?>? report;

  @override
  void initState() {
    super.initState();
    animation =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..addListener(() => frames++)
          ..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final result = await runAcceptance(
        onRows: (value) => setState(() => rows = value),
        onCheck: (value) => setState(() => checks.add(value)),
        frameCount: () => frames,
      );
      animation.stop();
      setState(() => report = result);
    });
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = report?['status'];
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F3),
      appBar: AppBar(title: const Text('Dart ORM · native acceptance')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            status == 'passed'
                ? 'All checks passed'
                : status == 'failed'
                ? 'Check failed'
                : 'Running on Android',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          if (report == null) const LinearProgressIndicator(),
          if (report != null)
            Text(
              '${report!['phase']} · SQLite ${report!['sqlite']} · '
              '${report!['release'] == true ? 'AOT release' : 'debug'}',
            ),
          if (report?['error'] != null)
            Text(
              '${report!['error']}',
              style: const TextStyle(color: Colors.red),
            ),
          const SizedBox(height: 20),
          for (final row in rows)
            Card(
              child: ListTile(
                leading: Icon(
                  row.done ? Icons.check_circle : Icons.circle_outlined,
                  color: const Color(0xFF53715A),
                ),
                title: Text(row.text),
                subtitle: row.comments.isEmpty
                    ? null
                    : Text(row.comments.join('\n')),
              ),
            ),
          const SizedBox(height: 20),
          Text(
            '${checks.length} verified checks',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final check in checks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text('✓ $check'),
            ),
        ],
      ),
    );
  }
}
