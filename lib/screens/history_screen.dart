import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth      = FirebaseAuth.instance;

  final List<Map<String, dynamic>> _readings = [];
  DocumentSnapshot? _lastDoc;
  bool _loading = false;
  bool _hasMore = true;

  String _filter = 'All'; // All | Normal | Low | High | Critical

  static const int    _pageSize    = 20;
  static const double _criticalLow  = 54;
  static const double _low          = 70;
  static const double _high         = 180;
  static const double _criticalHigh = 300;

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchPage();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !_loading && _hasMore) {
        _fetchPage();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ────────────────────────────────────────────────
  // Data
  // ────────────────────────────────────────────────

  Future<void> _fetchPage() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);

    final uid = _auth.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }

    try {
      Query query = _firestore
          .collection('glucoseReadings')
          .where('patientID', isEqualTo: uid)
          .orderBy('timestamp', descending: true)
          .limit(_pageSize);

      if (_lastDoc != null) query = query.startAfterDocument(_lastDoc!);

      final snap = await query.get();

      if (snap.docs.isEmpty) {
        setState(() { _hasMore = false; _loading = false; });
        return;
      }

      _lastDoc = snap.docs.last;
      final newItems = snap.docs.map((d) => d.data() as Map<String, dynamic>).toList();

      setState(() {
        _readings.addAll(newItems);
        _hasMore = snap.docs.length == _pageSize;
        _loading = false;
      });
    } catch (e) {
      // fallback without orderBy if index not ready
      try {
        final snap = await _firestore
            .collection('glucoseReadings')
            .where('patientID', isEqualTo: uid)
            .limit(100)
            .get();

        final items = snap.docs.map((d) => d.data() as Map<String, dynamic>).toList();
        items.sort((a, b) {
          final ta = (a['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          final tb = (b['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          return tb.compareTo(ta);
        });

        setState(() {
          _readings.addAll(items);
          _hasMore = false;
          _loading = false;
        });
      } catch (_) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _readings.clear();
      _lastDoc = null;
      _hasMore = true;
    });
    await _fetchPage();
  }

  // ────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────

  String _label(double? v) {
    if (v == null) return 'Unknown';
    if (v < _criticalLow || v > _criticalHigh) return 'Critical';
    if (v < _low)  return 'Low';
    if (v > _high) return 'High';
    return 'Normal';
  }

  Color _color(double? v) {
    if (v == null) return Colors.grey;
    if (v < _criticalLow || v > _criticalHigh) return const Color(0xFFB71C1C);
    if (v < _low)  return const Color(0xFFE65100);
    if (v > _high) return const Color(0xFFFF6F00);
    return const Color(0xFF2E7D32);
  }

  String _formatTs(dynamic ts) {
    if (ts == null) return '--';
    try {
      final dt   = (ts as Timestamp).toDate();
      final date = '${dt.day.toString().padLeft(2,'0')}/'
                   '${dt.month.toString().padLeft(2,'0')}/'
                   '${dt.year}';
      final time = '${dt.hour.toString().padLeft(2,'0')}:'
                   '${dt.minute.toString().padLeft(2,'0')}';
      return '$date  $time';
    } catch (_) { return '--'; }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'All') return _readings;
    return _readings.where((r) {
      final v = (r['glucoseLevel'] as num?)?.toDouble();
      return _label(v) == _filter;
    }).toList();
  }

  // ────────────────────────────────────────────────
  // Build
  // ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D2E),
        title: const Text('History',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          _filterBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: filtered.isEmpty && !_loading
                  ? _emptyState()
                  : ListView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                      itemCount: filtered.length + (_hasMore ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i == filtered.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFF4FC3F7), strokeWidth: 2),
                            ),
                          );
                        }
                        return _readingTile(filtered[i]);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────
  // Widgets
  // ────────────────────────────────────────────────

  Widget _filterBar() {
    const filters = ['All', 'Normal', 'Low', 'High', 'Critical'];
    return Container(
      color: const Color(0xFF1A1D2E),
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: filters.map((f) {
          final active = _filter == f;
          return GestureDetector(
            onTap: () => setState(() => _filter = f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: active ? const Color(0xFF4FC3F7) : Colors.white10,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(f,
                  style: TextStyle(
                    color: active ? Colors.black87 : Colors.white54,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  )),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _readingTile(Map<String, dynamic> r) {
    final val   = (r['glucoseLevel'] as num?)?.toDouble();
    final color = _color(val);
    final label = _label(val);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                val != null ? val.toStringAsFixed(1) : '--',
                style: TextStyle(
                    color: color, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const Text('mg/dL',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_formatTs(r['timestamp']),
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                if (r['source'] != null) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.device_hub, color: Color(0xFF4FC3F7), size: 12),
                    const SizedBox(width: 4),
                    Text('${r['source']}',
                        style: const TextStyle(
                            color: Color(0xFF4FC3F7), fontSize: 11)),
                  ]),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.35)),
            ),
            child: Text(label,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.history, color: Colors.white12, size: 56),
          const SizedBox(height: 12),
          Text(
            _filter == 'All' ? 'No readings recorded yet' : 'No "$_filter" readings found',
            style: const TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
    );
  }
}