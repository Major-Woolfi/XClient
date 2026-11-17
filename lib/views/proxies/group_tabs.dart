import 'dart:math';

import 'package:xclient/common/common.dart';
import 'package:xclient/models/common.dart';
import 'package:xclient/ui/icons/icons.dart';
import 'package:xclient/widgets/widgets.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

const _stripInset = 16.0;
const _tabSpacing = 8.0;
const _tabPadding = 16.0;

/// Групповые чипы над видом табов прокси. Строятся только чипы в виду:
/// ширина каждого чипа берется из его надписи, поэтому полоса может прокрутить
/// к тому, что еще не построила.
class GroupTabs extends StatefulWidget {
  const GroupTabs({super.key, required this.controller, required this.groups});

  final TabController controller;
  final List<Group> groups;

  @override
  State<GroupTabs> createState() => _GroupTabsState();
}

class _GroupTabsState extends State<GroupTabs> {
  static const _fadeExtent = 24.0;

  // Контроллер листа отдал бы перетаскивания полосы листу.
  final _scrollController = ScrollController();
  final _hasMore = ValueNotifier(false);
  final _fade = ValueNotifier(0.0);
  late final _selected = ValueNotifier(widget.controller.index);
  _TabExtents? _extents;

  @override
  void initState() {
    super.initState();
    _follow(widget.controller);
  }

