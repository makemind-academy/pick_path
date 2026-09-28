import 'dart:async';
import 'dart:convert';

import 'package:mcp_server/mcp_server.dart';

import 'serve_bundle.dart';

/// pick_server — a picking list for one order.
///
/// An order arrives in the sequence the customer typed it. A person picking it
/// walks the racks in the sequence the racks are in. Those are two different
/// sequences, and printing the first one makes somebody walk the aisle four
/// times.
///
/// So the order of the list is not data that came in. It is computed here from
/// where things are, and the walk is measured both ways so the difference is
/// on the screen rather than in a claim.
void main(List<String> args) async {
  const config = McpServerConfig(
    name: 'Pick Path',
    version: '1.0.0',
    capabilities: ServerCapabilities(
      tools: ToolsCapability(listChanged: true),
      resources: ResourcesCapability(listChanged: true),
    ),
  );
  final server = McpServer.createServer(config);
  PickServer(server).register();
  // The screen next door: AppPlayer reads it from here and sends the pages'
  // tool calls back to the tools above.
  registerBundleUi(server, '../pick.mbd');
  final transport = McpServer.createStdioTransport().get();
  server.connect(transport);
  await Completer<void>().future;
}

/// Where something lives. Aisle, then bay along that aisle, then shelf height.

/// "1 order", "2 orders". A screen that says "1 orders" is a screen
/// nobody proofread.
String _plural(int n, String one) => "$n $one" + (n == 1 ? "" : "s");

class Slot {
  const Slot(this.aisle, this.bay, this.level);

  final int aisle;
  final int bay;
  final int level;

  String get label => 'A$aisle-${bay.toString().padLeft(2, '0')}-L$level';
}

class Line {
  Line(this.sku, this.name, this.want, this.slot, this.onHand);

  final String sku;
  final String name;
  final int want;
  final Slot slot;
  final int onHand;

  int picked = 0;

  /// What is left to find, once the bin has been emptied.
  int get short => want - picked;
}

class PickServer {
  PickServer(this.server);

  final Server server;

  /// The order as it was typed by whoever placed it. Deliberately in a silly
  /// sequence — this is what an order looks like.
  final _lines = <Line>[
    Line('SKU-8841', 'Blue mug', 3, const Slot(4, 12, 2), 9),
    Line('SKU-2210', 'Notebook A5', 6, const Slot(1, 3, 1), 6),
    Line('SKU-7002', 'Desk lamp', 1, const Slot(4, 2, 3), 4),
    Line('SKU-1183', 'Cable tidy', 4, const Slot(2, 9, 1), 2),
    Line('SKU-5560', 'Pen box', 2, const Slot(1, 14, 2), 8),
  ];

  int _cursor = 0;

  /// Distance for a walk that visits [order] in sequence, starting at the door.
  ///
  /// Crude on purpose: moving along an aisle costs one per bay, and changing
  /// aisle costs the walk to the end and back. It does not need to be a real
  /// floor plan to show that the two sequences are not the same length.
  int _walk(List<Line> order) {
    var here = const Slot(0, 0, 0);
    var steps = 0;
    for (final l in order) {
      if (l.slot.aisle != here.aisle) {
        steps += here.bay + 8 + l.slot.bay;
      } else {
        steps += (l.slot.bay - here.bay).abs();
      }
      here = l.slot;
    }
    return steps;
  }

  List<Line> get _asTyped => List.of(_lines);

  /// The same lines, in the sequence a person actually walks.
  List<Line> get _walkOrder => List.of(_lines)
    ..sort((a, b) {
      final byAisle = a.slot.aisle.compareTo(b.slot.aisle);
      if (byAisle != 0) return byAisle;
      return a.slot.bay.compareTo(b.slot.bay);
    });

  void register() {
    server.addTool(
      name: 'pick.state',
      description: 'The picking list in walking order, with the walk measured',
      inputSchema: const {'type': 'object', 'properties': {}},
      handler: (args) async => _state(),
    );

    server.addTool(
      name: 'pick.take',
      description: 'Pick what is actually in the bin at the current stop',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'count': {'type': 'integer'},
        },
        'required': ['count'],
      },
      handler: (args) async {
        final order = _walkOrder;
        if (_cursor >= order.length) return _state(notice: 'nothing left');
        final line = order[_cursor];
        final took = args['count'] as int;
        line.picked = took;
        _cursor++;
        // A short pick is not a failure to record. It is the thing the office
        // needs to know before the van leaves, so it stays on the line.
        final note = line.short > 0
            ? '${line.sku} short ${line.short} — bin had $took'
            : '${line.sku} complete';
        return _state(notice: note);
      },
    );
  }

  CallToolResult _state({String notice = ''}) {
    final order = _walkOrder;
    final typedWalk = _walk(_asTyped);
    final pathWalk = _walk(order);
    final shortLines = _lines.where((l) => l.picked > 0 && l.short > 0).toList();

    return CallToolResult(content: [
      TextContent(
        text: jsonEncode({
          'rows': [
            for (var i = 0; i < order.length; i++)
              {
                'stop': '${i + 1}',
                'slot': order[i].slot.label,
                'name': '${order[i].want} x ${order[i].name}',
                'state': i < _cursor
                    ? (order[i].short > 0 ? 'SHORT ${order[i].short}' : 'picked')
                    : (i == _cursor ? 'go here' : ''),
                'here': i == _cursor,
                'short': i < _cursor && order[i].short > 0,
              },
          ],
          'stops': order.length,
          // The rule a picker works to, printed on the cart's own screen: what
          // to do when the slot has fewer than the line asks for.
          'aisleRule': 'Short-pick what is there · never leave the stop empty-handed',
          'done': _cursor,
          'typedWalk': _plural(typedWalk, 'step'),
          'pathWalk': _plural(pathWalk, 'step'),
          'saved': '${typedWalk - pathWalk} steps',
          'shortCount': shortLines.length,
          'shortLine': shortLines.isEmpty
              ? 'nothing short'
              : shortLines
                  .map((l) => '${l.sku} short ${l.short}')
                  .join(' · '),
          'notice': notice,
        }),
      )
    ]);
  }
}
