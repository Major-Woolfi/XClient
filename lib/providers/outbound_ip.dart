import 'package:xclient/common/service_probe.dart';
import 'package:xclient/models/models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'core.dart';
import 'route_state.dart';
import 'routed_probe.dart';

part 'generated/outbound_ip.g.dart';

/// Ключован аутбаундом, который закрепляет поиск: имя узла, `DIRECT`, или
/// [routedOutbound] для того, что правила выбирают прямо сейчас.
@Riverpod(keepAlive: true)
class OutboundIpProbe extends _$OutboundIpProbe
    with RoutedProbe<String, IpInfo> {
  @override
  RoutedProbeState<String, IpInfo> build() => buildProbe();

  @override
  Future<Map<String, ProbeAnswer<IpInfo>>> probe(
    String target,
    RouteState route,
  ) async {
    final proxyName = target == routedOutbound && !route.proxied
        ? directOutbound
        : target;
    final result = await lookupOutboundIp(
      ref.read(coreHandlerProvider),
      proxyName,
    );
    final value = parseOutboundIp(result);
    final exit = result.chains.firstOrNull;
    return {
      target: ProbeAnswer(
        value: value,
        coreEpoch: result.coreEpoch,
        routeVersion: result.routeVersion,
        hits: result.hits,
      ),
      // Узел выходит через один и тот же адрес, его спросишь.
      if (value != null && exit != null && exit != target)
        exit: ProbeAnswer(
          value: value,
          coreEpoch: result.coreEpoch,
          routeVersion: result.routeVersion,
          hits: result.nodeHits,
        ),
    };
  }
}


