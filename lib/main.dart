import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart' as ul;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';

const kOsmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// ====== ENTRY POINT ======
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final auth = FirebaseAuthRepo(); // pakai Firebase
  runApp(MyApp(auth: auth));
}

/// ====== APP ROOT ======
class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.auth});
  final AuthRepo auth;

  // warna brand SiBejo
  static const kGreen = Color(0xFF00878A);
  static const kYellow = Color(0xFFFFC107);
  static const kSurface = Color(0xFFF7F8F2);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SiBejo Rescue',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kGreen,
          primary: kGreen,
          secondary: kYellow,
          brightness: Brightness.light,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      routes: {
        '/': (_) => SplashPage(auth: auth),
        '/login': (_) => LoginPage(auth: auth),
        '/home': (_) => HomePage(auth: auth),
        '/shelters': (_) => const SheltersPage(),
        '/data': (_) => const DataProcessingPage(),
        '/profile': (_) => const ProfilePage(),
        '/report': (_) => const ReportPage(),
        '/nearest': (_) => const NearestShelterPage(),
      },
    );
  }
}

/// ====== UTIL: SnackBar helper (seragam) ======
void showSnack(BuildContext context, String message, {bool error = false}) {
  final c = error ? Colors.red.shade700 : MyApp.kGreen;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        elevation: error ? 0 : 1,
        backgroundColor: error ? Colors.red.shade50 : c.withOpacity(.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.withOpacity(.25)),
        ),
        content: Row(
          children: [
            Icon(error ? Icons.error_outline : Icons.check_circle_outline,
                color: c),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: c, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        action: error
            ? SnackBarAction(label: 'OK', textColor: c, onPressed: () {})
            : null,
        duration: const Duration(seconds: 3),
      ),
    );
}

/// ====== KONTRAK AUTH ======
abstract class AuthRepo {
  bool get isLoggedIn;
  Future<void> login(String email, String password);
  Future<void> logout();
  Stream<User?> authStateChanges();
}

/// ====== IMPLEMENTASI AUTH: FIREBASE ======
class FirebaseAuthRepo implements AuthRepo {
  final FirebaseAuth _fa = FirebaseAuth.instance;
  @override
  bool get isLoggedIn => _fa.currentUser != null;
  @override
  Stream<User?> authStateChanges() => _fa.authStateChanges();

  @override
  Future<void> login(String email, String password) async {
    try {
      await _fa.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapFirebaseErr(e));
    }
  }

  @override
  Future<void> logout() => _fa.signOut();

  String _mapFirebaseErr(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Format email tidak valid';
      case 'user-not-found':
        return 'Akun tidak ditemukan';
      case 'wrong-password':
        return 'Password salah';
      case 'user-disabled':
        return 'Akun dinonaktifkan';
      case 'too-many-requests':
        return 'Terlalu banyak percobaan, coba lagi nanti';
      case 'network-request-failed':
        return 'Jaringan bermasalah';
      default:
        return 'Login gagal: ${e.code}';
    }
  }
}

