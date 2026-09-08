import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Login fields ──────────────────────────────
  final _loginEmail    = TextEditingController();
  final _loginPassword = TextEditingController();
  bool   _loginLoading = false;
  String _loginError   = '';
  bool   _loginObscure = true;

  // ── Signup Step 0 – Credentials ───────────────
  final _signupEmail    = TextEditingController();
  final _signupPassword = TextEditingController();
  final _signupConfirm  = TextEditingController();
  bool _signupObscure   = true;

  // ── Signup Step 1 – Role ──────────────────────
  String _selectedRole = ''; // 'patient' or 'doctor'

  // ── Signup Step 2 – Patient Info ──────────────
  final _signupName    = TextEditingController();
  final _signupDob     = TextEditingController();
  final _signupPhone   = TextEditingController();
  final _signupAddress = TextEditingController();
  String _selectedGender       = 'Male';
  String _selectedDiabetesType = 'Type 1';

  // ── Signup Step 3 – Emergency Contact ─────────
  final _ecName         = TextEditingController();
  final _ecRelationship = TextEditingController();
  final _ecPhone        = TextEditingController();

  // ── Signup state ──────────────────────────────
  int    _signupStep    = 0;
  bool   _signupLoading = false;
  String _signupError   = '';

  // ── Static options ────────────────────────────
  final List<String> _genders       = ['Male', 'Female', 'Other'];
  final List<String> _diabetesTypes = ['Type 1', 'Type 2', 'Gestational', 'Other'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _signupStep  = 0;
          _signupError = '';
          _loginError  = '';
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmail.dispose();    _loginPassword.dispose();
    _signupEmail.dispose();   _signupPassword.dispose();  _signupConfirm.dispose();
    _signupName.dispose();    _signupDob.dispose();       _signupPhone.dispose();
    _signupAddress.dispose();
    _ecName.dispose();        _ecRelationship.dispose();  _ecPhone.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════
  // AUTH ACTIONS
  // ════════════════════════════════════════════════

  Future<void> _login() async {
    if (_loginEmail.text.trim().isEmpty || _loginPassword.text.trim().isEmpty) {
      setState(() => _loginError = 'Please fill in all fields');
      return;
    }
    setState(() { _loginLoading = true; _loginError = ''; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _loginEmail.text.trim(),
        password: _loginPassword.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _loginError = _friendlyAuthError(e.code));
    } finally {
      if (mounted) setState(() => _loginLoading = false);
    }
  }

  bool _validateStep(int step) {
    setState(() => _signupError = '');
    switch (step) {
      case 0:
        if (_signupEmail.text.trim().isEmpty ||
            _signupPassword.text.trim().isEmpty ||
            _signupConfirm.text.trim().isEmpty) {
          setState(() => _signupError = 'Please fill in all fields');
          return false;
        }
        if (_signupPassword.text != _signupConfirm.text) {
          setState(() => _signupError = 'Passwords do not match');
          return false;
        }
        if (_signupPassword.text.length < 6) {
          setState(() => _signupError = 'Password must be at least 6 characters');
          return false;
        }
        return true;
      case 1:
        if (_selectedRole.isEmpty) {
          setState(() => _signupError = 'Please select a role');
          return false;
        }
        return true;
      case 2:
        if (_signupName.text.trim().isEmpty ||
            _signupDob.text.trim().isEmpty  ||
            _signupPhone.text.trim().isEmpty ||
            _signupAddress.text.trim().isEmpty) {
          setState(() => _signupError = 'Please fill in all fields');
          return false;
        }
        return true;
      case 3:
        if (_ecName.text.trim().isEmpty        ||
            _ecRelationship.text.trim().isEmpty ||
            _ecPhone.text.trim().isEmpty) {
          setState(() => _signupError = 'Please fill in all emergency contact details');
          return false;
        }
        return true;
    }
    return true;
  }

  Future<void> _signup() async {
    setState(() { _signupLoading = true; _signupError = ''; });
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _signupEmail.text.trim(),
        password: _signupPassword.text.trim(),
      );
      final uid = cred.user!.uid;
      final db  = FirebaseFirestore.instance;

      // Always write patients doc (role field used for routing)
      await db.collection('patients').doc(uid).set({
        'patientID'    : uid,
        'name'         : _signupName.text.trim().isNotEmpty ? _signupName.text.trim() : _signupEmail.text.trim().split('@').first,
        'email'        : _signupEmail.text.trim(),
        'dateOfBirth'  : _signupDob.text.trim(),
        'gender'       : _selectedGender,
        'phone'        : _signupPhone.text.trim(),
        'address'      : _signupAddress.text.trim(),
        'diabetesType' : _selectedDiabetesType,
        'role'         : _selectedRole,
        'doctorId'     : '',
        'doctorName'   : '',
        'createdAt'    : FieldValue.serverTimestamp(),
      });

      if (_selectedRole == 'patient') {
        await db.collection('medicalProfiles').doc(uid).set({
          'patientID'        : uid,
          'targetGlucoseMin' : null,
          'targetGlucoseMax' : null,
          'insulinType'      : null,
          'basalRate'        : null,
          'doctorID'         : null,
          'createdAt'        : FieldValue.serverTimestamp(),
        });
        await db.collection('emergencyContacts').doc(uid).set({
          'patientID'    : uid,
          'name'         : _ecName.text.trim(),
          'relationship' : _ecRelationship.text.trim(),
          'phone'        : _ecPhone.text.trim(),
        });
      } else {
        // Doctor collection
        await db.collection('doctors').doc(uid).set({
          'name'             : _signupEmail.text.trim().split('@').first,
          'email'            : _signupEmail.text.trim(),
          'assignedPatients' : [],
          'createdAt'        : FieldValue.serverTimestamp(),
        });
      }
    } on FirebaseAuthException catch (e) {
      setState(() { _signupError = _friendlyAuthError(e.code); _signupStep = 0; });
    } catch (e) {
      setState(() => _signupError = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _signupLoading = false);
    }
  }

  String _friendlyAuthError(String code) {
    switch (code) {
      case 'user-not-found':         return 'No account found with this email';
      case 'wrong-password':         return 'Incorrect password';
      case 'email-already-in-use':   return 'This email is already registered';
      case 'invalid-email':          return 'Invalid email address';
      case 'weak-password':          return 'Password is too weak';
      case 'network-request-failed': return 'No internet connection';
      default:                       return 'Authentication failed. Try again.';
    }
  }

  // ════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 52),
              _logo(),
              const SizedBox(height: 40),
              _tabBar(),
              const SizedBox(height: 24),
              AnimatedBuilder(
                animation: _tabController,
                builder: (_, __) {
                  final isLogin = _tabController.index == 0;
                  return SizedBox(
                    height: isLogin ? 300 : _signupStepHeight(),
                    child: TabBarView(
                      controller: _tabController,
                      children: [_loginForm(), _signupBody()],
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  double _signupStepHeight() {
    switch (_signupStep) {
      case 0: return 370;
      case 1: return 400; // role picker
      case 2: return 500;
      case 3: return 360;
      default: return 400;
    }
  }

  // ════════════════════════════════════════════════
  // LOGO
  // ════════════════════════════════════════════════

  Widget _logo() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF4FC3F7).withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.monitor_heart, size: 64, color: Color(0xFF4FC3F7)),
        ),
        const SizedBox(height: 16),
        const Text('DiASync',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 6),
        const Text('Automated Insulin Delivery System',
            style: TextStyle(color: Colors.white38, fontSize: 13)),
      ],
    );
  }

  // ════════════════════════════════════════════════
  // TAB BAR
  // ════════════════════════════════════════════════

  Widget _tabBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: const Color(0xFF4FC3F7),
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.black87,
        unselectedLabelColor: Colors.white54,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        dividerColor: Colors.transparent,
        tabs: const [Tab(text: 'Login'), Tab(text: 'Sign Up')],
      ),
    );
  }

  // ════════════════════════════════════════════════
  // LOGIN FORM
  // ════════════════════════════════════════════════

  Widget _loginForm() {
    return Column(
      children: [
        _field(controller: _loginEmail, hint: 'Email',
            icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 14),
        _field(controller: _loginPassword, hint: 'Password',
            icon: Icons.lock_outlined,
            obscure: _loginObscure,
            toggle: () => setState(() => _loginObscure = !_loginObscure)),
        if (_loginError.isNotEmpty) ...[
          const SizedBox(height: 10),
          _errorText(_loginError),
        ],
        const SizedBox(height: 20),
        _button('Login', _loginLoading, _login),
        const SizedBox(height: 14),
        TextButton(
          onPressed: _showForgotPassword,
          child: const Text('Forgot Password?',
              style: TextStyle(color: Color(0xFF4FC3F7), fontSize: 13)),
        ),
      ],
    );
  }

  void _showForgotPassword() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D2E),
        title: const Text('Reset Password', style: TextStyle(color: Colors.white)),
        content: _field(controller: ctrl, hint: 'Email',
            icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () async {
              if (ctrl.text.trim().isNotEmpty) {
                await FirebaseAuth.instance
                    .sendPasswordResetEmail(email: ctrl.text.trim());
              }
              if (mounted) Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reset email sent if account exists')),
              );
            },
            child: const Text('Send', style: TextStyle(color: Color(0xFF4FC3F7))),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════
  // SIGNUP – STEP WRAPPER
  // ════════════════════════════════════════════════

  Widget _signupBody() {
    return Column(
      children: [
        _stepIndicator(),
        const SizedBox(height: 20),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: KeyedSubtree(
              key: ValueKey(_signupStep),
              child: _signupStepContent(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepIndicator() {
    // Doctor only has 2 steps (0 and 1), patient has 4
    final titles = _selectedRole == 'doctor'
        ? ['Account', 'Role']
        : ['Account', 'Role', 'Info', 'Emergency'];
    final total = titles.length;
    final currentDisplay = _signupStep.clamp(0, total - 1);

    return Row(
      children: List.generate(total, (i) {
        final active = i == currentDisplay;
        final done   = i < currentDisplay;
        final color  = done || active ? const Color(0xFF4FC3F7) : Colors.white24;
        return Expanded(
          child: Row(
            children: [
              if (i > 0)
                Expanded(child: Container(height: 1, color: done ? const Color(0xFF4FC3F7) : Colors.white24)),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFF4FC3F7) : (done ? const Color(0xFF4FC3F7).withOpacity(0.3) : Colors.white10),
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 1.5),
                    ),
                    child: Center(
                      child: done
                          ? const Icon(Icons.check, size: 14, color: Color(0xFF4FC3F7))
                          : Text('${i + 1}',
                              style: TextStyle(
                                  color: active ? Colors.black : Colors.white54,
                                  fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(titles[i],
                      style: TextStyle(
                          color: active ? const Color(0xFF4FC3F7) : Colors.white38,
                          fontSize: 10)),
                ],
              ),
              if (i < total - 1)
                Expanded(child: Container(height: 1, color: done ? const Color(0xFF4FC3F7) : Colors.white24)),
            ],
          ),
        );
      }),
    );
  }

  Widget _signupStepContent() {
    switch (_signupStep) {
      case 0: return _signupStep0();
      case 1: return _signupStep1Role();
      case 2: return _signupStep2Info();
      case 3: return _signupStep3Emergency();
      default: return const SizedBox();
    }
  }

  // ── Step 0: Credentials ───────────────────────

  Widget _signupStep0() {
    return Column(
      children: [
        _field(controller: _signupEmail, hint: 'Email',
            icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 14),
        _field(controller: _signupPassword, hint: 'Password',
            icon: Icons.lock_outlined,
            obscure: _signupObscure,
            toggle: () => setState(() => _signupObscure = !_signupObscure)),
        const SizedBox(height: 14),
        _field(controller: _signupConfirm, hint: 'Confirm Password',
            icon: Icons.lock_outlined, obscure: _signupObscure),
        if (_signupError.isNotEmpty) ...[
          const SizedBox(height: 10),
          _errorText(_signupError),
        ],
        const SizedBox(height: 20),
        _button('Next', false, () {
          if (_validateStep(0)) setState(() => _signupStep = 1);
        }),
      ],
    );
  }

  // ── Step 1: Role Picker ───────────────────────

  Widget _signupStep1Role() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('I am a...', style: TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 16),
        _roleCard('patient', 'Patient',
            'Monitor glucose & receive automated insulin doses',
            Icons.favorite_border),
        const SizedBox(height: 12),
        _roleCard('doctor', 'Doctor',
            'Manage patients, view data & set insulin parameters',
            Icons.medical_services_outlined),
        if (_signupError.isNotEmpty) ...[
          const SizedBox(height: 10),
          _errorText(_signupError),
        ],
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: _button('Back', false,
              () => setState(() { _signupStep = 0; _signupError = ''; }),
              color: Colors.white24, textColor: Colors.white70)),
          const SizedBox(width: 12),
          Expanded(child: _button(
            _selectedRole == 'doctor' ? 'Create Account' : 'Next',
            _signupLoading,
            () async {
              if (!_validateStep(1)) return;
              if (_selectedRole == 'doctor') {
                await _signup();
              } else {
                setState(() => _signupStep = 2);
              }
            },
            color: _selectedRole == 'doctor' ? const Color(0xFF66BB6A) : const Color(0xFF4FC3F7),
          )),
        ]),
      ],
    );
  }

  Widget _roleCard(String value, String title, String subtitle, IconData icon) {
    final selected = _selectedRole == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4FC3F7).withOpacity(0.12) : const Color(0xFF1A1D2E),
          border: Border.all(
            color: selected ? const Color(0xFF4FC3F7) : Colors.white12,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF4FC3F7).withOpacity(0.2) : Colors.white10,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: selected ? const Color(0xFF4FC3F7) : Colors.white38, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(
                color: selected ? const Color(0xFF4FC3F7) : Colors.white,
                fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ])),
          if (selected) const Icon(Icons.check_circle, color: Color(0xFF4FC3F7), size: 20),
        ]),
      ),
    );
  }

  // ── Step 2: Patient Info ──────────────────────

  Widget _signupStep2Info() {
    return Column(
      children: [
        _field(controller: _signupName, hint: 'Full Name', icon: Icons.person_outlined),
        const SizedBox(height: 12),
        _datePicker(),
        const SizedBox(height: 12),
        _dropdown(
          label: 'Gender',
          value: _selectedGender,
          items: _genders,
          onChanged: (v) => setState(() => _selectedGender = v!),
        ),
        const SizedBox(height: 12),
        _field(controller: _signupPhone, hint: 'Phone Number',
            icon: Icons.phone_outlined, keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        _field(controller: _signupAddress, hint: 'Address', icon: Icons.home_outlined),
        const SizedBox(height: 12),
        _dropdown(
          label: 'Diabetes Type',
          value: _selectedDiabetesType,
          items: _diabetesTypes,
          onChanged: (v) => setState(() => _selectedDiabetesType = v!),
        ),
        if (_signupError.isNotEmpty) ...[
          const SizedBox(height: 10),
          _errorText(_signupError),
        ],
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: _button('Back', false,
              () => setState(() { _signupStep = 1; _signupError = ''; }),
              color: Colors.white24, textColor: Colors.white70)),
          const SizedBox(width: 12),
          Expanded(child: _button('Next', false, () {
            if (_validateStep(2)) setState(() => _signupStep = 3);
          })),
        ]),
      ],
    );
  }

  Widget _datePicker() {
    return TextField(
      controller: _signupDob,
      readOnly: true,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Date of Birth',
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: const Icon(Icons.calendar_today_outlined, color: Colors.white38, size: 20),
        filled: true,
        fillColor: const Color(0xFF1A1D2E),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4FC3F7), width: 1.5)),
      ),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime(2000),
          firstDate: DateTime(1920),
          lastDate: DateTime.now(),
          builder: (ctx, child) => Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(primary: Color(0xFF4FC3F7)),
            ),
            child: child!,
          ),
        );
        if (picked != null) {
          _signupDob.text =
              '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
        }
      },
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF1A1D2E),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white38),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: onChanged,
          hint: Text(label, style: const TextStyle(color: Colors.white38)),
        ),
      ),
    );
  }

  // ── Step 3: Emergency Contact ─────────────────

  Widget _signupStep3Emergency() {
    return Column(
      children: [
        _sectionHeader(Icons.emergency_outlined, 'Emergency Contact'),
        const SizedBox(height: 16),
        _field(controller: _ecName, hint: 'Contact Name', icon: Icons.person_outlined),
        const SizedBox(height: 12),
        _field(controller: _ecRelationship, hint: 'Relationship (e.g. Parent)',
            icon: Icons.family_restroom_outlined),
        const SizedBox(height: 12),
        _field(controller: _ecPhone, hint: 'Contact Phone',
            icon: Icons.phone_outlined, keyboardType: TextInputType.phone),
        if (_signupError.isNotEmpty) ...[
          const SizedBox(height: 10),
          _errorText(_signupError),
        ],
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: _button('Back', false,
              () => setState(() { _signupStep = 2; _signupError = ''; }),
              color: Colors.white24, textColor: Colors.white70)),
          const SizedBox(width: 12),
          Expanded(child: _button('Create Account', _signupLoading, () async {
            if (_validateStep(3)) await _signup();
          }, color: const Color(0xFF66BB6A))),
        ]),
      ],
    );
  }

  Widget _sectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF4FC3F7), size: 20),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                color: Color(0xFF4FC3F7),
                fontWeight: FontWeight.bold,
                fontSize: 15)),
      ],
    );
  }

  // ════════════════════════════════════════════════
  // SHARED WIDGETS
  // ════════════════════════════════════════════════

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
    VoidCallback? toggle,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      readOnly: readOnly,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        suffixIcon: toggle != null
            ? IconButton(
                icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white38, size: 20),
                onPressed: toggle)
            : null,
        filled: true,
        fillColor: const Color(0xFF1A1D2E),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4FC3F7), width: 1.5)),
      ),
    );
  }

  Widget _button(String label, bool loading, VoidCallback onTap,
      {Color color = const Color(0xFF4FC3F7), Color textColor = Colors.black87}) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: loading
            ? const SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(color: Colors.black54, strokeWidth: 2.5))
            : Text(label,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: textColor)),
      ),
    );
  }

  Widget _errorText(String msg) => Text(
        msg,
        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
        textAlign: TextAlign.center,
      );
}