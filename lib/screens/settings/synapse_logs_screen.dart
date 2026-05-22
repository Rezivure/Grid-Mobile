import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/in_app_notifier.dart';
import '../../services/log_stream_service.dart';
import '../../styles/grid_colors.dart';

/// Terminal-style live tail of in-app + Matrix SDK logs. Reached from
/// Developer tools → "Synapse Logs". Auto-scrolls to the latest line
/// unless the user manually scrolls up, in which case scrolling is
/// paused until they return to the bottom (typical log-viewer UX).
class SynapseLogsScreen extends StatefulWidget {
  const SynapseLogsScreen({super.key});

  @override
  State<SynapseLogsScreen> createState() => _SynapseLogsScreenState();
}

class _SynapseLogsScreenState extends State<SynapseLogsScreen> {
  final ScrollController _scrollController = ScrollController();
  final Set<LogStreamLevel> _enabledLevels = {
    LogStreamLevel.info,
    LogStreamLevel.warning,
    LogStreamLevel.error,
    LogStreamLevel.debug,
    LogStreamLevel.verbose,
  };
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    LogStreamService.instance.start();
    LogStreamService.instance.addListener(_onLogsChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    LogStreamService.instance.removeListener(_onLogsChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onLogsChanged() {
    if (!mounted) return;
    setState(() {});
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 24;
    if (atBottom != _autoScroll) {
      setState(() => _autoScroll = atBottom);
    }
  }

  List<LogStreamEntry> _visibleEntries() {
    return LogStreamService.instance.entries
        .where((e) => _enabledLevels.contains(e.level))
        .toList(growable: false);
  }

  Future<void> _copyAll() async {
    final entries = _visibleEntries();
    final buffer = StringBuffer();
    for (final e in entries) {
      buffer.writeln(_formatLine(e));
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    InAppNotifier.instance.show(
      title: 'Copied ${entries.length} lines',
      variant: InAppNotificationVariant.success,
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _share() async {
    final entries = _visibleEntries();
    final buffer = StringBuffer();
    for (final e in entries) {
      buffer.writeln(_formatLine(e));
    }
    await Share.share(buffer.toString(), subject: 'Grid logs');
  }

  String _formatLine(LogStreamEntry e) {
    final t = e.time;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    final tag = _levelTag(e.level);
    return '$hh:$mm:$ss.$ms $tag ${e.source}: ${e.message}';
  }

  String _levelTag(LogStreamLevel l) {
    switch (l) {
      case LogStreamLevel.error:
        return '[E]';
      case LogStreamLevel.warning:
        return '[W]';
      case LogStreamLevel.info:
        return '[I]';
      case LogStreamLevel.debug:
        return '[D]';
      case LogStreamLevel.verbose:
        return '[V]';
    }
  }

  Color _levelColor(LogStreamLevel l) {
    switch (l) {
      case LogStreamLevel.error:
        return context.gridColors.danger;
      case LogStreamLevel.warning:
        return context.gridColors.amber;
      case LogStreamLevel.info:
        return context.gridColors.mint;
      case LogStreamLevel.debug:
        return context.gridColors.text2;
      case LogStreamLevel.verbose:
        return context.gridColors.text3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _visibleEntries();
    final paused = LogStreamService.instance.paused;
    return Scaffold(
      backgroundColor: context.gridColors.bg,
      appBar: AppBar(
        backgroundColor: context.gridColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: context.gridColors.text,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        centerTitle: true,
        title: Text(
          'Synapse Logs',
          style: GoogleFonts.getFont(
            'Geist',
            color: context.gridColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.015,
          ),
        ),
        actions: [
          IconButton(
            tooltip: paused ? 'Resume' : 'Pause',
            icon: Icon(
              paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: paused ? context.gridColors.mint : context.gridColors.text2,
            ),
            onPressed: () => LogStreamService.instance.setPaused(!paused),
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert_rounded,
              color: context.gridColors.text2,
            ),
            color: context.gridColors.surface,
            onSelected: (v) async {
              switch (v) {
                case 'copy':
                  await _copyAll();
                  break;
                case 'share':
                  await _share();
                  break;
                case 'clear':
                  LogStreamService.instance.clear();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('Copy all')),
              PopupMenuItem(value: 'share', child: Text('Share')),
              PopupMenuItem(value: 'clear', child: Text('Clear')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _LevelFilterBar(
            enabled: _enabledLevels,
            onToggle: (level) {
              setState(() {
                if (_enabledLevels.contains(level)) {
                  _enabledLevels.remove(level);
                } else {
                  _enabledLevels.add(level);
                }
              });
            },
          ),
          Expanded(
            child: Container(
              color: context.gridColors.bg,
              child: entries.isEmpty
                  ? _emptyState(paused)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: SelectableText.rich(
                            TextSpan(
                              style: GoogleFonts.getFont(
                                'Geist Mono',
                                fontSize: 11,
                                height: 1.35,
                                color: context.gridColors.text2,
                              ),
                              children: [
                                TextSpan(
                                  text: '${_timeStamp(e.time)} ',
                                  style: TextStyle(
                                    color: context.gridColors.text4,
                                  ),
                                ),
                                TextSpan(
                                  text: '${_levelTag(e.level)} ',
                                  style: TextStyle(
                                    color: _levelColor(e.level),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                TextSpan(
                                  text: '${e.source}: ',
                                  style: TextStyle(
                                    color: context.gridColors.text3,
                                  ),
                                ),
                                TextSpan(
                                  text: e.message,
                                  style: TextStyle(
                                    color: e.level == LogStreamLevel.error
                                        ? context.gridColors.danger
                                        : context.gridColors.text,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          if (!_autoScroll && entries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 12, 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: Material(
                  color: context.gridColors.mint,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: () {
                      _scrollController.jumpTo(
                        _scrollController.position.maxScrollExtent,
                      );
                      setState(() => _autoScroll = true);
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_downward_rounded,
                            size: 14,
                            color: Color(0xFF04201A),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Jump to latest',
                            style: TextStyle(
                              color: Color(0xFF04201A),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyState(bool paused) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              paused
                  ? Icons.pause_circle_outline_rounded
                  : Icons.terminal_rounded,
              size: 36,
              color: context.gridColors.text3,
            ),
            const SizedBox(height: 12),
            Text(
              paused ? 'Capture paused' : 'Waiting for logs…',
              style: GoogleFonts.getFont(
                'Geist',
                color: context.gridColors.text2,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              paused
                  ? 'Tap the play button to resume.'
                  : 'Trigger sync / decryption activity to see lines stream in.',
              textAlign: TextAlign.center,
              style: GoogleFonts.getFont(
                'Geist',
                color: context.gridColors.text3,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeStamp(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
}

class _LevelFilterBar extends StatelessWidget {
  const _LevelFilterBar({required this.enabled, required this.onToggle});

  final Set<LogStreamLevel> enabled;
  final void Function(LogStreamLevel) onToggle;

  @override
  Widget build(BuildContext context) {
    final levels = [
      (LogStreamLevel.error, 'ERR', context.gridColors.danger),
      (LogStreamLevel.warning, 'WRN', context.gridColors.amber),
      (LogStreamLevel.info, 'INF', context.gridColors.mint),
      (LogStreamLevel.debug, 'DBG', context.gridColors.text2),
      (LogStreamLevel.verbose, 'VRB', context.gridColors.text3),
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.gridColors.hairline),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          for (final (level, label, color) in levels) ...[
            _Chip(
              label: label,
              color: color,
              active: enabled.contains(level),
              onTap: () => onToggle(level),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? color.withOpacity(0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: active ? color : context.gridColors.hairlineStrong,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.getFont(
              'Geist Mono',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.08,
              color: active ? color : context.gridColors.text3,
            ),
          ),
        ),
      ),
    );
  }
}