/// ====== SPLASH ======
class SplashPage extends StatefulWidget {
  const SplashPage({super.key, required this.auth});
  final AuthRepo auth;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    widget.auth.authStateChanges().listen((user) {
      final next = (user != null) ? '/home' : '/login';
      if (mounted) {
        Navigator.pushReplacementNamed(context, next);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

/// ====== LOGIN PAGE ======
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.auth});
  final AuthRepo auth;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pass = _pass.text;
    final emailOk = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

    if (!_formKey.currentState!.validate()) {
      if (!emailOk) {
        showSnack(context, 'Ups, format email belum pas.', error: true);
      } else if (pass.length < 6) {
        showSnack(context, 'Password minimal 6 karakter.', error: true);
      } else {
        showSnack(context, 'Mohon periksa kembali isian formulir kamu.',
            error: true);
      }
      return;
    }

    setState(() => _loading = true);
    try {
      await widget.auth.login(email, pass);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString().replaceFirst('Exception: ', ''),
          error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 12),
                      Image.asset('assets/sibejo.png', width: 175, height: 175),
                      const SizedBox(height: 30),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                          helperText: 'Contoh: bejo@gmail.com',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty)
                            return 'Ups, emailnya belum diisi 🙂';
                          final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch(v.trim());
                          return ok ? null : 'Emailnya belum benar';
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _pass,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(_obscure
                                ? Icons.visibility
                                : Icons.visibility_off),
                          ),
                        ),
                        validator: (v) => (v == null || v.length < 6)
                            ? 'Minimal 6 karakter'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _submit,
                          icon: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.login),
                          label: Text(_loading ? 'Signing in...' : 'Login'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: MyApp.kGreen,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _loading ? null : () {},
                        child: const Text('Lupa password?'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================
// HomePage
// =============================
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.auth});
  final AuthRepo auth;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _initLoading = true;

  // ⬇️ pemicu remount anak + fungsi refresh
  int _reloadTick = 0;
  Future<void> _refreshHome() async {
    setState(() => _reloadTick++); // remount HomeMapCard & grid
    await Future.delayed(
        const Duration(milliseconds: 250)); // biar indikator terlihat sebentar
  }

  @override
  void initState() {
    super.initState();
    _initHome();
  }

  Future<void> _initHome() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() => _initLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_initLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Loading data…'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            Image.asset(
              'assets/sibejo_horizontal.png',
              height: 50,
              errorBuilder: (_, __, ___) => Text(
                'SiBejo Rescue',
                style: Theme.of(context).textTheme.titleMedium!.copyWith(
                      color: MyApp.kGreen,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshHome, // ⬅️ tombol reload
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await widget.auth.logout();
              if (!mounted) return;
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),

      // ⬇️ Pull-to-refresh + scroll container
      body: RefreshIndicator(
        onRefresh: _refreshHome,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // remount peta saat _reloadTick berubah
              KeyedSubtree(
                key: ValueKey(_reloadTick),
                child: const HomeMapCard(),
              ),
              const SizedBox(height: 16),

              // grid di dalam scroll
              LayoutBuilder(
                builder: (context, c) {
                  final cross = c.maxWidth >= 720 ? 3 : 2;
                  return GridView.count(
                    crossAxisCount: cross,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.05,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _menuCard(
                        icon: Icons.home_work_outlined,
                        title: 'Shelter',
                        subtitle: 'Tambah & lihat lokasi',
                        onTap: () => Navigator.pushNamed(context, '/shelters'),
                      ),
                      _menuCard(
                        icon: Icons.near_me_outlined,
                        title: 'Shelter Terdekat',
                        subtitle: 'Arahkan saya',
                        onTap: () => Navigator.pushNamed(context,
                            '/nearest'), // ganti ke route yg kamu pakai
                      ),
                      _menuCard(
                        icon: Icons.analytics_outlined,
                        title: 'Olah Data Longsor',
                        subtitle: 'Sensor & laporan',
                        onTap: () => Navigator.pushNamed(context, '/data'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),

      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20), topRight: Radius.circular(20)),
        child: Container(
          color: MyApp.kGreen,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('SiBejo Rescue',
                      style: TextStyle(
                          color: Colors.white70, fontWeight: FontWeight.w600)),
                  TextButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/profile'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.white.withOpacity(.25)),
                      ),
                    ),
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Profil'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // gaya menu modern: ikon bulat + teks, tanpa card solid
  Widget _menuCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    final fg = MyApp.kGreen;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        splashColor: fg.withOpacity(.12),
        highlightColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fg.withOpacity(.10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, size: 26, color: fg),
              ),
              const SizedBox(height: 5),
              Text(
                title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: Colors.black.withOpacity(.55)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// ======================================
/// Map Card + Tabs
/// ======================================
class HomeMapCard extends StatelessWidget {
  const HomeMapCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: DefaultTabController(
        length: 2,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(height: 4),
            TabBar(
              indicatorSize: TabBarIndicatorSize.label,
              tabs: [
                Tab(icon: Icon(Icons.home_work_outlined), text: 'Shelter'),
                Tab(icon: Icon(Icons.terrain_outlined), text: 'Analisis'),
              ],
            ),
            SizedBox(
              height: 220,
              child: TabBarView(
                physics: NeverScrollableScrollPhysics(),
                children: [
                  ShelterMapTab(),
                  AnalysisMapTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ShelterMapTab extends StatefulWidget {
  const ShelterMapTab({super.key});
  @override
  State<ShelterMapTab> createState() => _ShelterMapTabState();
}

enum _Base { osm, sat }

class _ShelterMapTabState extends State<ShelterMapTab>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  final MapController _c = MapController();

  static const _indoCenter = ll.LatLng(-0.789275, 113.921327);
  static const _indoZoom = 4.0;

  _Base _base = _Base.osm;
  List<ll.LatLng> _shelterPts = const [];

  ll.LatLng _curCenter = _indoCenter;
  double _curZoom = _indoZoom;
  late final AnimationController _anim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650));

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  // === utils
  double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim().replaceAll(',', '.'));
    return null;
  }

  void _snack(String msg) {
    final c = Colors.black87;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.black.withOpacity(.15)),
        ),
        content: Row(children: [
          Icon(Icons.info_outline, color: c),
          const SizedBox(width: 12),
          Expanded(child: Text(msg, style: TextStyle(color: c))),
        ]),
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _animateTo(ll.LatLng target, double targetZoom,
      {Duration duration = const Duration(milliseconds: 650),
      Curve curve = Curves.easeInOutCubic}) async {
    _anim.duration = duration;
    final lat = Tween<double>(begin: _curCenter.latitude, end: target.latitude)
        .animate(CurvedAnimation(parent: _anim, curve: curve));
    final lon =
        Tween<double>(begin: _curCenter.longitude, end: target.longitude)
            .animate(CurvedAnimation(parent: _anim, curve: curve));
    final zm = Tween<double>(begin: _curZoom, end: targetZoom)
        .animate(CurvedAnimation(parent: _anim, curve: curve));

    void tick() => _c.move(ll.LatLng(lat.value, lon.value), zm.value);
    _anim
      ..removeListener(tick)
      ..addListener(tick);
    await _anim.forward(from: 0);
    _anim.removeListener(tick);
  }

  ll.LatLng _avg(List<ll.LatLng> pts) {
    double la = 0, lo = 0;
    for (final p in pts) {
      la += p.latitude;
      lo += p.longitude;
    }
    return ll.LatLng(la / pts.length, lo / pts.length);
  }

  void _fitToShelters() async {
    if (_shelterPts.isEmpty) {
      _snack('Belum ada data shelter.');
      return;
    }
    if (_shelterPts.length == 1) {
      await _animateTo(_shelterPts.first, 15);
      return;
    }
    final center = _avg(_shelterPts);
    await _animateTo(center, (_curZoom < 8 ? 8 : _curZoom));
    final b = LatLngBounds.fromPoints(_shelterPts);
    _c.fitCamera(
        CameraFit.bounds(bounds: b, padding: const EdgeInsets.all(24)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('shelters')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Stack(
      children: [
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snap) {
            final docs = snap.data?.docs ?? const [];
            final markers = <Marker>[];
            final pts = <ll.LatLng>[];

            for (final d in docs) {
              final m = d.data();
              final lon = _asDouble(m['lon']);
              final lat = _asDouble(m['lat']);
              if (lon == null || lat == null) continue;

              final p = ll.LatLng(lat, lon);
              pts.add(p);
              markers.add(
                Marker(
                  point: p,
                  width: 44,
                  height: 44,
                  child: const Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(Icons.location_pin, size: 40, color: Colors.white),
                      Icon(Icons.location_pin, size: 34, color: Colors.teal),
                    ],
                  ),
                ),
              );
            }
            _shelterPts = pts;

            return FlutterMap(
              mapController: _c,
              options: MapOptions(
                initialCenter: _indoCenter,
                initialZoom: _indoZoom,
                minZoom: 0,
                maxZoom: 19,
                onMapEvent: (ev) {
                  // penting untuk animasi
                  _curCenter = ev.camera.center;
                  _curZoom = ev.camera.zoom;
                },
              ),
              children: [
                // basemap: OSM saat _base==osm, Esri saat sat
                if (_base == _Base.osm)
                  TileLayer(
                    urlTemplate:
                        'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                    userAgentPackageName: 'id.sibejo.sibejo_rescue',
                  )
                else
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  ),

                MarkerLayer(markers: markers),

                RichAttributionWidget(
                  attributions: [
                    if (_base == _Base.osm)
                      const TextSourceAttribution(
                          '© OpenStreetMap contributors')
                    else
                      const TextSourceAttribution(
                        'Imagery © Esri — Esri, Maxar, Earthstar Geographics, and the GIS User Community',
                      ),
                  ],
                ),
              ],
            );
          },
        ),

        // badge jumlah shelter
        Positioned(
          right: 12,
          top: 10,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(FirebaseAuth.instance.currentUser!.uid)
                .collection('shelters')
                .snapshots(),
            builder: (c, s) {
              final n = s.data?.docs.length ?? 0;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(blurRadius: 6, color: Colors.black12)
                  ],
                ),
                child: Text('Shelter: $n',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              );
            },
          ),
        ),

        // toggle basemap
        Positioned(
          left: 10,
          bottom: 10,
          child: FloatingActionButton.small(
            heroTag: 'toggle_base',
            backgroundColor: Colors.white,
            foregroundColor: MyApp.kGreen,
            tooltip: 'Ganti basemap',
            onPressed: () => setState(() {
              _base = _base == _Base.osm ? _Base.sat : _Base.osm;
            }),
            child: Icon(_base == _Base.osm
                ? Icons.map_outlined
                : Icons.satellite_alt_outlined),
          ),
        ),

        // fokus shelter (animated)
        Positioned(
          right: 66,
          bottom: 10,
          child: FloatingActionButton.small(
            heroTag: 'fit_shelters',
            onPressed: _fitToShelters,
            tooltip: 'Fokus Shelter',
            backgroundColor: Colors.white,
            foregroundColor: MyApp.kGreen,
            child: const Icon(Icons.center_focus_strong),
          ),
        ),

        // lokasi saya (animated)
        Positioned(
          right: 10,
          bottom: 10,
          child: FloatingActionButton.small(
            heroTag: 'shelter_loc',
            onPressed: () async {
              final me = await _getMyLocation();
              if (me != null) await _animateTo(me, 16);
            },
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }
}