  @override
  void didUpdateWidget(GroupTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.animation?.removeListener(_handleAnimation);
      _follow(widget.controller);
    }
  }

  @override
  void dispose() {
    widget.controller.animation?.removeListener(_handleAnimation);
    _scrollController.dispose();
    _hasMore.dispose();
    _fade.dispose();
    _selected.dispose();
    super.dispose();
  }

  void _follow(TabController controller) {
    _selected.value = controller.index;
    controller.animation!.addListener(_handleAnimation);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(jump: true));
  }

  // Клик анимирует через каждый таб между; считаются только проходы свайпа.
  void _handleAnimation() {
    final controller = widget.controller;
    final index = controller.indexIsChanging
        ? controller.index
        : controller.animation!.value.round();
    if (index == _selected.value) {
      return;
    }
    _selected.value = index;
    _reveal();
  }

  void _reveal({bool jump = false}) {
    final extents = _extents;
    if (!mounted || extents == null || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final index = _selected.value;
    if (!position.hasContentDimensions ||
        index < 0 ||
        index >= extents.widths.length) {
      return;
    }
    final center =
        _stripInset + extents.starts[index] + extents.widths[index] / 2;
    final target = (center - position.viewportDimension / 2).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (jump) {
      position.jumpTo(target);
    } else {
      position.animateTo(
        target,
        duration: commonDuration,
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _select(int index) {
    widget.controller.animateTo(index);
  }

  bool _handleMetrics(ScrollMetrics metrics) {
    _fade.value = (metrics.extentAfter / _fadeExtent).clamp(0.0, 1.0);
    final hasMore = metrics.maxScrollExtent > 0;
    if (hasMore != _hasMore.value) {
      _hasMore.value = hasMore;
      // Кнопка «Еще» сужает вкладки, которые она перекрывает.
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(jump: true));
    }
    return false;
  }

  Shader _buildEdgeFade(Rect bounds, double fade) {
    return LinearGradient(
      begin: AlignmentDirectional.centerStart,
      end: AlignmentDirectional.centerEnd,
      colors: [
        Colors.black,
        Colors.black.withValues(alpha: 1 - fade),
      ],
      stops: [max(0.0, 1 - _fadeExtent / bounds.width), 1],
    ).createShader(bounds, textDirection: Directionality.of(context));
  }

  Widget _buildMoreButton() {
    return TonalButtonTheme(
      size: TonalButtonSize.section,
      child: ElasticPress(
        child: PopupAnchor(
          targetBuilder: (open) => IconButton(
            tooltip: context.appLocalizations.proxyGroup,
            onPressed: open,
            icon: const GlyphIcon(AppGlyphs.chevronDown),
          ),
          popupBuilder: (_) => PopupMenu(
            maxVisibleItems: 7,
            items: [
              for (final (index, group) in widget.groups.indexed)
                PopupMenuItem(
                  label: group.name,
                  checked: index == widget.controller.index,
                  onPressed: () => _select(index),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabs(_TabExtents extents, bool hasMore) {
    final groups = widget.groups;
    final last = groups.length - 1;
    return ListView.custom(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      padding: EdgeInsetsDirectional.only(
        start: _stripInset,
        end: hasMore ? 0 : _stripInset,
      ),
      itemExtentBuilder: (index, _) => index < extents.widths.length
          ? extents.widths[index] + (index < last ? _tabSpacing : 0)
          : null,
      childrenDelegate: _TabsDelegate(
        (_, index) => Padding(
          padding: EdgeInsetsDirectional.only(
            end: index < last ? _tabSpacing : 0,
          ),
          child: _GroupTab(
            name: groups[index].name,
            index: index,
            selected: _selected,
            onPressed: () => _select(index),
          ),
        ),
        childCount: groups.length,
        extent: extents.total,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final extents = _extents = _TabExtents.of(context, widget.groups, _extents);
    return SizedBox(
      height: TonalButtonSize.section.button,
      child: ValueListenableBuilder(
        valueListenable: _hasMore,
        builder: (_, hasMore, moreButton) {
          return Row(
            children: [
              Expanded(
                child: NotificationListener<ScrollMetricsNotification>(
                  onNotification: (notification) =>
                      _handleMetrics(notification.metrics),
                  child: NotificationListener<ScrollUpdateNotification>(
                    onNotification: (notification) =>
                        _handleMetrics(notification.metrics),
                    child: ValueListenableBuilder(
                      valueListenable: _fade,
                      builder: (_, fade, child) => ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (bounds) =>
                            _buildEdgeFade(bounds, fade),
                        child: child,
                      ),
                      child: _buildTabs(extents, hasMore),
                    ),
                  ),
                ),
              ),
              if (hasMore)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8, end: 16),
                  child: moreButton,
                ),
            ],
          );
        },
        child: _buildMoreButton(),
      ),
    );
  }
}

/// Ширина, которую чип отводит под надпись, высчитанная так, как
/// [Card] подгоняет размер своей кнопки.
class _TabExtents {
  _TabExtents._(this._key, this.widths) : starts = _startsOf(widths);

  final Object _key;
  final List<double> widths;
  final List<double> starts;

  double get total => widths.isEmpty ? 0 : starts.last + widths.last;

  static List<double> _startsOf(List<double> widths) {
    final starts = <double>[];
    var start = 0.0;
    for (final width in widths) {
      starts.add(start);
      start += width + _tabSpacing;
    }
    return starts;
  }

  static _TabExtents of(
    BuildContext context,
    List<Group> groups,
    _TabExtents? previous,
  ) {
    final style = AppTextStyle.subheadline.of(context, emphasized: true);
    final minWidth = Card.minimumOf(context).minWidth;
    final padding = Card.paddingOf(
      context,
      const EdgeInsets.symmetric(horizontal: _tabPadding),
    ).horizontal;
    final names = [for (final group in groups) group.name];
    final key = (
      _NamesKey(names),
      style,
      MediaQuery.boldTextOf(context),
      MediaQuery.textScalerOf(context),
      Directionality.of(context),
      Localizations.maybeLocaleOf(context),
      minWidth,
      padding,
    );
    if (previous != null && previous._key == key) {
      return previous;
    }
    return _TabExtents._(key, [
      for (final name in names)
        max(
          minWidth,
          EmojiText.widthOf(context, name, style).ceilToDouble() + padding,
        ),
    ]);
  }
}

/// Сообщает всю длину полосы, которую список с разными экстентами в противном
/// случае экстраполировал бы из построенных чипов.
class _TabsDelegate extends SliverChildBuilderDelegate {
  _TabsDelegate(
    super.builder, {
    required super.childCount,
    required this.extent,
  }) : super(addAutomaticKeepAlives: false);

  final double extent;

  @override
  double? estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) => extent;
}

class _NamesKey {
  const _NamesKey(this.names);

  final List<String> names;

  @override
  bool operator ==(Object other) =>
      other is _NamesKey && stringListEquality.equals(names, other.names);

  @override
  int get hashCode => stringListEquality.hash(names);
}

/// Перестраивается только при получении или потере выбора, так что свайп через
/// сотни групп перестраивает два таба на шаг вместо всей полосы.
class _GroupTab extends StatefulWidget {
  const _GroupTab({
    required this.name,
    required this.index,
    required this.selected,
    required this.onPressed,
  });

  final String name;
  final int index;
  final ValueListenable<int> selected;
  final VoidCallback onPressed;

  @override
  State<_GroupTab> createState() => _GroupTabState();
}

class _GroupTabState extends State<_GroupTab> {
  late bool _isSelected;

  @override
  void initState() {
    super.initState();
    _isSelected = widget.selected.value == widget.index;
    widget.selected.addListener(_handleSelected);
  }

  @override
  void didUpdateWidget(_GroupTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      oldWidget.selected.removeListener(_handleSelected);
      widget.selected.addListener(_handleSelected);
    }
    _isSelected = widget.selected.value == widget.index;
  }

  @override
  void dispose() {
    widget.selected.removeListener(_handleSelected);
    super.dispose();
  }

  void _handleSelected() {
    final isSelected = widget.selected.value == widget.index;
    if (isSelected != _isSelected) {
      setState(() => _isSelected = isSelected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _isSelected;
    final colorScheme = context.colorScheme;
    return Card(
      isSelected: selected,
      fillsSelection: true,
      shape: AppShape.full,
      padding: const EdgeInsets.symmetric(horizontal: _tabPadding),
      onPressed: widget.onPressed,
      child: AnimatedDefaultTextStyle(
        duration: midDuration,
        style: AppTextStyle.subheadline
            .of(context, emphasized: true)
            .copyWith(
              color: selected
                  ? colorScheme.onPrimary
                  : colorScheme.onSurfaceVariant,
            ),
        child: EmojiText(widget.name, maxLines: 1),
      ),
    );
  }
}
