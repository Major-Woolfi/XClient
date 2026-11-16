import 'package:xclient/common/app_ports.dart';
import 'package:xclient/enum/enum.dart';
import 'package:xclient/models/models.dart';
import 'package:xclient/ui/icons/app_glyphs.dart';
import 'package:xclient/views/views.dart';

class Navigation implements NavigationPort {
  static Navigation? _instance;

  @override
  List<NavigationItem> getItems({
    bool openLogs = false,
    bool hasProxies = false,
  }) {
    return [
      NavigationItem(
        glyph: AppGlyphs.dashboard,
        label: PageLabel.dashboard,
        builder: (_) => const DashboardView(),
      ),
      NavigationItem(
        glyph: AppGlyphs.proxies,
        label: PageLabel.proxies,
        builder: (_) => const ProxiesView(),
        modes: hasProxies
            ? [NavigationItemMode.mobile, NavigationItemMode.desktop]
            : [],
      ),
      NavigationItem(
        glyph: AppGlyphs.profiles,
        label: PageLabel.profiles,
        builder: (_) => const ProfilesView(),
      ),
      NavigationItem(
        glyph: AppGlyphs.requests,
        label: PageLabel.requests,
        builder: (_) => const RequestsView(),
        modes: [NavigationItemMode.desktop, NavigationItemMode.moreFull],
      ),
      NavigationItem(
        glyph: AppGlyphs.dns,
        label: PageLabel.dns,
        builder: (_) => const DnsQueriesView(),
        modes: [NavigationItemMode.moreFull],
      ),
      NavigationItem(
        glyph: AppGlyphs.resources,
        label: PageLabel.resources,
        builder: (_) => const ResourcesView(),
        modes: [NavigationItemMode.more],
      ),
      NavigationItem(
        glyph: AppGlyphs.logs,
        label: PageLabel.logs,
        builder: (_) => const LogsView(),
        modes: openLogs
            ? [NavigationItemMode.desktop, NavigationItemMode.more]
            : [],
      ),
      NavigationItem(
        glyph: AppGlyphs.tools,
        label: PageLabel.tools,
        builder: (_) => const ToolsView(),
        modes: [NavigationItemMode.desktop, NavigationItemMode.mobile],
      ),
    ];
  }

  Navigation._internal();

  factory Navigation() {
    _instance ??= Navigation._internal();
    return _instance!;
  }
}

final navigation = Navigation();