class AnalysisMapTab extends StatefulWidget {
  const AnalysisMapTab({super.key});
  @override
  State<AnalysisMapTab> createState() => _AnalysisMapTabState();
}

class _AnalysisMapTabState extends State<AnalysisMapTab>
    with AutomaticKeepAliveClientMixin {
  final MapController _c = MapController();
  static const _fallbackCenter = ll.LatLng(-7.8249, 110.0830);
  bool _didFit = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('analyses')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Stack(
      children: [
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snap) {
            final docs = snap.data?.docs ?? const [];
            final markers = docs.map((d) {
              final m = d.data();
              final lon = _toDouble(m['x']) ?? 0;
              final lat = _toDouble(m['y']) ?? 0;
              final sf = _toDouble(m['sf']) ?? 0;
              final color = sf < 1
                  ? Colors.red
                  : (sf < 1.3 ? Colors.orange : Colors.green);
              return Marker(
                point: ll.LatLng(lat, lon),
                width: 28,
                height: 28,
                child: Icon(Icons.place, size: 24, color: color),
              );
            }).toList();

            final center =
                markers.isNotEmpty ? markers.first.point : _fallbackCenter;

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_didFit && markers.length >= 2) {
                final b = LatLngBounds.fromPoints(
                    markers.map((e) => e.point).toList());
                _c.fitCamera(CameraFit.bounds(
                    bounds: b, padding: const EdgeInsets.all(24)));
                _didFit = true;
              }
            });

            return FlutterMap(
              mapController: _c,
              options: MapOptions(initialCenter: center, initialZoom: 13),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'id.sibejo.sibejo_rescue',
                ),
                if (markers.isNotEmpty) MarkerLayer(markers: markers),
              ],
            );
          },
        ),
        Positioned(
          right: 10,
          bottom: 10,
          child: FloatingActionButton.small(
            heroTag: 'analysis_loc',
            onPressed: () async {
              final me = await _getMyLocation();
              if (me != null) _c.move(me, 16);
            },
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }
}

// ==== Helpers map / parse
double? _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim().replaceAll(',', '.'));
  return null;
}

Widget _badge(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
        border: Border.all(color: Colors.black12),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );

/// ====== MODEL RINGAN (Analisis) ======
class SlopeRecord {
  final String id;
  final double x, y;
  final double tinggi, lebar;
  final double sudutKemiringan, sudutGesek;
  final double kohesi, sf;
  final String? potensi;
  final DateTime? createdAt;

  SlopeRecord({
    required this.id,
    required this.x,
    required this.y,
    required this.tinggi,
    required this.lebar,
    required this.sudutKemiringan,
    required this.sudutGesek,
    required this.kohesi,
    required this.sf,
    this.potensi,
    this.createdAt,
  });

  factory SlopeRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    final t = m['createdAt'];
    return SlopeRecord(
      id: d.id,
      x: _toDouble(m['x']) ?? 0,
      y: _toDouble(m['y']) ?? 0,
      tinggi: _toDouble(m['tinggi']) ?? 0,
      lebar: _toDouble(m['lebar']) ?? 0,
      sudutKemiringan: _toDouble(m['sudutKemiringan']) ?? 0,
      sudutGesek: _toDouble(m['sudutGesek']) ?? 0,
      kohesi: _toDouble(m['kohesi']) ?? 0,
      sf: _toDouble(m['sf']) ?? 0,
      potensi: m['potensi'] as String?,
      createdAt: t is Timestamp ? t.toDate() : null,
    );
  }
}

