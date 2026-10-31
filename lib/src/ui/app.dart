import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../format.dart';
import '../native_bridge.dart';
import '../theme.dart';
import 'home_page.dart';
import 'settings_page.dart';

class DsBarApp extends StatefulWidget {
  const DsBarApp({super.key});

  @override
  State<DsBarApp> createState() => _DsBarAppState();
}

class _DsBarAppState extends State<DsBarApp> {
  final state = AppState();
  final bridge = NativeBridge();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    state.load();
    // 从通知 / 磁贴返回前台时，重读一次缓存快照
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  AppLifecycleListener? _lifecycle;

  Future<void> _onResume() async {
    await state.load();
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final title = _index == 0 ? 'DeepSeek 用量' : '设置';
        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              if (_index == 0)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _RefreshButton(state: state),
                ),
              IconButton(
                tooltip: '设置',
                onPressed: () => setState(() => _index = _index == 0 ? 1 : 0),
                icon: Icon(
                  _index == 0 ? Icons.settings_outlined : Icons.arrow_back,
                  size: 20,
                ),
              ),
            ],
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(1),
              child: Divider(height: 1, thickness: 1, color: DsColors.hairline),
            ),
          ),
          body: SafeArea(
            top: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _index == 0
                  ? HomePage(
                      key: const ValueKey('home'),
                      state: state,
                      onOpenSettings: () => setState(() => _index = 1),
                    )
                  : SettingsPage(
                      key: const ValueKey('settings'),
                      state: state,
                      bridge: bridge,
                    ),
            ),
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(height: 1, thickness: 1, color: DsColors.hairline),
              NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.insights_outlined),
                    selectedIcon: Icon(Icons.insights),
                    label: '概览',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.tune_outlined),
                    selectedIcon: Icon(Icons.tune),
                    label: '设置',
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (state.refreshing) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: DsColors.primary),
        ),
      );
    }
    return IconButton(
      tooltip: state.lastRefreshAt == null
          ? '同步'
          : '同步（上次 ${Fmt.relativeTime(state.lastRefreshAt)}）',
      onPressed: () async {
        await state.refresh();
        if (context.mounted) {
          HapticFeedback.selectionClick();
        }
      },
      icon: const Icon(Icons.sync, size: 20),
    );
  }
}
