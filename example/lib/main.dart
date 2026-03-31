import 'package:flutter/material.dart';

import 'demos/editorial_engine_demo.dart';
import 'demos/bubbles_demo.dart';

void main() {
  runApp(const PretextDemoApp());
}

class PretextDemoApp extends StatelessWidget {
  const PretextDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'pretext_flutter Demos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF955F3B),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const DemoLauncher(),
    );
  }
}

class DemoLauncher extends StatelessWidget {
  const DemoLauncher({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F1EA),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PRETEXT FLUTTER',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: colorScheme.primary,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Demos',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Georgia',
                      color: Color(0xFF201B18),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Interactive demos showing what pretext_flutter unlocks: '
                    'real-time text reflow around obstacles, shrinkwrap chat '
                    'bubbles, and more — all with pure arithmetic, no repeated '
                    'TextPainter.layout() calls.',
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: Color(0xFF6D645D),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Expanded(
                    child: GridView.count(
                      crossAxisCount:
                          MediaQuery.sizeOf(context).width > 760 ? 2 : 1,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 2.2,
                      children: [
                        _DemoCard(
                          title: 'Editorial Engine',
                          description:
                              'Animated orbs, live text reflow, multi-column '
                              'flow with zero DOM measurements. Drag the orbs '
                              'and watch text follow at 60fps.',
                          emoji: '\u{1F4F0}',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const EditorialEngineDemoPage(),
                            ),
                          ),
                        ),
                        _DemoCard(
                          title: 'Bubbles',
                          description:
                              'Tight multiline message bubbles that shrinkwrap '
                              'to the exact minimum width. Compare wasted space '
                              'vs normal CSS-style bubbles.',
                          emoji: '\u{1F4AC}',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BubblesDemo(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoCard extends StatelessWidget {
  const _DemoCard({
    required this.title,
    required this.description,
    required this.emoji,
    required this.onTap,
  });

  final String title;
  final String description;
  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFFDF8),
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD8CEC3)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14362817),
                blurRadius: 40,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF201B18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Text(
                  description,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Color(0xFF6D645D),
                  ),
                  overflow: TextOverflow.fade,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