/// ====== HALAMAN: OLAH DATA ======
class DataProcessingPage extends StatelessWidget {
  const DataProcessingPage({super.key});

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('analyses');

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final q = _col(user.uid).orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Olah Data Longsor'),
        actions: [
          IconButton(
            tooltip: 'Laporan',
            icon: const Icon(Icons.insert_chart_outlined),
            onPressed: () => Navigator.pushNamed(context, '/report'),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return _emptyState(context);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final r = SlopeRecord.fromDoc(docs[i]);
              return Dismissible(
                key: ValueKey(r.id),
                background: Container(
                  decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Icon(Icons.delete_outline, color: Colors.red.shade700),
                ),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Hapus data?'),
                          content:
                              const Text('Data ini akan dihapus permanen.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Batal')),
                            TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Hapus')),
                          ],
                        ),
                      ) ??
                      false;
                },
                onDismissed: (_) => _col(user.uid).doc(r.id).delete(),
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    title: Text(
                      '(${r.x.toStringAsFixed(6)}, ${r.y.toStringAsFixed(6)})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'Tinggi ${r.tinggi.toStringAsFixed(0)} m • Lebar ${r.lebar.toStringAsFixed(0)} m\n'
                      'Kemiringan ${r.sudutKemiringan.toStringAsFixed(0)}° • Gesek ${r.sudutGesek.toStringAsFixed(0)}° • Kohesi ${r.kohesi.toStringAsFixed(0)} kPa',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: MyApp.kGreen.withOpacity(.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: MyApp.kGreen.withOpacity(.25)),
                          ),
                          child: Text('SF ${r.sf.toStringAsFixed(3)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(height: 4),
                        Text(r.potensi ?? 'Potensi: -',
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    onTap: () {
                      final ref = docs[i].reference;
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => EditRecordPage(docRef: ref)));
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: MyApp.kGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Data'),
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const AddRecordPage())),
      ),
    );
  }

  Widget _emptyState(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.table_rows_rounded,
                  size: 56, color: Colors.black.withOpacity(.3)),
              const SizedBox(height: 12),
              const Text('Belum ada data',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Klik tombol “Tambah Data” untuk mulai menganalisis',
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

// ===== Helpers: validator angka + builder field =====
typedef R = String? Function(String? v);

R rangeValidator(String label, {double? min, double? max}) => (String? v) {
      final s = (v ?? '').trim().replaceAll(',', '.');
      final d = double.tryParse(s);
      if (d == null) return '$label harus angka';
      if (min != null && d < min) return '$label minimal $min';
      if (max != null && d > max) return '$label maksimal $max';
      return null;
    };

double? parseNum(String v) => double.tryParse(v.trim().replaceAll(',', '.'));

InputDecoration dec(String label, {String? suffix}) =>
    InputDecoration(labelText: label, suffixText: suffix);

class MapPreview extends StatelessWidget {
  const MapPreview({super.key, required this.lon, required this.lat});
  final double lon; // x (longitude)
  final double lat; // y (latitude)

  @override
  Widget build(BuildContext context) {
    final ll.LatLng center = ll.LatLng(lat, lon); // (lat, lon)

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 180,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: 14,
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'id.sibejo.sibejo_rescue',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: center,
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.location_pin,
                      size: 36, color: Colors.red),
                ),
              ],
            ),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('© OpenStreetMap contributors')
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<ll.LatLng?> _getMyLocation() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return null;
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied) return null;
  }
  if (perm == LocationPermission.deniedForever) return null;

  final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high);
  return ll.LatLng(pos.latitude, pos.longitude);
}

class PickLocationPage extends StatefulWidget {
  const PickLocationPage({super.key, required this.initial});
  final ll.LatLng initial; // pusat awal peta (fallback)

  @override
  State<PickLocationPage> createState() => _PickLocationPageState();
}

class _PickLocationPageState extends State<PickLocationPage> {
  final MapController _mapController = MapController();
  ll.LatLng? _picked;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerToMyLocation());
  }

  Future<void> _centerToMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final me = await _getMyLocation();
      if (!mounted) return;
      final target = me ?? widget.initial;
      _mapController.move(target, 16);
      setState(() {
        _picked ??= target;
      });
      if (me == null) {
        showSnack(
            context, 'Lokasi tidak tersedia. Pastikan GPS & izin lokasi aktif.',
            error: true);
      }
    } catch (_) {
      if (!mounted) return;
      showSnack(context, 'Gagal mendapatkan lokasi.', error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih Lokasi di Peta'),
        actions: [
          IconButton(
            tooltip: 'Lokasi saya',
            onPressed: _locating ? null : _centerToMyLocation,
            icon: _locating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location),
          ),
        ],
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: widget.initial,
          initialZoom: 14,
          onTap: (tapPos, point) => setState(() => _picked = point),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'id.sibejo.sibejo_rescue',
          ),
          if (_picked != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: _picked!,
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.location_pin,
                      size: 38, color: Colors.red),
                ),
              ],
            ),
          const RichAttributionWidget(attributions: [
            TextSourceAttribution('© OpenStreetMap contributors')
          ]),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed:
            _picked == null ? null : () => Navigator.pop(context, _picked),
        icon: const Icon(Icons.check),
        label: const Text('Pakai Titik Ini'),
      ),
      bottomNavigationBar: (_picked == null)
          ? null
          : SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(blurRadius: 8, color: Colors.black12)
                  ],
                ),
                child: Text(
                  'Lon: ${_picked!.longitude.toStringAsFixed(6)}  •  Lat: ${_picked!.latitude.toStringAsFixed(6)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
    );
  }
}

/// ====== FORM: TAMBAH DATA ANALISIS ======
class AddRecordPage extends StatefulWidget {
  const AddRecordPage({super.key});
  @override
  State<AddRecordPage> createState() => _AddRecordPageState();
}

class _AddRecordPageState extends State<AddRecordPage> {
  final _f = GlobalKey<FormState>();
  final _x = TextEditingController(), _y = TextEditingController();
  final _tinggi = TextEditingController(), _lebar = TextEditingController();
  final _kem = TextEditingController(), _gesek = TextEditingController();
  final _kohesi = TextEditingController(), _sf = TextEditingController();
  String? _potensi;
  bool _saving = false;

