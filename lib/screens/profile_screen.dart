import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth      = FirebaseAuth.instance;

  Map<String, dynamic>? _patient;
  Map<String, dynamic>? _medProfile;
  Map<String, dynamic>? _device;
  Map<String, dynamic>? _emergency;

  bool _loading = true;

  static const Map<String, dynamic> _fakeDevice = {
    'deviceID'        : 'DIAS-ESP32-DEMO',
    'model'           : 'DiASync v1.0 (ESP32)',
    'firmwareVersion' : 'v0.9.1-beta',
    'status'          : 'Demo Mode',
    'lastSync'        : 'Not connected yet',
  };

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // ── Data ──────────────────────────────────────────

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    final uid = _auth.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }

    try {
      final results = await Future.wait([
        _firestore.collection('patients').doc(uid).get(),
        _firestore.collection('medicalProfiles').doc(uid).get(),
        _firestore.collection('emergencyContacts').doc(uid).get(),
        _firestore.collection('devices').doc(uid).get(),
      ]);

      final patientSnap   = results[0] as DocumentSnapshot;
      final medSnap       = results[1] as DocumentSnapshot;
      final emergencySnap = results[2] as DocumentSnapshot;
      final deviceSnap    = results[3] as DocumentSnapshot;

      setState(() {
        _patient    = patientSnap.exists   ? patientSnap.data()   as Map<String, dynamic> : null;
        _medProfile = medSnap.exists       ? medSnap.data()       as Map<String, dynamic> : null;
        _emergency  = emergencySnap.exists ? emergencySnap.data() as Map<String, dynamic> : null;
        _device     = deviceSnap.exists    ? deviceSnap.data()    as Map<String, dynamic> : _fakeDevice;
        _loading    = false;
      });
    } catch (e) {
      setState(() {
        _device  = _fakeDevice;
        _loading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();
  }

  Future<void> _showChangeDeviceDialog() async {
    final controller = TextEditingController(
      text: _device?['deviceID'] ?? '',
    );
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.device_hub, color: Color(0xFF4FC3F7), size: 20),
            SizedBox(width: 8),
            Text('Connect Device', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your ESP32 Device ID or tap the QR icon to scan.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. ESP32-DiASync',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF0F1117),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF4FC3F7)),
                ),
                suffixIcon: IconButton(
                  tooltip: 'Scan QR Code',
                  icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF4FC3F7)),
                  onPressed: () {
                    // Simulates QR scan result for demo
                    controller.text = 'ESP32-DiASync';
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('QR scanned: ESP32-DiASync'),
                        backgroundColor: Color(0xFF4FC3F7),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tip: Tap the QR icon to auto-fill from your device\'s QR code.',
              style: TextStyle(color: Colors.white24, fontSize: 10),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4FC3F7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.link, color: Colors.black, size: 16),
            label: const Text('Connect', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            onPressed: () async {
              final uid = _auth.currentUser!.uid;
              final deviceData = {
                'deviceID'        : controller.text.trim(),
                'model'           : 'DiASync v1.0 (ESP32)',
                'firmwareVersion' : 'v0.9.1-beta',
                'status'          : 'Connected',
                'lastSync'        : DateTime.now().toString(),
              };
              await _firestore.collection('devices').doc(uid).set(deviceData);
              setState(() => _device = deviceData);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Device ${controller.text.trim()} connected!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D2E),
        title: const Text('Profile',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadProfile,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
            onPressed: _showLogoutConfirm,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4FC3F7)))
          : RefreshIndicator(
              onRefresh: _loadProfile,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _avatarHeader(),
                    const SizedBox(height: 20),
                    _section('Patient Info', Icons.person, _patientRows()),
                    const SizedBox(height: 14),
                    _section('Medical Profile', Icons.medical_information, _medRows()),
                    const SizedBox(height: 14),
                    _deviceSection(),
                    const SizedBox(height: 14),
                    _section('Emergency Contact', Icons.emergency, _emergencyRows()),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
    );
  }

  // ── Logout confirm ────────────────────────────────

  Future<void> _showLogoutConfirm() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(color: Colors.white54)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) await _signOut();
  }

  // ── Widgets ───────────────────────────────────────

  Widget _avatarHeader() {
    final name  = _patient?['name'] as String? ?? 'Patient';
    final email = _auth.currentUser?.email ?? '';
    final diabetesType = _patient?['diabetesType'] as String? ?? '';

    return Row(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: const Color(0xFF4FC3F7).withOpacity(0.15),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : 'P',
            style: const TextStyle(
                color: Color(0xFF4FC3F7), fontSize: 28, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(email,
                  style: const TextStyle(color: Colors.white38, fontSize: 13)),
              if (diabetesType.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4FC3F7).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF4FC3F7).withOpacity(0.3)),
                  ),
                  child: Text(diabetesType,
                      style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 11)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(String title, IconData icon, List<_Row> rows) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              Icon(icon, color: const Color(0xFF4FC3F7), size: 18),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      color: Color(0xFF4FC3F7),
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ]),
          ),
          const Divider(color: Colors.white10, height: 1),
          ...rows.map((r) => _infoRow(r.label, r.value)),
        ],
      ),
    );
  }

  Widget _deviceSection() {
    final isDemo = _device == _fakeDevice ||
        (_device?['status'] == 'Demo Mode');
    final isConnected = _device?['status'] == 'Connected';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E),
        borderRadius: BorderRadius.circular(14),
        border: isDemo
            ? Border.all(color: Colors.orange.withOpacity(0.4), width: 1)
            : isConnected
                ? Border.all(color: Colors.green.withOpacity(0.4), width: 1)
                : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.device_hub, color: Color(0xFF4FC3F7), size: 18),
                const SizedBox(width: 8),
                const Text('Device',
                    style: TextStyle(
                        color: Color(0xFF4FC3F7),
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                const Spacer(),
                if (isDemo)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.5)),
                    ),
                    child: const Text('Not Connected',
                        style: TextStyle(color: Colors.orange, fontSize: 10)),
                  ),
                if (isConnected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withOpacity(0.5)),
                    ),
                    child: const Text('Connected',
                        style: TextStyle(color: Colors.green, fontSize: 10)),
                  ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _showChangeDeviceDialog,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4FC3F7).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.edit, color: Color(0xFF4FC3F7), size: 14),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          ..._deviceRows().map((r) => _infoRow(r.label, r.value)),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ── Row builders ──────────────────────────────────

  List<_Row> _patientRows() => [
    _Row('Name',          _val(_patient, 'name')),
    _Row('Date of Birth', _val(_patient, 'dateOfBirth')),
    _Row('Gender',        _val(_patient, 'gender')),
    _Row('Phone',         _val(_patient, 'phone')),
    _Row('Address',       _val(_patient, 'address')),
    _Row('Diabetes Type', _val(_patient, 'diabetesType')),
  ];

  List<_Row> _medRows() => [
    _Row('Target Min',   _valUnit(_medProfile, 'targetGlucoseMin', 'mg/dL')),
    _Row('Target Max',   _valUnit(_medProfile, 'targetGlucoseMax', 'mg/dL')),
    _Row('Insulin Type', _val(_medProfile, 'insulinType')),
    _Row('Basal Rate',   _valUnit(_medProfile, 'basalRate', 'U/hr')),
    _Row('Doctor ID',    _val(_medProfile, 'doctorID')),
  ];

  List<_Row> _deviceRows() => [
    _Row('Device ID', _val(_device, 'deviceID')),
    _Row('Model',     _val(_device, 'model')),
    _Row('Firmware',  _val(_device, 'firmwareVersion')),
    _Row('Status',    _val(_device, 'status')),
    _Row('Last Sync', _val(_device, 'lastSync')),
  ];

  List<_Row> _emergencyRows() => [
    _Row('Name',         _val(_emergency, 'name')),
    _Row('Relationship', _val(_emergency, 'relationship')),
    _Row('Phone',        _val(_emergency, 'phone')),
  ];

  // ── Helpers ───────────────────────────────────────

  String _val(Map<String, dynamic>? map, String key) =>
      map?[key]?.toString().isNotEmpty == true ? map![key].toString() : '--';

  String _valUnit(Map<String, dynamic>? map, String key, String unit) {
    final v = map?[key];
    if (v == null) return '--';
    return '$v $unit';
  }
}

class _Row {
  final String label;
  final String value;
  const _Row(this.label, this.value);
}