// lib/widgets/groups_subscreen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/widgets/custom_search_bar.dart';
import 'package:grid_frontend/widgets/grid/grid_avatar.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';
import 'package:grid_frontend/widgets/grid/grid_status_pill.dart';
import 'package:grid_frontend/widgets/group_info_subscreen.dart';

class GroupsSubscreen extends StatefulWidget {
  final ScrollController scrollController;

  GroupsSubscreen({required this.scrollController});

  @override
  _GroupsSubscreenState createState() => _GroupsSubscreenState();
}

class _GroupsSubscreenState extends State<GroupsSubscreen> {
  bool _showGroupDetail = false;
  String _selectedGroupName = '';

  // Placeholder group data shaping the redesigned list. The item count and
  // tap handler stay wired to the original `_showGroupDetail` flow so the
  // existing navigation logic into `GroupInfoSubscreen` is preserved.
  static const List<_GroupCardModel> _groups = [
    _GroupCardModel(
      name: 'Climbing crew',
      memberNames: ['Anya', 'Marcus', 'Devon', 'Jules'],
      memberCount: 4,
      place: 'Index, WA',
      liveCount: 3,
      timerLabel: 'ends in 3h 12m',
      featured: true,
    ),
    _GroupCardModel(
      name: 'Roomies',
      memberNames: ['Kai', 'Sam'],
      memberCount: 2,
      place: 'Capitol Hill',
      liveCount: 2,
    ),
    _GroupCardModel(
      name: 'Road trip — Day 4',
      memberNames: ['Anya', 'Yuki', 'Rey'],
      memberCount: 3,
      place: 'Crater Lake',
      liveCount: 3,
      timerLabel: 'active for 4d',
      isTrip: true,
    ),
    _GroupCardModel(
      name: 'Family',
      memberNames: ['Mom', 'Dad', 'Y'],
      memberCount: 3,
      place: null,
      liveCount: 0,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (_showGroupDetail) {
      return Column(
        children: [
          CustomSearchBar(
              controller: TextEditingController(), hintText: 'Search Groups'),
          Expanded(
            child: GroupInfoSubscreen(
              groupName: _selectedGroupName,
              onBack: () {
                setState(() {
                  _showGroupDetail = false;
                  _selectedGroupName = '';
                });
              },
              scrollController: widget.scrollController,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        CustomSearchBar(
            controller: TextEditingController(), hintText: 'Search Groups'),
        Expanded(
          child: ListView.builder(
            controller: widget.scrollController,
            itemCount: _groups.length,
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
            itemBuilder: (context, index) {
              final group = _groups[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _GroupCard(
                  model: group,
                  onTap: () {
                    setState(() {
                      _showGroupDetail = true;
                      _selectedGroupName = group.name;
                    });
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// View-model for the redesigned group card. Kept local to this file so we
/// don't introduce a new shared primitive.
class _GroupCardModel {
  const _GroupCardModel({
    required this.name,
    required this.memberNames,
    required this.memberCount,
    required this.place,
    required this.liveCount,
    this.timerLabel,
    this.isTrip = false,
    this.featured = false,
  });

  final String name;
  final List<String> memberNames;
  final int memberCount;
  final String? place;
  final int liveCount;
  final String? timerLabel;
  final bool isTrip;
  final bool featured;
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.model, required this.onTap});

  final _GroupCardModel model;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final featured = model.featured;
    final decoration = BoxDecoration(
      gradient: featured
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [GridTokens.mintFaint, GridTokens.surface],
            )
          : null,
      color: featured ? null : GridTokens.surface,
      borderRadius: BorderRadius.circular(GridTokens.rLg),
      border: Border.all(
        color: featured ? GridTokens.mintSoft : GridTokens.hairline,
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        child: Ink(
          decoration: decoration,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StackedAvatars(names: model.memberNames),
                    const SizedBox(width: 14),
                    Expanded(child: _GroupCardBody(model: model)),
                    if (model.liveCount > 0) ...[
                      const SizedBox(width: 8),
                      GridLiveBadge(label: '${model.liveCount} LIVE'),
                    ],
                  ],
                ),
                if (model.timerLabel != null) ...[
                  const SizedBox(height: 12),
                  _TimerRow(label: model.timerLabel!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupCardBody extends StatelessWidget {
  const _GroupCardBody({required this.model});

  final _GroupCardModel model;

  @override
  Widget build(BuildContext context) {
    final subtitle = model.place == null
        ? '${model.memberCount} members  ·  —'
        : '${model.memberCount} members  ·  ${model.place}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                model.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.01,
                  color: GridTokens.text,
                  height: 1.2,
                ),
              ),
            ),
            if (model.isTrip) ...[
              const SizedBox(width: 8),
              const GridStatusPill(
                label: 'TRIP',
                kind: GridStatusKind.trip,
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.getFont(
            'Geist',
            fontSize: 12.5,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.01,
            color: GridTokens.text2,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

/// Up to 4 avatars overlapped left-to-right with a bg ring around each.
class _StackedAvatars extends StatelessWidget {
  const _StackedAvatars({required this.names});

  final List<String> names;

  static const double _avatarSize = 32;
  static const double _overlap = 12;

  @override
  Widget build(BuildContext context) {
    final visible = names.take(4).toList();
    if (visible.isEmpty) {
      return const SizedBox(width: _avatarSize, height: _avatarSize);
    }

    // Each avatar's ring adds ~3pt of padding, so an avatar tile is
    // _avatarSize + 6. The first sits flush, every additional one advances
    // by (tile - overlap).
    const tile = _avatarSize + 6;
    final width = tile + (visible.length - 1) * (tile - _overlap);

    return SizedBox(
      width: width,
      height: tile,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < visible.length; i++)
            Positioned(
              left: i * (tile - _overlap),
              top: 0,
              child: GridAvatar(
                name: visible[i],
                size: _avatarSize,
                padding: 3,
              ),
            ),
        ],
      ),
    );
  }
}

class _TimerRow extends StatelessWidget {
  const _TimerRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: GridTokens.surface2,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        border: Border.all(color: GridTokens.hairline),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.history_rounded,
            size: 14,
            color: GridTokens.text3,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GridMono(
              label,
              color: GridTokens.text2,
              size: 11,
              letterSpacing: 0.06,
              uppercase: false,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