  @override
  void dispose() {
    _x.dispose();
    _y.dispose();
    _tinggi.dispose();
    _lebar.dispose();
    _kem.dispose();
    _gesek.dispose();
    _kohesi.dispose();
    _sf.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_f.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('analyses')
          .add({
        'x': parseNum(_x.text),
        'y': parseNum(_y.text),
        'tinggi': parseNum(_tinggi.text),
        'lebar': parseNum(_lebar.text),
        'sudutKemiringan': parseNum(_kem.text),
        'sudutGesek': parseNum(_gesek.text),
        'kohesi': parseNum(_kohesi.text),
        'sf': parseNum(_sf.text),
        'potensi': _potensi ?? 'Belum dihitung',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Data tersimpan');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, 'Gagal menyimpan: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lon = parseNum(_x.text);
    final lat = parseNum(_y.text);
    final showMap = lon != null && lat != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Tambah Data Analisis')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _f,
            onChanged: () => setState(() {}),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _x,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration: dec('Koordinat x (Lon)'),
                        validator:
                            rangeValidator('Koordinat x', min: -180, max: 180),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _y,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration: dec('Koordinat y (Lat)'),
                        validator:
                            rangeValidator('Koordinat y', min: -90, max: 90),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Pilih di peta'),
                    onPressed: () async {
                      final lon = parseNum(_x.text);
                      final lat = parseNum(_y.text);
                      final start = (lon != null && lat != null)
                          ? ll.LatLng(lat, lon)
                          : const ll.LatLng(-7.8249, 110.0830);
                      final picked = await Navigator.push<ll.LatLng?>(
                        context,
                        MaterialPageRoute(
                            builder: (_) => PickLocationPage(initial: start)),
                      );
                      if (picked != null) {
                        _x.text =
                            picked.longitude.toStringAsFixed(6); // X = lon
                        _y.text = picked.latitude.toStringAsFixed(6); // Y = lat
                        setState(() {});
                      }
                    },
                  ),
                ),
                if (showMap) ...[
                  const SizedBox(height: 12),
                  MapPreview(lon: lon!, lat: lat!),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _tinggi,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: dec('Tinggi', suffix: 'm'),
                        validator: rangeValidator('Tinggi', min: 0, max: 200),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lebar,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: dec('Lebar', suffix: 'm'),
                        validator: rangeValidator('Lebar', min: 0, max: 500),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _kem,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: dec('Sudut kemiringan', suffix: '°'),
                        validator:
                            rangeValidator('Sudut kemiringan', min: 0, max: 90),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _gesek,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: dec('Sudut gesek internal', suffix: '°'),
                        validator: rangeValidator('Sudut gesek internal',
                            min: 0, max: 60),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _kohesi,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: dec('Kohesi (c)', suffix: 'kPa'),
                        validator: rangeValidator('Kohesi', min: 0, max: 500),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _sf,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: dec('SF'),
                        validator: rangeValidator('SF', min: 0, max: 5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: dec('Potensi Longsor (sementara)'),
                  items: const [
                    DropdownMenuItem(value: 'Tinggi', child: Text('Tinggi')),
                    DropdownMenuItem(value: 'Sedang', child: Text('Sedang')),
                    DropdownMenuItem(value: 'Rendah', child: Text('Rendah')),
                    DropdownMenuItem(
                        value: 'Belum dihitung', child: Text('Belum dihitung')),
                  ],
                  value: _potensi,
                  onChanged: (v) => setState(() => _potensi = v),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Menyimpan…' : 'Simpan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MyApp.kGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EditRecordPage extends StatefulWidget {
  const EditRecordPage({super.key, required this.docRef});
  final DocumentReference<Map<String, dynamic>> docRef;

  @override
  State<EditRecordPage> createState() => _EditRecordPageState();
}

class _EditRecordPageState extends State<EditRecordPage> {
  final _f = GlobalKey<FormState>();
  final _x = TextEditingController(), _y = TextEditingController();
  final _tinggi = TextEditingController(), _lebar = TextEditingController();
  final _kem = TextEditingController(), _gesek = TextEditingController();
  final _kohesi = TextEditingController(), _sf = TextEditingController();
  String? _potensi;

  bool _loading = true, _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await widget.docRef.get();
    final m = d.data()!;
    setState(() {
      _x.text = '${m['x']}';
      _y.text = '${m['y']}';
      _tinggi.text = '${m['tinggi']}';
      _lebar.text = '${m['lebar']}';
      _kem.text = '${m['sudutKemiringan']}';
      _gesek.text = '${m['sudutGesek']}';
      _kohesi.text = '${m['kohesi']}';
      _sf.text = '${m['sf']}';
      _potensi = m['potensi'] as String?;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _x.dispose();
    _y.dispose();
    _tinggi.dispose();
    _lebar.dispose();
    _kem.dispose();
    _gesek.dispose();
    _kohesi.dispose();
    _sf.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_f.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.docRef.update({
        'x': parseNum(_x.text),
        'y': parseNum(_y.text),
        'tinggi': parseNum(_tinggi.text),
        'lebar': parseNum(_lebar.text),
        'sudutKemiringan': parseNum(_kem.text),
        'sudutGesek': parseNum(_gesek.text),
        'kohesi': parseNum(_kohesi.text),
        'sf': parseNum(_sf.text),
        'potensi': _potensi ?? 'Belum dihitung',
      });
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Perubahan disimpan');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, 'Gagal menyimpan: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final lon = parseNum(_x.text);
    final lat = parseNum(_y.text);
    final showMap = lon != null && lat != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Data Analisis')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _f,
            onChanged: () => setState(() {}),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _x,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration: dec('Koordinat x (Lon)'),
                        validator:
                            rangeValidator('Koordinat x', min: -180, max: 180),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _y,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration: dec('Koordinat y (Lat)'),
                        validator:
                            rangeValidator('Koordinat y', min: -90, max: 90),
                      ),
                    ),
                  ],
                ),
                if (showMap) ...[
                  const SizedBox(height: 12),
                  MapPreview(lon: lon!, lat: lat!),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _tinggi,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: dec('Tinggi', suffix: 'm'),
                        validator: rangeValidator('Tinggi', min: 0, max: 200),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lebar,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: dec('Lebar', suffix: 'm'),
                        validator: rangeValidator('Lebar', min: 0, max: 500),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _kem,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: dec('Sudut kemiringan', suffix: '°'),
                        validator:
                            rangeValidator('Sudut kemiringan', min: 0, max: 90),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _gesek,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: dec('Sudut gesek internal', suffix: '°'),
                        validator: rangeValidator('Sudut gesek internal',
                            min: 0, max: 60),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _kohesi,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: dec('Kohesi (c)', suffix: 'kPa'),
                        validator: rangeValidator('Kohesi', min: 0, max: 500),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _sf,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: dec('SF'),
                        validator: rangeValidator('SF', min: 0, max: 5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: dec('Potensi Longsor (sementara)'),
                  value: _potensi,
                  items: const [
                    DropdownMenuItem(value: 'Tinggi', child: Text('Tinggi')),
                    DropdownMenuItem(value: 'Sedang', child: Text('Sedang')),
                    DropdownMenuItem(value: 'Rendah', child: Text('Rendah')),
                    DropdownMenuItem(
                        value: 'Belum dihitung', child: Text('Belum dihitung')),
                  ],
                  onChanged: (v) => setState(() => _potensi = v),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Menyimpan…' : 'Simpan Perubahan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MyApp.kGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ====== LAPORAN ======
class ReportPage extends StatelessWidget {
  const ReportPage({super.key});

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('analyses');

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final stream = _col(uid).orderBy('createdAt', descending: true).snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Analisis'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => _exportCsv(context, uid),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('Belum ada data'));
          }

          int nT = 0, nS = 0, nR = 0, nB = 0;
          double sumSf = 0;
          for (final d in docs) {
            final m = d.data();
            final p = (m['potensi'] ?? '').toString();
            if (p == 'Tinggi') {
              nT++;
            } else if (p == 'Sedang') {
              nS++;
            } else if (p == 'Rendah') {
              nR++;
            } else {
              nB++;
            }
            sumSf += (_toDouble(m['sf']) ?? 0);
          }
          final avgSf = sumSf / docs.length;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _statCard('Total Data', docs.length.toString(), Icons.table_rows),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _badgeCard('Tinggi', nT, Colors.red)),
                  const SizedBox(width: 8),
                  Expanded(child: _badgeCard('Sedang', nS, Colors.orange)),
                  const SizedBox(width: 8),
                  Expanded(child: _badgeCard('Rendah', nR, Colors.green)),
                ],
              ),
              const SizedBox(height: 8),
              _badgeCard('Belum dihitung', nB, Colors.blueGrey),
              const SizedBox(height: 12),
              _statCard('Rata-rata SF', avgSf.toStringAsFixed(3),
                  Icons.stacked_line_chart),
              const SizedBox(height: 24),
              const Text('10 entri terbaru',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ...docs.take(10).map((d) {
                final m = d.data();
                final dx = _toDouble(m['x']);
                final dy = _toDouble(m['y']);
                final sf = _toDouble(m['sf']) ?? 0;
                return ListTile(
                  title: Text(
                      '(${dx?.toStringAsFixed(6) ?? '-'}, ${dy?.toStringAsFixed(6) ?? '-'})'),
                  subtitle: Text(
                      'SF ${sf.toStringAsFixed(3)} • Potensi ${m['potensi'] ?? '-'}'),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _statCard(String title, String value, IconData ic) => Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: MyApp.kGreen.withOpacity(.12),
            child: Icon(ic, color: MyApp.kGreen),
          ),
          title: Text(title),
          trailing: Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ),
      );

  Widget _badgeCard(String label, int n, Color c) => Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: c, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(label),
              ]),
              Text('$n', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );

