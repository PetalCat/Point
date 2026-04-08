import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../theme.dart';
import '../providers.dart';
import 'filter_bar.dart';
import 'person_row.dart';
import 'item_row.dart';
import '../screens/group_detail_screen.dart';
import 'ghost_bottom_sheet.dart';

class PeopleDrawer extends ConsumerWidget {
  final ScrollController? scrollController;
  final FilterMode filterMode;
  final Function(String userId)? onPersonTap;

  const PeopleDrawer({
    super.key,
    this.scrollController,
    this.filterMode = FilterMode.all,
    this.onPersonTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationState = ref.watch(locationProvider);
    final itemState = ref.watch(itemProvider);
    final groupState = ref.watch(groupProvider);

    final people = locationState.people.values.toList();
    people.sort((a, b) {
      if (a.online != b.online) return a.online ? -1 : 1;
      return b.timestamp.compareTo(a.timestamp);
    });

    final items = itemState.items;
    final groups = groupState.groups;

    final showPeople =
        filterMode == FilterMode.all || filterMode == FilterMode.people;
    final showGroups = filterMode == FilterMode.groups;
    final showItems =
        filterMode == FilterMode.all || filterMode == FilterMode.items;

    final title = switch (filterMode) {
      FilterMode.all => 'All',
      FilterMode.people => 'People',
      FilterMode.groups => 'Groups',
      FilterMode.items => 'Items',
    };

    // Build list widgets
    final listWidgets = <Widget>[];

    if (showGroups) {
      // Show group cards
      for (var i = 0; i < groups.length; i++) {
        final g = groups[i];
        if (i > 0) listWidgets.add(const _Divider());
        listWidgets.add(_GroupRow(group: g));
      }
    } else {
      if (showPeople && people.isNotEmpty) {
        if (filterMode == FilterMode.all)
          listWidgets.add(const _SectionLabel(text: 'People'));
        for (var i = 0; i < people.length; i++) {
          if (listWidgets.isNotEmpty && listWidgets.last is! _SectionLabel)
            listWidgets.add(const _Divider());
          listWidgets.add(
            GestureDetector(
              onTap: () => onPersonTap?.call(people[i].userId),
              child: PersonRow(person: people[i]),
            ),
          );
        }
      }

      if (showItems && items.isNotEmpty) {
        if (filterMode == FilterMode.all)
          listWidgets.add(const _SectionLabel(text: 'Items'));
        for (var i = 0; i < items.length; i++) {
          if (listWidgets.isNotEmpty && listWidgets.last is! _SectionLabel)
            listWidgets.add(const _Divider());
          listWidgets.add(ItemRow(item: items[i]));
        }
      }
    }

    final isEmpty = listWidgets.isEmpty;

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.dividerClr,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: context.primaryText,
                      ),
                    ),
                    const Spacer(),
                    _SharingToggle(locationState: locationState),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                'Nothing here yet',
                style: TextStyle(fontSize: 14, color: context.tertiaryText),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => listWidgets[index],
              childCount: listWidgets.length,
            ),
          ),
      ],
    );
  }
}

class _GroupRow extends StatelessWidget {
  final dynamic group; // Group model

  const _GroupRow({required this.group});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupDetailScreen(groupId: group.id),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: PointColors.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  group.name[0].toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: context.primaryText,
                    ),
                  ),
                  Text(
                    '${group.members.length} member${group.members.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 10,
                      color: context.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            // Member stack
            SizedBox(
              width: (group.members.length.clamp(0, 4) * 18.0) + 8,
              height: 24,
              child: Stack(
                children: [
                  ...group.members.take(4).toList().asMap().entries.map((e) {
                    final m = e.value;
                    final name = m.userId.split('@').first;
                    return Positioned(
                      left: e.key * 16.0,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: PointColors.colorForUser(m.userId),
                          shape: BoxShape.circle,
                          border: Border.all(color: context.cardBg, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            name[0].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              '\u203A',
              style: TextStyle(color: PointColors.textTertiary, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _SharingToggle extends StatelessWidget {
  final dynamic locationState;

  const _SharingToggle({required this.locationState});

  @override
  Widget build(BuildContext context) {
    final ghost = locationState.isGhostMode;

    return GestureDetector(
      onTap: () => GhostBottomSheet.show(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: ghost ? const Color(0xFF2C2C2E) : PointColors.accent,
          borderRadius: BorderRadius.circular(22),
          boxShadow: ghost
              ? null
              : [
                  const BoxShadow(
                    color: PointColors.accentGlow,
                    blurRadius: 14,
                    offset: Offset(0, 3),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ghost ? '\u{1F47B}' : '\u{1F4CD}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(width: 5),
            Text(
              ghost ? 'Ghost' : 'Live',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: context.tertiaryText,
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: context.dividerClr,
      indent: 16,
      endIndent: 16,
    );
  }
}
