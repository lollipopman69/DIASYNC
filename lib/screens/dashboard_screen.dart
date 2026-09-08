import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth      = FirebaseAuth.instance;

  double?   _glucose;
  bool      _pumpActive  = false;
  DateTime? _lastUpdated;
  String    _status      = 'Loading...';
  Color     _statusColor = Colors.grey;

  List<Map<String, dynamic>> _recentReadings = [];
  List<Map<String, dynamic>> _activeAlerts   = [];

  bool _loading = true;

  // Dynamic thresholds — loaded from medicalProfiles
  double _low          = 70;
  double _high         = 180;
  double _criticalLow  = 54;
  double _criticalHigh = 300;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // ── Data ──────────────────────────────────────────

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await Future.wait([
      _loadThresholds(),
      _loadRecentReadings(),
      _loadAlerts(),
    ]);
    await _loadLatestGlucose(); // after thresholds are set
  }

  Future<void> _loadThresholds() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await _firestore.collection('medicalProfiles').doc(uid).get();
      final data = doc.data();
      if (data != null) {
        setState(() {
          _low  = (data['targetGlucoseMin'] ?? 70).toDouble();
          _high = (data['targetGlucoseMax'] ?? 180).toDouble();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadLatestGlucose() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }

    try {
      final snap = await _firestore
          .collection('glucoseReadings')
          .where('patientID', isEqualTo: uid)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        final data    = snap.docs.first.data();
        final glucose = (data['glucoseLevel'] as num?)?.toDouble();
        final ts      = (data['timestamp'] as Timestamp?)?.toDate();
        setState(() {
          _glucose     = glucose;
          _lastUpdated = ts;
          _calcStatus(glucose);
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadRecentReadings() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await _firestore
          .collection('glucoseReadings')
          .where('patientID', isEqualTo: uid)
          .orderBy('timestamp', descending: true)
          .limit(8)
          .get();
      setState(() {
        _recentReadings = snap.docs.map((d) => d.data()).toList();
      });
    } catch (_) {}
  }

  Future<void> _loadAlerts() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await _firestore
          .collection('alerts')
          .where('patientID', isEqualTo: uid)
          .orderBy('timestamp', descending: true)
          .limit(5)
          .get();
      setState(() {
        _activeAlerts = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      });
    } catch (_) {}
  }

  Future<void> _refreshAll() async {
    setState(() => _loading = true);
    await _loadAll();
  }

  // ── Helpers ───────────────────────────────────────

  void _calcStatus(double? v) {
    if (v == null) {
      _status = 'No data';
      _statusColor = Colors.grey;
      return;
    }
    if (v < _criticalLow || v > _criticalHigh) {
      _status = 'CRITICAL';
      _statusColor = const Color(0xFFB71C1C);
    } else if (v < _low) {
      _status = 'LOW';
      _statusColor = const Color(0xFFE65100);
    } else if (v > _high) {
      _status = 'HIGH';
      _statusColor = const Color(0xFFFF6F00);
    } else {
      _status = 'NORMAL';
      _statusColor = const Color(0xFF2E7D32);
    }
  }

  Color _dotColor(double? v) {
    if (v == null) return Colors.grey;
    if (v < _criticalLow || v > _criticalHigh) return const Color(0xFFB71C1C);
    if (v < _low)  return const Color(0xFFE65100);
    if (v > _high) return const Color(0xFFFF6F00);
    return const Color(0xFF2E7D32);
  }

  String _hms(DateTime? dt) {
    if (dt == null) return '--';
    return '${_p(dt.hour)}:${_p(dt.minute)}:${_p(dt.second)}';
  }

  String _hmFromTs(dynamic ts) {
    if (ts == null) return '--';
    try {
      final dt = (ts as Timestamp).toDate();
      return '${_p(dt.hour)}:${_p(dt.minute)}';
    } catch (_) { return '--'; }
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  // ── Build ─────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D2E),
        title: const Text('Dashboard',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _refreshAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4FC3F7)))
          : RefreshIndicator(
              onRefresh: _refreshAll,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _glucoseCard(),
                    const SizedBox(height: 14),
                    _statusRow(),
                    const SizedBox(height: 14),
                    _thresholdBanner(),
                    const SizedBox(height: 14),
                    if (_activeAlerts.isNotEmpty) ...[
                      _alertsSection(),
                      const SizedBox(height: 14),
                    ],
                    _recentSection(),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
    );
  }

  // ── Widgets ───────────────────────────────────────

  Widget _glucoseCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _statusColor.withOpacity(0.55), width: 2),
        boxShadow: [
          BoxShadow(color: _statusColor.withOpacity(0.18), blurRadius: 22),
        ],
      ),
      child: Column(
        children: [
          const Text('Blood Glucose',
              style: TextStyle(color: Colors.white54, fontSize: 13, letterSpacing: 1.4)),
          const SizedBox(height: 10),
          Text(
            _glucose != null ? _glucose!.toStringAsFixed(1) : '--',
            style: TextStyle(
              color: _statusColor,
              fontSize: 78,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
          const Text('mg/dL',
              style: TextStyle(color: Colors.white38, fontSize: 15)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
            decoration: BoxDecoration(
              color: _statusColor.withOpacity(0.13),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _statusColor.withOpacity(0.4)),
            ),
            child: Text(_status,
                style: TextStyle(
                    color: _statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
          ),
          const SizedBox(height: 10),
          Text('Last updated: ${_hms(_lastUpdated)}',
              style: const TextStyle(color: Colors.white30, fontSize: 11)),
        ],
      ),
    );
  }

  // Shows doctor-set target range
  Widget _thresholdBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4FC3F7).withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.track_changes, color: Color(0xFF4FC3F7), size: 14),
          const SizedBox(width: 6),
          Text(
            'Doctor target range: ${_low.toInt()}–${_high.toInt()} mg/dL',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _statusRow() {
    return Row(
      children: [
        Expanded(child: _tile(
          Icons.water_drop,
          _pumpActive ? 'ACTIVE' : 'IDLE',
          'Pump',
          _pumpActive ? const Color(0xFF4FC3F7) : Colors.white38,
        )),
        const SizedBox(width: 10),
        Expanded(child: _tile(
          Icons.bluetooth_connected,
          'Demo',
          'Device',
          Colors.orange,
        )),
        const SizedBox(width: 10),
        Expanded(child: _tile(
          Icons.notifications_active,
          '${_activeAlerts.length}',
          'Alerts',
          _activeAlerts.isNotEmpty ? Colors.orange : Colors.white38,
        )),
      ],
    );
  }

  Widget _tile(IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ]),
    );
  }

  Widget _alertsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Recent Alerts',
            style: TextStyle(
                color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ..._activeAlerts.map((a) {
          final type = a['type'] as String? ?? 'INFO';
          final color = type == 'CRITICAL'
              ? const Color(0xFFB71C1C)
              : type == 'LOW'
                  ? const Color(0xFFE65100)
                  : type == 'HIGH'
                      ? const Color(0xFFFF6F00)
                      : Colors.white38;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Row(children: [
                Icon(Icons.warning_amber_rounded, color: color, size: 18),
                const SizedBox(width: 10),
                Expanded(
                 child: Text(a['message'] ?? 'Alert',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ),
                GestureDetector(
                  onTap: () async {
                    final id = a['id'] as String?;
                    if (id != null) {
                      await _firestore.collection('alerts').doc(id).update({
                        'resolved': true,
                        'resolvedAt': FieldValue.serverTimestamp(),
                      });
                      await _loadAlerts();
                    }
                  },
                  child: const Icon(Icons.close, color: Colors.white24, size: 16),
                ),
              ]),
          );
        }),
      ],
    );
  }

  Widget _recentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Recent Readings',
            style: TextStyle(
                color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1D2E),
            borderRadius: BorderRadius.circular(14),
          ),
          child: _recentReadings.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text('No readings yet',
                        style: TextStyle(color: Colors.white38)),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _recentReadings.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Colors.white12, height: 1),
                  itemBuilder: (_, i) {
                    final r   = _recentReadings[i];
                    final val = (r['glucoseLevel'] as num?)?.toDouble();
                    final dotC = _dotColor(val);
                    return ListTile(
                      leading: Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(
                          color: dotC,
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(
                        val != null ? '${val.toStringAsFixed(1)} mg/dL' : '--',
                        style: TextStyle(color: dotC, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      trailing: Text(
                        _hmFromTs(r['timestamp']),
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}