  Future<void> _exportCsv(BuildContext context, String uid) async {
    try {
      final snap = await _col(uid).orderBy('createdAt', descending: true).get();
      final rows = <List<dynamic>>[
        [
          'x',
          'y',
          'tinggi',
          'lebar',
          'sudutKemiringan',
          'sudutGesek',
          'kohesi',
          'sf',
          'potensi',
          'createdAt'
        ],
      ];
      for (final d in snap.docs) {
        final m = d.data();
        rows.add([
          m['x'],
          m['y'],
          m['tinggi'],
          m['lebar'],
          m['sudutKemiringan'],
          m['sudutGesek'],
          m['kohesi'],
          m['sf'],
          m['potensi'],
          (m['createdAt'] as Timestamp?)?.toDate().toIso8601String(),
        ]);
      }
      final csv = const ListToCsvConverter().convert(rows);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/sibejo_analisis.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles([XFile(file.path)],
          text: 'Export data analisis (CSV)');
    } catch (e) {
      showSnack(context, 'Export gagal: $e', error: true);
    }
  }
}

/// ====== PROFILE PAGE ======
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _form = GlobalKey<FormState>();
  final _cur = TextEditingController();
  final _new = TextEditingController();
  final _new2 = TextEditingController();

  bool _ob1 = true, _ob2 = true, _ob3 = true;
  bool _loading = false;
  late final String _email;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _email = user?.email ?? '-';
  }

  @override
  void dispose() {
    _cur.dispose();
    _new.dispose();
    _new2.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_form.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      showSnack(context, 'Sesi tidak valid. Silakan login ulang.', error: true);
      return;
    }

    setState(() => _loading = true);
    try {
      final cred =
          EmailAuthProvider.credential(email: user.email!, password: _cur.text);
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(_new.text);

      showSnack(context, 'Password berhasil diperbarui ✅');
      _cur.clear();
      _new.clear();
      _new2.clear();
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
          showSnack(context, 'Password saat ini salah.', error: true);
          break;
        case 'weak-password':
          showSnack(
              context, 'Password baru terlalu lemah (minimal 6 karakter).',
              error: true);
          break;
        case 'requires-recent-login':
          showSnack(context, 'Keamanan: silakan login ulang lalu coba lagi.',
              error: true);
          break;
        default:
          showSnack(context, 'Gagal memperbarui password: ${e.code}',
              error: true);
      }
    } catch (e) {
      showSnack(context, 'Terjadi kesalahan. Coba lagi.', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil User')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: MyApp.kGreen.withOpacity(.15),
                      child: Icon(Icons.person, color: MyApp.kGreen),
                    ),
                    title: const Text('Email'),
                    subtitle: Text(_email),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Ganti Password',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _cur,
                  obscureText: _ob1,
                  decoration: InputDecoration(
                    labelText: 'Password saat ini',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _ob1 = !_ob1),
                      icon:
                          Icon(_ob1 ? Icons.visibility : Icons.visibility_off),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Wajib diisi' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _new,
                  obscureText: _ob2,
                  decoration: InputDecoration(
                    labelText: 'Password baru',
                    prefixIcon: const Icon(Icons.lock_reset),
                    helperText: 'Minimal 6 karakter',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _ob2 = !_ob2),
                      icon:
                          Icon(_ob2 ? Icons.visibility : Icons.visibility_off),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.length < 6) return 'Minimal 6 karakter';
                    if (v == _cur.text)
                      return 'Password baru tidak boleh sama dengan yang lama';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _new2,
                  obscureText: _ob3,
                  decoration: InputDecoration(
                    labelText: 'Konfirmasi password baru',
                    prefixIcon: const Icon(Icons.lock_person_outlined),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _ob3 = !_ob3),
                      icon:
                          Icon(_ob3 ? Icons.visibility : Icons.visibility_off),
                    ),
                  ),
                  validator: (v) =>
                      (v != _new.text) ? 'Konfirmasi tidak cocok' : null,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _changePassword,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: Text(_loading ? 'Menyimpan…' : 'Simpan Password'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MyApp.kGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ====== SHELTER ======

// Model Shelter ringkas
class Shelter {
  final String id;
  final String name;
  final double lon; // X
  final double lat; // Y
  final DateTime? createdAt;
  Shelter({
    required this.id,
    required this.name,
    required this.lon,
    required this.lat,
    this.createdAt,
  });
  factory Shelter.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    final t = m['createdAt'];
    return Shelter(
      id: d.id,
      name: (m['name'] ?? '') as String,
      lon: _toDouble(m['lon']) ?? 0,
      lat: _toDouble(m['lat']) ?? 0,
      createdAt: t is Timestamp ? t.toDate() : null,
    );
  }
}

