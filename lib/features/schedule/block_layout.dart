/// Overlap layout for one day column: tasks that overlap render side by
/// side instead of on top of each other (Google Calendar's behaviour).
/// Pure — unit-tested via the same cases the grid shows.
class BlockBox {
  const BlockBox({
    required this.taskId,
    required this.startMin,
    required this.endMin,
    required this.lane,
    required this.lanes,
  });

  final String taskId;

  /// Minutes-of-day.
  final int startMin;
  final int endMin;

  /// 0-based column within the overlap cluster.
  final int lane;

  /// How many columns the cluster needs (width = dayWidth / lanes).
  final int lanes;
}

/// Assigns each block a lane inside its overlap cluster. Greedy sweep: sort
/// by start; a block takes the first lane whose last block doesn't overlap.
/// `lanes` is the max lane count of the cluster the block belongs to.
List<BlockBox> layoutDayBlocks(
  List<({String taskId, int startMin, int endMin})> blocks,
) {
  final sorted = [...blocks]..sort((a, b) => a.startMin - b.startMin);
  final laneEnds = <int>[]; // lane -> last end minute
  final assigned = <({String taskId, int startMin, int endMin, int lane})>[];

  for (final b in sorted) {
    var lane = -1;
    for (var i = 0; i < laneEnds.length; i++) {
      if (laneEnds[i] <= b.startMin) {
        lane = i;
        break;
      }
    }
    if (lane == -1) {
      lane = laneEnds.length;
      laneEnds.add(b.endMin);
    } else {
      laneEnds[lane] = b.endMin;
    }
    assigned.add((
      taskId: b.taskId,
      startMin: b.startMin,
      endMin: b.endMin,
      lane: lane,
    ));
  }

  // Cluster width = number of lanes concurrently in use around the block —
  // approximated by counting blocks overlapping this one (incl. itself).
  return [
    for (final a in assigned)
      BlockBox(
        taskId: a.taskId,
        startMin: a.startMin,
        endMin: a.endMin,
        lane: a.lane,
        lanes: assigned
            .where((o) => o.startMin < a.endMin && a.startMin < o.endMin)
            .fold<int>(1, (m, o) => o.lane + 1 > m ? o.lane + 1 : m),
      ),
  ];
}