class SheltersPage extends StatelessWidget {
  const SheltersPage({super.key});

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('shelters');

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final q = _col(uid).orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Shelter')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.home_work_outlined,
                        size: 56, color: Colors.black.withOpacity(.3)),
                    const SizedBox(height: 12),
                    const Text('Belum ada shelter',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text(
                        'Tekan “Tambah Shelter” untuk menambahkan lokasi.'),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = docs[i];
              final s = Shelter.fromDoc(d);
              return Dismissible(
                key: ValueKey(s.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Hapus shelter?'),
                          content: Text('“${s.name}” akan dihapus.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Batal')),
                            TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Hapus')),
                          ],
                        ),
                      ) ??
                      false;
                },
                onDismissed: (_) => _col(uid).doc(s.id).delete(),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.delete_outline, color: Colors.red.shade700),
                ),
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    title: Text(s.name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        'Lon ${s.lon.toStringAsFixed(6)} • Lat ${s.lat.toStringAsFixed(6)}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => EditShelterPage(docRef: d.reference)),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: MyApp.kGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_home_work_outlined),
        label: const Text('Tambah Shelter'),
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const AddShelterPage())),
      ),
    );
  }
}

class AddShelterPage extends StatefulWidget {
  const AddShelterPage({super.key});
  @override
  State<AddShelterPage> createState() => _AddShelterPageState();
}

class _AddShelterPageState extends State<AddShelterPage> {
  final _f = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _lon = TextEditingController();
  final _lat = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _lon.dispose();
    _lat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_f.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('shelters')
          .add({
        'name': _name.text.trim(),
        'lon': parseNum(_lon.text),
        'lat': parseNum(_lat.text),
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Shelter tersimpan');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, 'Gagal menyimpan: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lon = parseNum(_lon.text);
    final lat = parseNum(_lat.text);
    final showMap = lon != null && lat != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Tambah Shelter')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _f,
            onChanged: () => setState(() {}),
            child: Column(
              children: [
                TextFormField(
                  controller: _name,
                  decoration: dec('Nama shelter'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _lon,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration: dec('Longitude (X)'),
                        validator:
                            rangeValidator('Longitude', min: -180, max: 180),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lat,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration: dec('Latitude (Y)'),
                        validator:
                            rangeValidator('Latitude', min: -90, max: 90),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Pilih di peta'),
                    onPressed: () async {
                      final start = (lon != null && lat != null)
                          ? ll.LatLng(lat, lon)
                          : const ll.LatLng(-7.8249, 110.0830);
                      final picked = await Navigator.push<ll.LatLng?>(
                        context,
                        MaterialPageRoute(
                            builder: (_) => PickLocationPage(initial: start)),
                      );
                      if (picked != null) {
                        _lon.text = picked.longitude.toStringAsFixed(6);
                        _lat.text = picked.latitude.toStringAsFixed(6);
                        setState(() {});
                      }
                    },
                  ),
                ),
                if (showMap) ...[
                  const SizedBox(height: 12),
                  MapPreview(lon: lon!, lat: lat!),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Menyimpan…' : 'Simpan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MyApp.kGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EditShelterPage extends StatefulWidget {
  const EditShelterPage({super.key, required this.docRef});
  final DocumentReference<Map<String, dynamic>> docRef;

  @override
  State<EditShelterPage> createState() => _EditShelterPageState();
}

class _EditShelterPageState extends State<EditShelterPage> {
  final _f = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _lon = TextEditingController();
  final _lat = TextEditingController();
  bool _loading = true, _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await widget.docRef.get();
    final m = d.data()!;
    setState(() {
      _name.text = (m['name'] ?? '').toString();
      _lon.text = '${m['lon']}';
      _lat.text = '${m['lat']}';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _lon.dispose();
    _lat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_f.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.docRef.update({
        'name': _name.text.trim(),
        'lon': parseNum(_lon.text),
        'lat': parseNum(_lat.text),
      });
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Perubahan disimpan');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, 'Gagal menyimpan: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final lon = parseNum(_lon.text), lat = parseNum(_lat.text);
    final showMap = lon != null && lat != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Shelter')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _f,
            onChanged: () => setState(() {}),
            child: Column(
              children: [
                TextFormField(
                  controller: _name,
                  decoration: dec('Nama shelter'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _lon,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration: dec('Longitude (X)'),
                        validator:
                            rangeValidator('Longitude', min: -180, max: 180),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lat,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration: dec('Latitude (Y)'),
                        validator:
                            rangeValidator('Latitude', min: -90, max: 90),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Pilih di peta'),
                    onPressed: () async {
                      final start = (lon != null && lat != null)
                          ? ll.LatLng(lat!, lon!)
                          : const ll.LatLng(-7.8249, 110.0830);
                      final picked = await Navigator.push<ll.LatLng?>(
                        context,
                        MaterialPageRoute(
                            builder: (_) => PickLocationPage(initial: start)),
                      );
                      if (picked != null) {
                        _lon.text = picked.longitude.toStringAsFixed(6);
                        _lat.text = picked.latitude.toStringAsFixed(6);
                        setState(() {});
                      }
                    },
                  ),
                ),
                if (showMap) ...[
                  const SizedBox(height: 12),
                  MapPreview(lon: lon!, lat: lat!),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Menyimpan…' : 'Simpan Perubahan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MyApp.kGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NearestShelterPage extends StatefulWidget {
  const NearestShelterPage({super.key});

  @override
  State<NearestShelterPage> createState() => _NearestShelterPageState();
}

class _NearestShelterPageState extends State<NearestShelterPage> {
  final MapController _map = MapController();

  ll.LatLng? _me; // posisi saya
  ll.LatLng? _dest; // tujuan (shelter terdekat)
  DocumentSnapshot<Map<String, dynamic>>? _nearestDoc;
  double? _nearestKm;
  bool _loading = true;
  bool _mapReady = false; // penting: map siap

  // --- helper snack lokal (ganti showSnack lama) ---
  void _snack(String msg, {bool error = false}) {
    final c = error ? Colors.red.shade700 : MyApp.kGreen;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? Colors.red.shade50 : c.withOpacity(.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color: (error ? Colors.red.shade200 : c.withOpacity(.25))),
          ),
          content: Row(children: [
            Icon(error ? Icons.error_outline : Icons.check_circle_outline,
                color: c),
            const SizedBox(width: 12),
            Expanded(
                child: Text(msg,
                    style: TextStyle(color: c, fontWeight: FontWeight.w600))),
          ]),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  // --- format jarak dinamis ---
  String _formatDistance(ll.LatLng? a, ll.LatLng? b) {
    if (a == null || b == null) return '—';
    final m = const ll.Distance().distance(a, b); // meter
    if (m < 1000) return '${m.toStringAsFixed(0)} m';
    return '${(m / 1000).toStringAsFixed(2)} km';
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _fitIfPossible() {
    if (!_mapReady || _me == null) return;
    if (_dest != null) {
      _map.fitCamera(
        CameraFit.coordinates(
          coordinates: [_me!, _dest!],
          padding: const EdgeInsets.all(32),
        ),
      );
    } else {
      _map.move(_me!, 15);
    }
  }

  Future<void> _init() async {
    try {
      // 1) posisi user
      final me = await _getMyLocation();
      if (!mounted) return;

      if (me == null) {
        setState(() => _loading = false);
        _snack('Lokasi tidak tersedia. Pastikan GPS & izin lokasi aktif.',
            error: true);
        return;
      }

      // 2) ambil shelters
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('shelters')
          .get();

      // DEBUG: cek isi Firestore
      for (final d in snap.docs) {
        print('Shelter: ${d.id}, data: ${d.data()}');
      }

      if (snap.docs.isEmpty) {
        setState(() {
          _me = me;
          _nearestDoc = null;
          _nearestKm = null;
          _dest = null;
          _loading = false;
        });
        _snack('Belum ada data shelter.', error: true);
        return;
      }

      // 3) hitung terdekat
      final dist = const ll.Distance();
      DocumentSnapshot<Map<String, dynamic>>? bestDoc;
      double bestMeters = double.infinity;

      for (final d in snap.docs) {
        final m = d.data();
        final lon = _toDouble(m['lon']);
        final lat = _toDouble(m['lat']);
        if (lon == null || lat == null) continue;

        final meters = dist.distance(me, ll.LatLng(lat, lon));
        if (meters < bestMeters) {
          bestMeters = meters;
          bestDoc = d;
        }
      }

      // 4) set state + simpan destinasi (jangan langsung fit)
      setState(() {
        _me = me;
        _nearestDoc = bestDoc;
        _nearestKm = (bestMeters.isFinite) ? bestMeters / 1000.0 : null;
        _dest = (bestDoc != null)
            ? ll.LatLng(
                _toDouble(bestDoc.data()!['lat'])!,
                _toDouble(bestDoc.data()!['lon'])!,
              )
            : null;
        _loading = false;
      });

      _fitIfPossible(); // akan jalan kalau map sudah ready
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Gagal memuat data: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final d = _nearestDoc;

    return Scaffold(
      appBar: AppBar(title: const Text('Shelter Terdekat')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (me == null)
              ? const Center(child: Text('Lokasi tidak tersedia.'))
              : Column(
                  children: [
                    // Kartu info
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: MyApp.kGreen.withOpacity(.12),
                            child: Icon(Icons.near_me_outlined,
                                color: MyApp.kGreen),
                          ),
                          title: Text(
                            d != null
                                ? (d.data()?['name'] ?? '(Tanpa nama)')
                                : 'Tidak ditemukan',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            (d != null)
                                ? 'Perkiraan jarak: ${_formatDistance(_me, _dest)}'
                                : '—',
                          ),
                          trailing: ElevatedButton.icon(
                            onPressed: (d != null) ? () => _openRoute(d) : null,
                            icon: const Icon(Icons.directions),
                            label: const Text('Buka Rute'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: MyApp.kGreen,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Peta
                    Expanded(
                      child: FlutterMap(
                        mapController: _map,
                        options: MapOptions(
                          initialCenter: me,
                          initialZoom: 15,
                          onMapReady: () {
                            _mapReady = true;
                            _fitIfPossible();
                          },
                        ),
                        children: [
                          TileLayer(
                            // pakai endpoint tunggal OSM (tanpa subdomain)
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'id.sibejo.sibejo_rescue',
                          ),
                          MarkerLayer(
                            markers: [
                              if (me != null)
                                Marker(
                                  point: me,
                                  width: 36,
                                  height: 36,
                                  child: const Icon(Icons.my_location,
                                      size: 28, color: Colors.blue),
                                ),
                              if (_dest != null)
                                Marker(
                                  point: _dest!,
                                  width: 40,
                                  height: 40,
                                  child: const Icon(Icons.location_pin,
                                      size: 36, color: Colors.red),
                                ),
                            ],
                          ),
                          if (me != null && _dest != null)
                            PolylineLayer(
                              polylines: [
                                Polyline(points: [me, _dest!], strokeWidth: 3)
                              ],
                            ),
                          const RichAttributionWidget(
                            attributions: [
                              TextSourceAttribution(
                                  '© OpenStreetMap contributors')
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Future<void> _openRoute(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final m = doc.data()!;
    final lat = _toDouble(m['lat']);
    final lon = _toDouble(m['lon']);
    if (lat == null || lon == null) {
      _snack('Koordinat shelter tidak valid.', error: true);
      return;
    }

    // 1) Google Maps turn-by-turn
    final nav = Uri.parse('google.navigation:q=$lat,$lon&mode=d');
    if (await ul.launchUrl(nav,
        mode: ul.LaunchMode.externalNonBrowserApplication)) return;

    // 2) Skema geo:
    final geo = Uri.parse('geo:$lat,$lon?q=$lat,$lon(Shelter)');
    if (await ul.launchUrl(geo,
        mode: ul.LaunchMode.externalNonBrowserApplication)) return;

    // 3) Fallback web Google Maps
    final web = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=driving');
    if (await ul.launchUrl(web, mode: ul.LaunchMode.externalApplication))
      return;
    if (await ul.launchUrl(web, mode: ul.LaunchMode.platformDefault)) return;

    // 4) (opsional) Apple Maps
    final apple = Uri.parse('http://maps.apple.com/?daddr=$lat,$lon');
    if (await ul.launchUrl(apple, mode: ul.LaunchMode.externalApplication))
      return;
    if (await ul.launchUrl(apple, mode: ul.LaunchMode.platformDefault)) return;

    _snack('Tidak bisa membuka aplikasi peta.', error: true);
  }
}
